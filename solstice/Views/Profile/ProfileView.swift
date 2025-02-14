// ProfileView.swift
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// Public typealias for backward compatibility
typealias ProfileView = ProfileViewContainer

@MainActor
struct ProfileViewContainer: View {
  let userId: String?
  @State private var error: Error?
  @Environment(UserViewModel.self) var userViewModel
  @State private var viewModel: ProfileViewModel?

  var body: some View {
    Group {
      if let error = error {
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 50))
            .foregroundColor(.yellow)
          Text("Unable to load profile")
            .font(.headline)
          Text(error.localizedDescription)
            .font(.subheadline)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .padding()
        }
      } else if let viewModel = viewModel {
        _ProfileView(userId: userId, viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .task {
      guard viewModel == nil else { return }
      do {
        viewModel = try ProfileViewModel(userId: userId, userViewModel: userViewModel)
      } catch {
        self.error = error
      }
    }
  }
}

// Renamed to _ProfileView to indicate it's an implementation detail
@MainActor
struct _ProfileView: View {
  let userId: String?
  let viewModel: ProfileViewModel
  @Environment(UserViewModel.self) var userViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var selectedTab = 0
  @State private var isRefreshing = false
  @Namespace private var tabNamespace

  private var effectiveUserId: String {
    if let specificUserId = userId {
      return specificUserId
    }
    return Auth.auth().currentUser?.uid ?? ""
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      if let displayUser = viewModel.user {
        ProfileContent(
          displayUser: displayUser,
          viewModel: viewModel,
          selectedTab: $selectedTab,
          tabNamespace: tabNamespace,
          effectiveUserId: effectiveUserId
        )
      } else {
        ProgressView()
      }
    }
    .refreshable {
      print("[DEBUG] Starting profile refresh")
      await refreshData()
    }
    .navigationTitle(
      userId == nil ? userViewModel.user.username : (viewModel.user?.username ?? "Profile")
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if userId == nil {
        ToolbarItem(id: "settings", placement: .topBarTrailing) {
          NavigationLink {
            SettingsView()
          } label: {
            Image(systemName: "gearshape.fill")
              .symbolRenderingMode(.hierarchical)
          }
        }
      }
    }
  }

  private func refreshData() async {
    print("[DEBUG] refreshData - Starting refresh")
    print("[DEBUG] userId: \(String(describing: userId))")
    print("[DEBUG] userViewModel.user.id: \(String(describing: userViewModel.user.id))")

    // Refresh user data
    if userId == nil {
      if let currentUser = userViewModel.user.id {
        print("[DEBUG] Refreshing current user data: \(currentUser)")
        try? await userViewModel.loadUser(userId: currentUser)
      } else {
        print("[WARNING] No user ID available for refresh")
      }
    }

    print("[DEBUG] Starting content refresh")
    await viewModel.refreshContent()
    print("[DEBUG] Finished content refresh")
  }
}

private struct ProfileContent: View {
  let displayUser: User
  let viewModel: ProfileViewModel
  @Binding var selectedTab: Int
  var tabNamespace: Namespace.ID
  let effectiveUserId: String

  var body: some View {
    VStack(alignment: .center, spacing: 24) {
      // Profile Header
      ProfileHeaderView(user: displayUser)
        .frame(maxWidth: .infinity)

      // Bio
      if let bio = displayUser.bio {
        Text(bio)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
          .frame(maxWidth: .infinity)
      }

      // Stats Row
      ProfileStatsRow(viewModel: viewModel)

      // Tabs
      ProfileTabBar(
        displayUser: displayUser,
        selectedTab: $selectedTab,
        namespace: tabNamespace
      )

      // Tab Content
      ProfileTabContent(
        selectedTab: selectedTab,
        displayUser: displayUser,
        effectiveUserId: effectiveUserId,
        viewModel: viewModel
      )
    }
  }
}

private struct ProfileStatsRow: View {
  let viewModel: ProfileViewModel

  var body: some View {
    HStack {
      Spacer(minLength: 0)

      VStack(spacing: 8) {
        Text("\(viewModel.videos.count)")
          .font(.headline)
        Text("Posts")
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity)

      VStack(spacing: 8) {
        Text("\(viewModel.followerCount)")
          .font(.headline)
        Text("Followers")
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity)

      VStack(spacing: 8) {
        Text("\(viewModel.followingCount)")
          .font(.headline)
        Text("Following")
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)
    }
    .padding(.horizontal)
    .frame(maxWidth: .infinity)
  }
}

