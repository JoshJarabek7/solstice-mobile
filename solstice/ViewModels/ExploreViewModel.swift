import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
  enum ExploreError: LocalizedError {
    case userNotFound
    case followError
    case alreadyFollowing
    case networkError(Error)

    var errorDescription: String? {
      switch self {
      case .userNotFound:
        return "User not found"
      case .followError:
        return "Unable to follow user at this time"
      case .alreadyFollowing:
        return "You are already following this user"
      case .networkError(let error):
        return "Network error: \(error.localizedDescription)"
      }
    }
  }
  @Published var searchResults: [SearchResult] = []
  @Published var suggestedUsers: [User] = []
  @Published var trendingHashtags: [String] = []
  @Published var trendingVideos: [Video] = []
  @Published var isLoading = false
  @Published var errorMessage = ""

  private let db = Firestore.firestore()
  private var searchTask: Task<Void, Never>?

  @Published var isFollowing: [String: Bool] = [:]

  init() {
    Task {
      await fetchTrendingHashtags()
      await fetchSuggestedUsers()
      await fetchTrendingVideos()
    }
  }

  func search(query: String) {
    // Cancel any existing search
    searchTask?.cancel()

    guard !query.isEmpty else {
      searchResults = []
      return
    }

    searchTask = Task {
      isLoading = true
      defer { isLoading = false }

      do {
        // Search users with a simpler query that matches the index
        let usersSnapshot = try await db.collection("users")
          .whereField("username", isGreaterThanOrEqualTo: query.lowercased())
          .whereField("username", isLessThan: query.lowercased() + "\u{f8ff}")
          .order(by: "username")
          .limit(to: 5)
          .getDocuments()

        let users = try usersSnapshot.documents.compactMap { doc -> User? in
          try doc.data(as: User.self)
        }

        // Search hashtags
        let hashtagsSnapshot = try await db.collection("hashtags")
          .whereField("tag", isGreaterThanOrEqualTo: query.lowercased())
          .whereField("tag", isLessThan: query.lowercased() + "\u{f8ff}")
          .order(by: "tag")
          .limit(to: 5)
          .getDocuments()

        let hashtags = hashtagsSnapshot.documents.compactMap { doc -> String in
          doc.data()["tag"] as? String ?? ""
        }

        // Combine results
        if !Task.isCancelled {
          searchResults = users.map { .user($0) } + hashtags.map { .hashtag($0) }
        }
      } catch {
        print("Error searching users:", error)
        errorMessage = "Failed to perform search: \(error.localizedDescription)"
      }
    }
  }

  private func fetchTrendingHashtags() async {
    do {
      let snapshot = try await db.collection("hashtags")
        .order(by: "count", descending: true)
        .limit(to: 10)
        .getDocuments()

      trendingHashtags = snapshot.documents.compactMap { doc in
        doc.data()["tag"] as? String
      }
    } catch {
      errorMessage = "Failed to fetch trending hashtags"
    }
  }

  func followUser(userId: String) async throws {
    print("[DEBUG] followUser - Starting for userId: \(userId)")
    guard let currentUserId = Auth.auth().currentUser?.uid else {
      print("[ERROR] followUser - Missing currentUserId")
      throw NSError(
        domain: "ExploreViewModel", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Current user ID is missing"])
    }
    print("[DEBUG] followUser - currentUserId: \(currentUserId)")

    guard !userId.isEmpty else {
      print("[ERROR] followUser - Empty userId")
      throw NSError(
        domain: "ExploreViewModel", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "User ID to follow is missing"])
    }
    print("[DEBUG] followUser - userId: \(userId)")

    // Check if already following
    if try await isFollowingUser(userId: userId) {
      throw ExploreError.alreadyFollowing
    }

    let followingRef = db.collection("users").document(currentUserId).collection("following")
      .document(userId)
    let followerRef = db.collection("users").document(userId).collection("followers").document(
      currentUserId)

    _ = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      db.runTransaction({ (transaction, errorPointer) -> Any? in
        // Add to following collection
        transaction.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: followingRef)

        // Add to followers collection
        transaction.setData(["timestamp": FieldValue.serverTimestamp()], forDocument: followerRef)

        return nil
      }) { _, error in
        if let error = error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }

    // Update local state
    isFollowing[userId] = true
  }

  private func isFollowingUser(userId: String) async throws -> Bool {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return false }

    let followingRef = db.collection("users")
      .document(currentUserId)
      .collection("following")
      .document(userId)

    let snapshot = try await followingRef.getDocument()
    return snapshot.exists
  }

  private func fetchSuggestedUsers() async {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }

    do {
      // Get current user's interests and activity
      let userDoc = try await db.collection("users")
        .document(currentUserId)
        .getDocument()

      let userData = userDoc.data() ?? [:]
      let interests = (userData["interests"] as? [String]) ?? []

      // Only query by interests if the user has any
      let query = db.collection("users")
        .whereField("id", isNotEqualTo: currentUserId)
        .limit(to: 10)

      let snapshot =
        try await
        (interests.isEmpty
        ? query.getDocuments()
        : query.whereField("interests", arrayContainsAny: interests).getDocuments())

      let users = try snapshot.documents.compactMap { doc -> User? in
        try doc.data(as: User.self)
      }

      // Check following status for each user
      for user in users where user.id != nil {
        isFollowing[user.id!] = try await isFollowingUser(userId: user.id!)
      }

      suggestedUsers = users

    } catch {
      errorMessage = "Failed to fetch suggested users"
    }
  }

  private func fetchTrendingVideos() async {
    do {
      let snapshot = try await db.collection("videos")
        .order(by: "likeCount", descending: true)
        .limit(to: 15)
        .getDocuments()

      let videos = try snapshot.documents.compactMap { doc -> Video? in
        try doc.data(as: Video.self)
      }

      trendingVideos = videos
    } catch {
      errorMessage = "Failed to fetch trending videos"
    }
  }
}

#Preview {
  ExploreView()
}
