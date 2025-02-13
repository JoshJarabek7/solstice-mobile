@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseStorage
@preconcurrency import SwiftUI

// Helper extension for chunking arrays
extension Array {
  func chunked(into size: Int) -> [[Element]] {
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

enum ProfileError: LocalizedError {
  case noUserID

  var errorDescription: String? {
    switch self {
    case .noUserID:
      return "Unable to load profile: No user ID available"
    }
  }
}

actor ListenerStore {
  private(set) var listeners: [@Sendable () -> Void] = []

  func add(_ listener: @Sendable @escaping () -> Void) {
    listeners.append(listener)
  }

  func removeAll() -> [@Sendable () -> Void] {
    let current = listeners
    listeners.removeAll()
    return current
  }
}

@Observable
@MainActor
final class ProfileViewModel {
  // User Data
  var user: User?
  var videos: [Video] = []
  var likedVideos: [Video] = []
  var followers: [User] = []
  var following: [User] = []
  var isLoading = false
  var error: Error?
  var showError = false
  var errorMessage = ""

  // Profile Stats
  var followerCount = 0
  var followingCount = 0
  var isPrivateAccount = false
  var isCurrentUserProfile = false
  var isFollowing = false
  var followRequestSent = false

  // Bookmark Collections
  var bookmarkCollections: [BookmarkCollection] = []
  var selectedBookmarkCollection: BookmarkCollection?
  var showCreateCollectionSheet = false
  var newCollectionName = ""

  private let userId: String
  private let db = Firestore.firestore()
  private let listenerStore = ListenerStore()
  let userViewModel: UserViewModel

  init(userId: String? = nil, userViewModel: UserViewModel) throws {
    print("[DEBUG] ProfileViewModel.init - Starting initialization")
    print("[DEBUG] Input userId: \(String(describing: userId))")
    print(
      "[DEBUG] Current Auth.currentUser?.uid: \(String(describing: Auth.auth().currentUser?.uid))")

    self.userViewModel = userViewModel

    // Get the user ID, throwing an error if none is available
    guard let validUserId = userId ?? Auth.auth().currentUser?.uid else {
      print("[ERROR] No valid userId available for ProfileViewModel")
      throw ProfileError.noUserID
    }

    print("[DEBUG] Using validUserId: \(validUserId)")
    self.userId = validUserId
    self.isCurrentUserProfile = userId == nil || userId == Auth.auth().currentUser?.uid

    Task {
      do {
        print("[DEBUG] Setting up data streams")
        await setupDataStreams()
        print("[DEBUG] Initial data fetch complete")
      } catch {
        print("[ERROR] Error initializing profile: \(error)")
        self.error = error
        self.showError = true
      }
    }
  }

  deinit {
    Task { [listeners = listenerStore] in
      let currentListeners = await listeners.removeAll()
      for listener in currentListeners {
        listener()
      }
    }
  }

  private func setupDataStreams() async {
    // Setup user data listener
    let userRef = db.collection("users").document(userId)
    let userListener = userRef.addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }
      Task {
        do {
          if let data = snapshot?.data() {
            try await self.processUserData(data)
          }
        } catch {
          print("[ERROR] Error processing user data: \(error)")
        }
      }
    }
    await listenerStore.add { userListener.remove() }

    // Setup videos listener
    let videosQuery = db.collection("videos")
      .whereField("creatorId", isEqualTo: userId)
      .order(by: "createdAt", descending: true)

    let videosListener = videosQuery.addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }
      if let error = error {
        print("[ERROR] Error fetching videos: \(error)")
        return
      }

      let videos =
        snapshot?.documents.compactMap { doc -> Video? in
          try? doc.data(as: Video.self)
        } ?? []