private struct ProfileTabBar: View {
  let displayUser: User
  @Binding var selectedTab: Int
  var namespace: Namespace.ID

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        TabButton(
          title: "Videos",
          isSelected: selectedTab == 0,
          namespace: namespace
        ) {
          withAnimation(.easeInOut) {
            selectedTab = 0
          }
        }

        if displayUser.isDatingEnabled {
          TabButton(
            title: "Dating",
            isSelected: selectedTab == 1,
            namespace: namespace
          ) {
            withAnimation(.easeInOut) {
              selectedTab = 1
            }
          }
        }

        TabButton(
          title: "Likes",
          isSelected: selectedTab == 2,
          namespace: namespace
        ) {
          withAnimation(.easeInOut) {
            selectedTab = 2
          }
        }
      }
      .padding(.horizontal)

      Divider()
    }
    .background(.background)
  }
}

private struct ProfileTabContent: View {
  let selectedTab: Int
  let displayUser: User
  let effectiveUserId: String
  let viewModel: ProfileViewModel

  var body: some View {
    switch selectedTab {
    case 0:
      VideosGridView(userId: effectiveUserId, videos: viewModel.videos)
    case 1 where displayUser.isDatingEnabled:
      DatingProfileSection(user: displayUser)
    case 2:
      LikedVideosGridView(videos: viewModel.likedVideos)
    default:
      EmptyView()
    }
  }
}

struct TabButton: View {
  let title: String
  let isSelected: Bool
  let namespace: Namespace.ID
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        Text(title)
          .font(.subheadline)
          .fontWeight(isSelected ? .semibold : .regular)
          .foregroundColor(isSelected ? .primary : .gray)
          .padding(.vertical, 12)

        // Underline indicator
        Rectangle()
          .fill(isSelected ? Color.blue : Color.clear)
          .frame(height: 3)
          .matchedGeometryEffect(id: "tab_indicator", in: namespace, isSource: isSelected)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

struct ProfileHeaderView: View {
  let user: User
  @State private var showPhotoViewer = false

  var body: some View {
    VStack(alignment: .center, spacing: 16) {
      // Profile Image
      if let imageURL = user.profileImageURL {
        Button {
          showPhotoViewer = true
        } label: {
          AsyncImage(url: URL(string: imageURL)) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            Image(systemName: "person.circle.fill")
              .resizable()
              .foregroundColor(.gray)
          }
          .frame(width: 100, height: 100)
          .clipShape(Circle())
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
          PhotoViewer(imageURL: imageURL, isPresented: $showPhotoViewer)
        }
      } else {
        Image(systemName: "person.circle.fill")
          .resizable()
          .frame(width: 100, height: 100)
          .foregroundColor(.gray)
      }

      // User Info
      VStack(alignment: .center, spacing: 8) {
        if !user.fullName.isEmpty {
          Text(user.fullName)
            .font(.title2)
            .bold()
        }

        if !user.username.isEmpty {
          Text("@\(user.username)")
            .font(.subheadline)
            .foregroundColor(.gray)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top)
  }
}

struct DatingProfileSection: View {
  let user: User
  @State private var showPhotoViewer = false
  @State private var selectedPhotoIndex = 0
  @State private var isLiked: Bool?
  @State private var isLoading = false
  @Environment(UserViewModel.self) private var userViewModel

