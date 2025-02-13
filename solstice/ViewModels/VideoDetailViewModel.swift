import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
final class VideoDetailViewModel: ObservableObject {
  @Published var creator: User?
  @Published var isFollowingCreator = false
  @Published var errorMessage: String?
  @Published var comments: [Comment] = []
  @Published var isLiked = false
  @Published var likeCount: Int = 0
  @Published var commentText = ""

  private let db = Firestore.firestore()
  var currentUserId: String? {
    Auth.auth().currentUser?.uid
  }

  func loadCreator(creatorId: String, videoId: String) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.fetchCreator(creatorId: creatorId) }
      group.addTask { await self.fetchComments(videoId: videoId) }
      group.addTask { await self.checkLikeStatus(videoId: videoId) }
    }
  }

  private func fetchCreator(creatorId: String) async {
    do {
      let snapshot = try await db.collection("users")
        .document(creatorId)
        .getDocument()

      if var data = snapshot.data() {
        // Set the ID before decoding
        data["id"] = creatorId
        
        // Handle nested ageRange structure
        if let ageRange = data["ageRange"] as? [String: Any] {
          data["ageRange.min"] = ageRange["min"] as? Int ?? 18
          data["ageRange.max"] = ageRange["max"] as? Int ?? 100
          data.removeValue(forKey: "ageRange")
        }
        
        // Handle boolean fields
        for field in ["isDatingEnabled", "isPrivate"] {
          if let value = data[field] {
            if let boolValue = value as? Bool {
              data[field] = boolValue
            } else if let intValue = value as? Int {
              data[field] = (intValue != 0)
            }
          }
        }
        
        // Handle arrays
        if let datingImages = data["datingImages"] as? [String] {
          data["datingImages"] = datingImages
        } else {
          data["datingImages"] = [String]()
        }
        
        // Handle timestamps
        if let timestamp = data["createdAt"] as? Timestamp {
          data["createdAt"] = timestamp.dateValue()
        }

        let decoder = Firestore.Decoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        creator = try decoder.decode(User.self, from: data)

        if let currentUserId = currentUserId {
          let followingDoc = try await db.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(creatorId)
            .getDocument()

          isFollowingCreator = followingDoc.exists
        }
      }
    } catch {
      errorMessage = "Failed to load creator: \(error.localizedDescription)"
    }
  }

  func followCreator() async throws {
    guard let currentUserId = currentUserId,
      let creator = creator,
      let creatorId = creator.id
    else { return }

    let followingRef = db.collection("users")
      .document(currentUserId)
      .collection("following")
      .document(creatorId)

    let followerRef = db.collection("users")
      .document(creatorId)
      .collection("followers")
      .document(currentUserId)

    if isFollowingCreator {
      // Unfollow
      try await followingRef.delete()
      try await followerRef.delete()
      isFollowingCreator = false
    } else {
      // Follow
      let timestamp = FieldValue.serverTimestamp()
      try await followingRef.setData(["timestamp": timestamp])
      try await followerRef.setData(["timestamp": timestamp])
      isFollowingCreator = true
    }
  }

  func toggleLike(videoId: String) async throws {
    guard let currentUserId = currentUserId else { return }
    
    // Capture current state
    let wasLiked = isLiked
    
    do {
      // Perform Firebase operations first
      let likeRef = db.collection("videos")
        .document(videoId)
        .collection("likes")
        .document(currentUserId)
      
      let videoRef = db.collection("videos").document(videoId)
      
      // Verify video exists before proceeding
      let videoDoc = try await videoRef.getDocument()
      guard videoDoc.exists else {
        self.errorMessage = "Video not found"
        return
      }
      
      if wasLiked {
        // Unlike
        try await likeRef.delete()
        try await videoRef.updateData([
          "likes": FieldValue.increment(Int64(-1))
        ])
        
        // Update UI after successful server operation
        await MainActor.run {
          self.isLiked = false
          self.likeCount -= 1
        }
      } else {
        // Like
        try await likeRef.setData([
          "timestamp": FieldValue.serverTimestamp(),
          "userId": currentUserId
        ])
        try await videoRef.updateData([
          "likes": FieldValue.increment(Int64(1))
        ])
        
        // Update UI after successful server operation
        await MainActor.run {
          self.isLiked = true
          self.likeCount += 1
        }
      }
    } catch {
      print("Error toggling like: \(error.localizedDescription)")
      self.errorMessage = "Failed to update like status: \(error.localizedDescription)"
      throw error
    }
  }

  private func checkLikeStatus(videoId: String) async {
    guard let currentUserId = currentUserId else { return }

    do {
      let likeDoc = try await db.collection("videos")
        .document(videoId)
        .collection("likes")
        .document(currentUserId)
        .getDocument()

      isLiked = likeDoc.exists

      // Get current like count
      let videoDoc = try await db.collection("videos")
        .document(videoId)
        .getDocument()

      likeCount = videoDoc.data()?["likes"] as? Int ?? 0
    } catch {
      errorMessage = "Failed to check like status"
    }
  }

  func addComment(videoId: String, text: String) async throws {
    guard let currentUserId = currentUserId else { return }
    
    let user = try await db.collection("users")
      .document(currentUserId)
      .getDocument()
    
    let userData = user.data()
    let username = userData?["username"] as? String ?? "Unknown"
    let profileImageURL = userData?["profileImageURL"] as? String
    
    let commentRef = db.collection("videos")
      .document(videoId)
      .collection("comments")
      .document()

    let comment = Comment(
      userId: currentUserId,
      text: text,
      timestamp: Date(),
      username: username,
      userProfileImageURL: profileImageURL
    )

    try commentRef.setData(from: comment)
    
    // Update video's comment count
    try await db.collection("videos")
      .document(videoId)
      .updateData([
        "comments": FieldValue.increment(Int64(1))
      ])

    await MainActor.run {
      comments.insert(comment, at: 0)
      commentText = ""
    }
  }

  private func fetchComments(videoId: String) async {
    do {
      let snapshot = try await db.collection("videos")
        .document(videoId)
        .collection("comments")
        .order(by: "timestamp", descending: true)
        .limit(to: 50)
        .getDocuments()

      var fetchedComments: [Comment] = []
      
      for doc in snapshot.documents {
        if var comment = try? doc.data(as: Comment.self) {
          // Check if the current user has liked this comment
          if let currentUserId = currentUserId {
            let likeDoc = try? await db.collection("videos")
              .document(videoId)
              .collection("comments")
              .document(doc.documentID)
              .collection("likes")
              .document(currentUserId)
              .getDocument()
            
            comment.isLiked = likeDoc?.exists ?? false
          }
          fetchedComments.append(comment)
        }
      }
      
      await MainActor.run {
        self.comments = fetchedComments
      }
    } catch {
      errorMessage = "Failed to fetch comments"
    }
  }

  func toggleCommentLike(videoId: String, commentId: String) async throws {
    guard let currentUserId = currentUserId else { return }
    
    let commentRef = db.collection("videos")
      .document(videoId)
      .collection("comments")
      .document(commentId)
    
    let likeRef = commentRef.collection("likes").document(currentUserId)
    
    // Get current comment
    guard let commentIndex = comments.firstIndex(where: { $0.id == commentId }) else { return }
    let wasLiked = comments[commentIndex].isLiked ?? false
    
    // Optimistically update UI
    await MainActor.run {
      comments[commentIndex].isLiked?.toggle()
      comments[commentIndex].likes += wasLiked ? -1 : 1
    }
    
    do {
      if wasLiked {
        // Unlike
        try await likeRef.delete()
        try await commentRef.updateData([
          "likes": FieldValue.increment(Int64(-1))
        ])
      } else {
        // Like
        try await likeRef.setData([
          "timestamp": FieldValue.serverTimestamp(),
          "userId": currentUserId
        ])
        try await commentRef.updateData([
          "likes": FieldValue.increment(Int64(1))
        ])
      }
    } catch {
      // Revert UI on error
      await MainActor.run {
        comments[commentIndex].isLiked?.toggle()
        comments[commentIndex].likes += wasLiked ? 1 : -1
      }
      throw error
    }
  }
}

#Preview {
  Text("VideoDetailViewModel Preview")
}
