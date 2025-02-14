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
    print("[DEBUG] -------- Explore Search Start --------")
    print("[DEBUG] Query: '\(query)'")
    print("[DEBUG] Current user ID: \(Auth.auth().currentUser?.uid ?? "nil")")
    print("[DEBUG] Is user signed in: \(Auth.auth().currentUser != nil)")
    
    // Cancel any existing search
    searchTask?.cancel()

    guard !query.isEmpty else {
      searchResults = []
      return
    }

    searchTask = Task {
      isLoading = true
      defer { 
        isLoading = false
        print("[DEBUG] -------- Explore Search End --------")
      }

      do {
        print("[DEBUG] Starting user search")
        let lowercaseQuery = query.lowercased()
        
        // Try a simple query first to test permissions
        print("[DEBUG] Testing permissions with simple query")
        let testQuery = try await db.collection("users")
          .limit(to: 1)
          .getDocuments()
        print("[DEBUG] Permission test successful, got \(testQuery.documents.count) documents")
        
        // Search users with lowercase fields
        print("[DEBUG] Searching users with query: '\(lowercaseQuery)'")
        let usersSnapshot = try await db.collection("users")
          .whereField("username_lowercase", isGreaterThanOrEqualTo: lowercaseQuery)
          .whereField("username_lowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
          .order(by: "username_lowercase")
          .limit(to: 5)
          .getDocuments()

        print("[DEBUG] User search returned \(usersSnapshot.documents.count) results")
        
        let users = try usersSnapshot.documents.compactMap { doc -> User? in
          var data = doc.data()
          data["id"] = doc.documentID
          
          // Handle nested ageRange structure
          if let ageRange = data["ageRange"] as? [String: Any] {
            data["ageRange.min"] = ageRange["min"] as? Int ?? 18
            data["ageRange.max"] = ageRange["max"] as? Int ?? 100
            data.removeValue(forKey: "ageRange")
          }
          
          return try Firestore.Decoder().decode(User.self, from: data)
        }
        print("[DEBUG] Successfully decoded \(users.count) users")

        if !Task.isCancelled {
          searchResults = users.map { .user($0) }
          print("[DEBUG] Total results: \(searchResults.count)")
        }
      } catch {
        print("[ERROR] Search failed with error: \(error)")
        print("[ERROR] Error description: \(error.localizedDescription)")
        if let firestoreError = error as NSError? {
          print("[ERROR] Firestore error code: \(firestoreError.code)")
          print("[ERROR] Firestore error domain: \(firestoreError.domain)")
          print("[ERROR] Firestore error userInfo: \(firestoreError.userInfo)")
        }
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