  private var canInteract: Bool {
    guard let currentUser = Auth.auth().currentUser else { return false }
    return currentUser.uid != user.id  // Not own profile
      && userViewModel.user.isDatingEnabled  // Current user has dating enabled
      && user.isDatingEnabled  // Profile user has dating enabled
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Dating Images
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(user.datingImages.indices, id: \.self) { index in
            Button {
              selectedPhotoIndex = index
              showPhotoViewer = true
            } label: {
              AsyncImage(url: URL(string: user.datingImages[index])) { image in
                image
                  .resizable()
                  .scaledToFill()
              } placeholder: {
                Rectangle()
                  .fill(Color.gray.opacity(0.2))
              }
              .frame(width: 200, height: 300)
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
        }
        .padding(.horizontal)
      }
      .fullScreenCover(isPresented: $showPhotoViewer) {
        PhotoCarouselViewer(
          images: user.datingImages,
          initialIndex: selectedPhotoIndex,
          isPresented: $showPhotoViewer
        )
      }
      // Force view recreation when index changes
      .id("photoViewer_\(selectedPhotoIndex)")

      // Like/Dislike Buttons
      if canInteract {
        HStack(spacing: 20) {
          Spacer()

          // Dislike Button
          Button {
            Task {
              await handleInteraction(like: false)
            }
          } label: {
            Image(systemName: isLiked == false ? "xmark.circle.fill" : "xmark.circle")
              .font(.system(size: 44))
              .foregroundColor(isLiked == false ? .red : .gray)
          }
          .disabled(isLoading)

          // Like Button
          Button {
            Task {
              await handleInteraction(like: true)
            }
          } label: {
            Image(systemName: isLiked == true ? "checkmark.circle.fill" : "checkmark.circle")
              .font(.system(size: 44))
              .foregroundColor(isLiked == true ? .green : .gray)
          }
          .disabled(isLoading)

          Spacer()
        }
        .padding(.vertical)
      }

      // Dating Bio
      if let bio = user.bio {
        VStack(alignment: .leading, spacing: 8) {
          Text("About")
            .font(.headline)
          Text(bio)
            .font(.body)
        }
        .padding(.horizontal)
      }

      // Basic Info
      VStack(alignment: .leading, spacing: 8) {
        Text("Basic Info")
          .font(.headline)

        if let age = user.age {
          HStack {
            Label("Age", systemImage: "calendar")
            Spacer()
            Text("\(age)")
              .foregroundColor(.gray)
          }
        }

        HStack {
          Label("Gender", systemImage: "person.fill")
          Spacer()
          Text(user.gender.rawValue.capitalized)
            .foregroundColor(.gray)
        }

        if !user.interestedIn.isEmpty {
          HStack {
            Label("Interested in", systemImage: "heart.fill")
            Spacer()
            Text(user.interestedIn.map { $0.rawValue.capitalized }.joined(separator: ", "))
              .foregroundColor(.gray)
          }
        }
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
    .task {
      await checkLikeStatus()
    }
  }

  private func checkLikeStatus() async {
    guard canInteract, let userId = user.id else { return }

    do {
      let db = Firestore.firestore()
      let currentUserId = Auth.auth().currentUser?.uid ?? ""

      // Check for like
      let likeDoc = try await db.collection("likes")
        .document("\(currentUserId)_\(userId)")
        .getDocument()

      if likeDoc.exists {
        isLiked = true
        return
      }

      // Check for pass
      let passDoc = try await db.collection("passes")
        .document("\(currentUserId)_\(userId)")
        .getDocument()

      if passDoc.exists {
        isLiked = false
      }
    } catch {
      print("Error checking like status: \(error)")
    }
  }

  private func handleInteraction(like: Bool) async {
    guard canInteract, let userId = user.id else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      let db = Firestore.firestore()
      let currentUserId = Auth.auth().currentUser?.uid ?? ""

      // Remove existing interaction if any
      try await db.collection("likes")
        .document("\(currentUserId)_\(userId)")
        .delete()
      try await db.collection("passes")
        .document("\(currentUserId)_\(userId)")
        .delete()

      // Add new interaction
      if like {
        try await db.collection("likes")
          .document("\(currentUserId)_\(userId)")
          .setData([
            "likerId": currentUserId,
            "likedId": userId,
            "timestamp": FieldValue.serverTimestamp(),
          ])

        // Check for mutual like
        let mutualLike = try await db.collection("likes")
          .document("\(userId)_\(currentUserId)")
          .getDocument()

        if mutualLike.exists {
          // Create match and chat
          let matchData: [String: Any] = [
            "users": [currentUserId, userId],
            "timestamp": FieldValue.serverTimestamp(),
          ]

          let chatData: [String: Any] = [
            "participants": [currentUserId, userId],
            "lastMessage": NSNull(),
            "lastMessageTimestamp": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
          ]

          try await db.collection("matches").addDocument(data: matchData)
          try await db.collection("chats").addDocument(data: chatData)

          await HapticManager.success()
        }
      } else {
        try await db.collection("passes")
          .document("\(currentUserId)_\(userId)")
          .setData([
            "passerId": currentUserId,
            "passedId": userId,
            "timestamp": FieldValue.serverTimestamp(),
          ])
      }

      isLiked = like
      await HapticManager.lightTap()
    } catch {
      print("Error handling interaction: \(error)")
    }
  }
}

struct VideosGridView: View {
  let userId: String
  let videos: [Video]

