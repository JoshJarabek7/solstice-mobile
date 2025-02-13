import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// Public typealias for backward compatibility
typealias ProfileView = ProfileViewContainer

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

      print("[DEBUG] ProfileViewContainer.task - Starting initialization")
      print("[DEBUG] userId: \(String(describing: userId))")
      print("[DEBUG] Auth.currentUser?.uid: \(String(describing: Auth.auth().currentUser?.uid))")
      print("[DEBUG] userViewModel.user.id: \(String(describing: userViewModel.user.id))")

      // Only try to create ProfileViewModel if we have a userId or current user
      do {
        print("[DEBUG] Attempting to create ProfileViewModel")
        viewModel = try ProfileViewModel(userId: userId, userViewModel: userViewModel)
        print("[DEBUG] Successfully created ProfileViewModel")
      } catch {
        print("[ERROR] Failed to create ProfileViewModel: \(error)")
        self.error = error
      }
    }
  }
}

// Renamed to _ProfileView to indicate it's an implementation detail
struct _ProfileView: View {
  let userId: String?
  @ObservedObject var viewModel: ProfileViewModel
  @Environment(UserViewModel.self) var userViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var selectedTab = 0
  @State private var isRefreshing = false

  private var effectiveUserId: String {
    if let specificUserId = userId {
      return specificUserId
    }
    return Auth.auth().currentUser?.uid ?? ""
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(spacing: 20) {
        if let displayUser = viewModel.user {
          // Profile Header
          ProfileHeaderView(user: displayUser)

          // Bio
          if let bio = displayUser.bio {
            Text(bio)
              .padding(.horizontal)
          }

          // Stats Row
          HStack(spacing: 40) {
            VStack {
              Text("\(viewModel.videos.count)")
                .font(.headline)
              Text("Posts")
                .foregroundColor(.gray)
            }
            VStack {
              Text("\(viewModel.followerCount)")
                .font(.headline)
              Text("Followers")
                .foregroundColor(.gray)
            }
            VStack {
              Text("\(viewModel.followingCount)")
                .font(.headline)
              Text("Following")
                .foregroundColor(.gray)
            }
          }
          .padding()

          // Tabs
          HStack {
            TabButton(
              title: "Videos",
              systemImage: "play.square",
              isSelected: selectedTab == 0
            ) {
              selectedTab = 0
            }

            if displayUser.isDatingEnabled {
              TabButton(
                title: "Dating",
                systemImage: "heart",
                isSelected: selectedTab == 1
              ) {
                selectedTab = 1
              }
            }

            TabButton(
              title: "Liked",
              systemImage: "heart.fill",
              isSelected: selectedTab == 2
            ) {
              selectedTab = 2
            }
          }
          .padding(.horizontal)

          // Tab Content
          switch selectedTab {
          case 0:
            VideosGridView(userId: effectiveUserId)
              .id(effectiveUserId) // Force refresh when user changes
          case 1 where displayUser.isDatingEnabled:
            DatingProfileSection(user: displayUser)
          case 2:
            LikedVideosGridView(videos: viewModel.likedVideos)
          default:
            EmptyView()
          }
        } else {
          ProgressView()
        }
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
            SettingsView(userViewModel: userViewModel)
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
    if userId != nil {
      print("[DEBUG] Refreshing specific user data")
      try? await viewModel.fetchUserData()
    } else {
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

struct TabButton: View {
  let title: String
  let systemImage: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 24))
        Text(title)
          .font(.caption)
      }
      .foregroundColor(isSelected ? .primary : .gray)
    }
  }
}

struct ProfileHeaderView: View {
  let user: User

  var body: some View {
    VStack(spacing: 12) {
      // Profile Image
      if let imageURL = user.profileImageURL {
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
      } else {
        Image(systemName: "person.circle.fill")
          .resizable()
          .frame(width: 100, height: 100)
          .foregroundColor(.gray)
      }

      // User Info
      VStack(spacing: 4) {
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
  }
}

struct DatingProfileSection: View {
  let user: User

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Dating Profile")
        .font(.headline)
        .padding(.horizontal)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(user.datingImages, id: \.self) { imageURL in
            AsyncImage(url: URL(string: imageURL)) { image in
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
        .padding(.horizontal)
      }
    }
  }
}

struct VideosGridView: View {
  let userId: String
  @StateObject private var viewModel = VideosGridViewModel()
  @State private var isRefreshing = false
  
  // Fixed grid layout with minimal spacing
  private let columns = [
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1)
  ]
  
  var body: some View {
    Group {
      if viewModel.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = viewModel.error {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundColor(.red)
          Text(error.localizedDescription)
            .multilineTextAlignment(.center)
          Button("Retry") {
            viewModel.fetchVideos(for: userId)
          }
          .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.videos.isEmpty {
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
            ForEach(viewModel.videos) { video in
              NavigationLink(destination: VideoDetailView(video: video, videos: viewModel.videos)) {
                VideoThumbnailView(video: video)
                  .background(Color.black)
              }
            }
          }
        }
        .background(Color.black.opacity(0.2))
      }
    }
    .onAppear {
      print("[DEBUG] VideosGridView appeared for userId: \(userId)")
      viewModel.fetchVideos(for: userId)
    }
    .onChange(of: userId) { oldValue, newValue in
      print("[DEBUG] UserId changed from \(oldValue) to \(newValue)")
      viewModel.fetchVideos(for: newValue)
    }
  }
}

struct LikedVideosGridView: View {
  let videos: [Video]

  var body: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
      ], spacing: 2
    ) {
      ForEach(videos) { video in
        NavigationLink(destination: VideoDetailView(video: video, videos: videos)) {
          VideoThumbnailView(video: video)
            .aspectRatio(9 / 16, contentMode: .fill)
            .clipped()
        }
      }
    }
    .padding(.horizontal, 1)
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