      self.videos = videos
    }
    await listenerStore.add { videosListener.remove() }

    // Setup liked videos listener using collection group query
    let likedVideosQuery = db.collectionGroup("likes")
      .whereField("userId", isEqualTo: userId)
      .order(by: "timestamp", descending: true)

    let likedVideosListener = likedVideosQuery.addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }
      Task {
        if let error = error {
          print("[ERROR] Error fetching liked videos: \(error)")
          return
        }

        // Get the parent video IDs
        let videoIds =
          snapshot?.documents.compactMap { doc -> String? in
            doc.reference.parent.parent?.documentID
          } ?? []

        // Fetch the actual videos
        var allVideos: [Video] = []
        for chunk in videoIds.chunked(into: 10) {
          do {
            let videoSnapshot = try await self.db.collection("videos")
              .whereField(FieldPath.documentID(), in: chunk)
              .getDocuments()

            let videos = videoSnapshot.documents.compactMap { doc -> Video? in
              try? doc.data(as: Video.self)
            }
            allVideos.append(contentsOf: videos)
          } catch {
            print("[ERROR] Error fetching video details: \(error)")
          }
        }

        await MainActor.run {
          self.likedVideos = allVideos.sorted { $0.createdAt > $1.createdAt }
        }
      }
    }
    await listenerStore.add { likedVideosListener.remove() }

    // Setup bookmark collections listener
    if isCurrentUserProfile {
      let bookmarksQuery = db.collection("users")
        .document(userId)
        .collection("bookmarkCollections")

      let bookmarksListener = bookmarksQuery.addSnapshotListener { [weak self] snapshot, error in
        guard let self = self else { return }
        if let error = error {
          print("[ERROR] Error fetching bookmarks: \(error)")
          return
        }

        self.bookmarkCollections =
          snapshot?.documents.compactMap { doc in
            try? doc.data(as: BookmarkCollection.self)
          } ?? []
      }
      await listenerStore.add { bookmarksListener.remove() }
    }
  }

  private func processUserData(_ data: [String: Any]) async throws {
    var userData = data
    userData["id"] = userId

    // Handle nested ageRange structure
    if let ageRange = userData["ageRange"] as? [String: Any] {
      userData["ageRange.min"] = ageRange["min"] as? Int ?? 18
      userData["ageRange.max"] = ageRange["max"] as? Int ?? 100
      userData.removeValue(forKey: "ageRange")
    }

    // Handle boolean fields
    for field in ["isDatingEnabled", "isPrivate"] {
      if let value = userData[field] {
        if let boolValue = value as? Bool {
          userData[field] = boolValue
        } else if let intValue = value as? Int {
          userData[field] = (intValue != 0)
        }
      }
    }

    let decoder = Firestore.Decoder()
    decoder.keyDecodingStrategy = .useDefaultKeys

    user = try decoder.decode(User.self, from: userData)
    isPrivateAccount = user?.isPrivate ?? false

    if !isCurrentUserProfile {
      await checkFollowStatus()
    }
  }

  private func checkFollowStatus() async {
    guard let currentUserId = Auth.auth().currentUser?.uid,
      currentUserId != userId
    else {
      print("[DEBUG] checkFollowStatus - Skipping (currentUser is nil or same as profile)")
      return
    }

    do {
      print(
        "[DEBUG] Checking follow status for currentUserId: \(currentUserId) -> targetId: \(userId)")
      // Check if following
      let followDoc = try await db.collection("follows")
        .whereField("followerId", isEqualTo: currentUserId)
        .whereField("followedId", isEqualTo: userId)
        .getDocuments()

      isFollowing = !followDoc.documents.isEmpty
      print("[DEBUG] isFollowing: \(isFollowing)")

      // Check if follow request exists
      let requestDoc = try await db.collection("followRequests")
        .whereField("requesterId", isEqualTo: currentUserId)
        .whereField("targetId", isEqualTo: userId)
        .getDocuments()

      followRequestSent = !requestDoc.documents.isEmpty
      print("[DEBUG] followRequestSent: \(followRequestSent)")
    } catch {
      print("[ERROR] Failed to check follow status: \(error)")
      errorMessage = "Failed to check follow status"
      showError = true
    }
  }

  func fetchContent() async {
    print("[DEBUG] fetchContent - Starting")
    await MainActor.run {
      isLoading = true
      error = nil
      showError = false
    }

    await withTaskGroup(of: Void.self) { group in
      // Fetch videos
      group.addTask {
        print("[DEBUG] Starting video fetch")
        await self.fetchVideos()
      }

      // Fetch liked videos
      group.addTask {
        print("[DEBUG] Starting liked videos fetch")
        await self.fetchLikedVideos()
      }

      // Wait for all tasks to complete
      await group.waitForAll()
      print("[DEBUG] All content fetches complete")
    }

    await MainActor.run {
      isLoading = false
    }
  }

  func refreshContent() async {
    // Clear existing data
    await MainActor.run {
      videos.removeAll()
      likedVideos.removeAll()
      isLoading = true
      error = nil
      showError = false
    }

    // Fetch fresh content
    await fetchContent()
  }

  private func fetchVideos() async {
    print("[DEBUG] fetchVideos - Starting for userId: \(userId)")
    do {
      let snapshot = try await db.collection("videos")
        .whereField("creatorId", isEqualTo: userId)
        .order(by: "createdAt", descending: true)
        .getDocuments()

      let fetchedVideos = try snapshot.documents.compactMap { doc -> Video? in
        try doc.data(as: Video.self)
      }

      print("[DEBUG] Fetched \(fetchedVideos.count) videos")
      await MainActor.run {
        self.videos = fetchedVideos
      }
    } catch {
      print("[ERROR] Error fetching videos: \(error)")
      await MainActor.run {
        self.error = error
        self.showError = true
      }
    }
  }

  private func fetchLikedVideos() async {
    print("[DEBUG] fetchLikedVideos - Starting for userId: \(userId)")
    guard !userId.isEmpty else {
      print("[ERROR] fetchLikedVideos - Empty userId")
      return
    }

    do {
      print("[DEBUG] Fetching videos liked by user: \(userId)")

      // Get all videos where this user has a like document
      let likedVideosQuery = db.collectionGroup("likes")
        .whereField("userId", isEqualTo: userId)
        .order(by: "timestamp", descending: true)

      let likedSnapshot = try await likedVideosQuery.getDocuments()

      // Get the parent video IDs
      let videoIds = likedSnapshot.documents.compactMap { doc -> String? in
        doc.reference.parent.parent?.documentID
      }

      print("[DEBUG] Found \(videoIds.count) liked video IDs")

      // If no liked videos, return empty array
      if videoIds.isEmpty {
        print("[DEBUG] No liked videos found")
        await MainActor.run {
          self.likedVideos = []
        }
        return
      }

      // Fetch the actual videos in batches of 10
      var allVideos: [Video] = []
      for chunk in videoIds.chunked(into: 10) {
        let snapshot = try await db.collection("videos")
          .whereField(FieldPath.documentID(), in: chunk)
          .getDocuments()

        let videos = try snapshot.documents.compactMap { doc -> Video? in
          try doc.data(as: Video.self)
        }
        allVideos.append(contentsOf: videos)
      }

      print("[DEBUG] Successfully fetched \(allVideos.count) liked videos")

      await MainActor.run {
        self.likedVideos = allVideos.sorted { $0.createdAt > $1.createdAt }
      }
    } catch {
      print("[ERROR] Error fetching liked videos: \(error)")
      await MainActor.run {
        self.error = error
        self.showError = true
      }
    }
  }

  func fetchBookmarkCollections() async {
    print("[DEBUG] fetchBookmarkCollections - Starting")
    print("[DEBUG] isCurrentUserProfile: \(isCurrentUserProfile)")
    print("[DEBUG] userId: \(userId)")

    guard isCurrentUserProfile else {
      print("[DEBUG] fetchBookmarkCollections - Skipping (not current user's profile)")
      return
    }

    do {
      print("[DEBUG] Fetching bookmark collections at path: users/\(userId)/bookmarkCollections")
      let snapshot = try await db.collection("users")
        .document(userId)
        .collection("bookmarkCollections")
        .getDocuments()

      bookmarkCollections = try snapshot.documents.compactMap { doc in
        try doc.data(as: BookmarkCollection.self)
      }
      print("[DEBUG] Found \(bookmarkCollections.count) bookmark collections")

      // Create default collection if none exists
      if bookmarkCollections.isEmpty {
        print("[DEBUG] No collections found, creating default collection")
        try await createDefaultBookmarkCollection()
      }
    } catch {
      print("[ERROR] Failed to fetch bookmark collections: \(error)")
      self.error = error
      showError = true
    }
  }

  func createBookmarkCollection() async {
    print("[DEBUG] createBookmarkCollection - Starting")
    print("[DEBUG] newCollectionName: \(newCollectionName)")

    guard !newCollectionName.isEmpty else {
      print("[WARNING] Attempted to create collection with empty name")
      return
    }

    do {
      let collection = BookmarkCollection(
        name: newCollectionName,
        userId: userId,
        isDefault: false,
        videos: []
      )

      print("[DEBUG] Creating collection at path: users/\(userId)/bookmarkCollections")
      try await db.collection("users")
        .document(userId)
        .collection("bookmarkCollections")
        .addDocument(data: try Firestore.Encoder().encode(collection))

      await fetchBookmarkCollections()
      newCollectionName = ""
      showCreateCollectionSheet = false

    } catch {
      print("[ERROR] Failed to create bookmark collection: \(error)")
      self.error = error
      showError = true
    }
  }

  private func createDefaultBookmarkCollection() async throws {
    print("[DEBUG] createDefaultBookmarkCollection - Starting")
    let defaultCollection = BookmarkCollection(
      name: "All Bookmarks",
      userId: userId,
      isDefault: true,
      videos: []
    )

    print("[DEBUG] Creating default collection at path: users/\(userId)/bookmarkCollections")
    try await db.collection("users")
      .document(userId)
      .collection("bookmarkCollections")
      .addDocument(data: try Firestore.Encoder().encode(defaultCollection))
  }

  func deleteBookmarkCollection(_ collection: BookmarkCollection) async {
    guard !collection.isDefault,
      let collectionId = collection.id
    else { return }

    do {
      try await db.collection("users")
        .document(userId)
        .collection("bookmarkCollections")
        .document(collectionId)
        .delete()

      await fetchBookmarkCollections()
    } catch {
      self.error = error
      showError = true
    }
  }

  func toggleFollow() async {
    guard let targetUser = user,
      let targetUserId = targetUser.id,
      let currentUserId = Auth.auth().currentUser?.uid
    else {
      errorMessage = "Unable to update follow status"
      showError = true
      return
    }

    do {
      if targetUser.isPrivate && !isFollowing {
        // Send follow request
        if !followRequestSent {
          try await db.collection("followRequests").addDocument(data: [
            "requesterId": currentUserId,
            "targetId": targetUserId,
            "timestamp": FieldValue.serverTimestamp(),
          ])
          followRequestSent = true
        } else {
          // Cancel follow request
          let request = try await db.collection("followRequests")
            .whereField("requesterId", isEqualTo: currentUserId)
            .whereField("targetId", isEqualTo: targetUserId)
            .getDocuments()

          if let requestDoc = request.documents.first {
            try await requestDoc.reference.delete()
            followRequestSent = false
          }
        }
      } else {
        if isFollowing {
          // Unfollow
          let followDoc = try await db.collection("follows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followedId", isEqualTo: targetUserId)
            .getDocuments()

          if let doc = followDoc.documents.first {
            try await doc.reference.delete()
            isFollowing = false
          }
        } else {
          // Follow
          try await db.collection("follows").addDocument(data: [
            "followerId": currentUserId,
            "followedId": targetUserId,
            "timestamp": FieldValue.serverTimestamp(),
          ])
          isFollowing = true
        }
      }
    } catch {
      errorMessage = "Failed to update follow status"
      showError = true
    }
  }
}