  // Fixed grid layout with minimal spacing
  private let columns = [
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1),
  ]

  var body: some View {
    Group {
      if videos.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "video.slash")
            .font(.largeTitle)
            .foregroundColor(.gray)
          Text("No videos yet")
            .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 1) {
            ForEach(videos) { video in
              NavigationLink {
                VideoDetailView(video: video, videos: videos)
              } label: {
                VideoThumbnailView(video: video)
                  .background(Color.black)
              }
            }
          }
        }
        .background(Color.black.opacity(0.2))
      }
    }
  }
}

struct LikedVideosGridView: View {
  let videos: [Video]

  var body: some View {
    Group {
      if videos.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "heart.slash")
            .font(.system(size: 50))
            .foregroundColor(.gray)
          Text("No liked videos yet")
            .font(.headline)
            .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VideoGrid(videos: videos) { video in
          NavigationLink(destination: VideoDetailView(video: video, videos: videos)) {
            EmptyView()
          }
        }
      }
    }
  }
}

class VideosGridViewModel: ObservableObject {
  @Published var videos: [Video] = []
  @Published var isLoading = false
  @Published var error: Error?
  private let db = Firestore.firestore()
  private var listener: ListenerRegistration?

  func fetchVideos(for userId: String) {
    print("[DEBUG] VideosGridViewModel.fetchVideos - Starting for userId: \(userId)")

    guard !userId.isEmpty else {
      print("[ERROR] VideosGridViewModel - Empty userId provided")
      error = NSError(
        domain: "",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"]
      )
      return
    }

    // Reset state
    isLoading = true
    error = nil

    // Remove existing listener if any
    listener?.remove()

    // Set up new listener
    let query = db.collection("videos")
      .whereField("creatorId", isEqualTo: userId)
      .order(by: "createdAt", descending: true)

    print("[DEBUG] Setting up listener for videos collection")
    print("[DEBUG] Query filters: creatorId = \(userId)")

    listener = query.addSnapshotListener { [weak self] snapshot, error in
      guard let self = self else { return }

      print("[DEBUG] Received snapshot update for userId: \(userId)")
      self.isLoading = false

      if let error = error {
        print("[ERROR] Snapshot listener error: \(error)")
        self.error = error
        return
      }

      guard let documents = snapshot?.documents else {
        print("[ERROR] No documents in snapshot")
        // Don't set error for empty results
        self.videos = []
        return
      }

      print("[DEBUG] Processing \(documents.count) documents")

      for (index, doc) in documents.enumerated() {
        print("[DEBUG] Document \(index + 1):")
        print("[DEBUG]   ID: \(doc.documentID)")
        print("[DEBUG]   Data: \(doc.data())")
      }

      let decodedVideos = documents.compactMap { doc -> Video? in
        do {
          let video = try doc.data(as: Video.self)
          print("[DEBUG] Successfully decoded video:")
          print("[DEBUG]   ID: \(video.id ?? "unknown")")
          print("[DEBUG]   CreatorId: \(video.creatorId)")
          print("[DEBUG]   Caption: \(video.caption ?? "none")")
          print("[DEBUG]   Created: \(video.createdAt)")
          return video
        } catch {
          print("[ERROR] Failed to decode video document \(doc.documentID):")
          print("[ERROR] \(error)")
          return nil
        }
      }

      print("[DEBUG] Successfully decoded \(decodedVideos.count) videos")

      // Sort by creation date (newest first)
      self.videos = decodedVideos.sorted { $0.createdAt > $1.createdAt }

      print("[DEBUG] Final videos count: \(self.videos.count)")
    }
  }

  deinit {
    print("[DEBUG] VideosGridViewModel.deinit - Removing listener")
    listener?.remove()
  }
}

#Preview {
  NavigationStack {
    ProfileViewContainer(userId: "preview_user_id")
      .environment(UserViewModel())
  }
}