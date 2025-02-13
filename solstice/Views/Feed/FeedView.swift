import AVKit
import FirebaseFirestore
import SwiftUI

struct FeedView: View {
  @StateObject private var viewModel = FeedViewModel()
  @State private var currentIndex = 0
  @State private var feedType: FeedType = .forYou

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        // Video Feed
        TabView(selection: $currentIndex) {
          ForEach(viewModel.videos.indices, id: \.self) { index in
            VideoPlayerView(
              video: viewModel.videos[index],
              isActive: currentIndex == index
            )
            .frame(
              width: geometry.size.width,
              height: geometry.size.height
            )
            .rotationEffect(.degrees(0))
            .tag(index)
            .onChange(of: currentIndex) { oldValue, newValue in
              if newValue == index {
                viewModel.videoViewed(at: index)
                // Load more videos if we're near the end
                if index >= viewModel.videos.count - 3 {
                  Task {
                    await viewModel.fetchMoreVideos()
                  }
                }
              }
            }
          }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .ignoresSafeArea()

        // Top Navigation
        VStack {
          HStack(spacing: 20) {
            Picker("Feed Type", selection: $feedType) {
              Text("Following").tag(FeedType.following)
              Text("For You").tag(FeedType.forYou)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
          }
          .padding(.top, 60)
          .padding(.horizontal)

          Spacer()
        }
      }
    }
    .onChange(of: feedType) { oldValue, newValue in
      Task {
        await viewModel.refreshFeed(type: newValue)
      }
    }
  }
}

enum FeedType {
  case following
  case forYou
}

@MainActor
class FeedViewModel: ObservableObject {
  @Published var videos: [Video] = []
  @Published var isLoading = false

  private let db = Firestore.firestore()
  private var lastDocument: DocumentSnapshot?
  private let limit = 5
  private var currentFeedType: FeedType = .forYou
  private var isLoadingMore = false

  func refreshFeed(type: FeedType) async {
    currentFeedType = type
    videos = []
    lastDocument = nil
    await fetchMoreVideos()
  }

  func fetchMoreVideos() async {
    guard !isLoadingMore else { return }
    isLoadingMore = true

    do {
      var query = db.collection("videos")
        .order(by: "createdAt", descending: true)
        .limit(to: limit)

      if let last = lastDocument {
        query = query.start(afterDocument: last)
      }

      // Add feed type specific filters
      switch currentFeedType {
      case .following:
        // TODO: Add following filter
        break
      case .forYou:
        query = query.order(by: "engagementScore", descending: true)
      }

      let snapshot = try await query.getDocuments()
      let newVideos = snapshot.documents.compactMap { try? $0.data(as: Video.self) }

      await MainActor.run {
        videos.append(contentsOf: newVideos)
        lastDocument = snapshot.documents.last
        isLoadingMore = false
      }
    } catch {
      print("Error fetching videos: \(error)")
      isLoadingMore = false
    }
  }

  func videoViewed(at index: Int) {
    guard index < videos.count else { return }
    let video = videos[index]

    Task {
      guard let videoId = video.id else { return }
      let ref = db.collection("videos").document(videoId)

      do {
        try await ref.updateData([
          "viewCount": FieldValue.increment(Int64(1)),
          "engagementScore": calculateEngagementScore(video),
        ])
      } catch {
        print("Error updating video stats: \(error)")
      }
    }
  }

  private func calculateEngagementScore(_ video: Video) -> Double {
    let viewWeight = 1.0
    let likeWeight = 2.0
    let commentWeight = 3.0
    let shareWeight = 4.0

    return Double(video.viewCount) * viewWeight + Double(video.likes) * likeWeight + Double(
      video.comments) * commentWeight + Double(video.shares) * shareWeight
  }
}

struct VideoPlayerView: View {
  let video: Video
  let isActive: Bool

  @StateObject private var viewModel: VideoPlayerViewModel
  @State private var playbackState = Video.PlaybackState()
  @State private var creator: User?

  init(video: Video, isActive: Bool) {
    self.video = video
    self.isActive = isActive
    _viewModel = StateObject(wrappedValue: VideoPlayerViewModel())
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Video Player
      VideoPlayer(video: video, playbackState: $playbackState, isActive: isActive)
        .overlay(
          // Right side buttons
          VStack(alignment: .trailing, spacing: 20) {
            Spacer()

            // Profile Button
            NavigationLink {
              ProfileViewContainer(userId: video.creatorId)
            } label: {
              if let creator = creator {
                AsyncImage(url: URL(string: creator.profileImageURL ?? "")) { image in
                  image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                } placeholder: {
                  Image(systemName: "person.circle.fill")
                    .resizable()
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
              } else {
                Image(systemName: "person.circle.fill")
                  .resizable()
                  .frame(width: 50, height: 50)
                  .foregroundColor(.gray)
              }
            }

            // Action Buttons
            ActionButton(
              icon: viewModel.isLiked ? "heart.fill" : "heart",
              count: video.likes,
              color: viewModel.isLiked ? .red : .white,
              action: { viewModel.handleDoubleTap() }
            )

            ActionButton(
              icon: "bubble.right",
              count: video.comments,
              action: { viewModel.showComments() }
            )

            ActionButton(
              icon: "paperplane",
              count: video.shares,
              action: { viewModel.showShare() }
            )

            ActionButton(
              icon: viewModel.isBookmarked ? "bookmark.fill" : "bookmark",
              color: viewModel.isBookmarked ? .yellow : .white,
              action: { viewModel.handleBookmark() }
            )
          }
          .padding(.trailing, 16)
          .padding(.bottom, 80),
          alignment: .bottomTrailing
        )

      // Video Info Overlay
      VStack(alignment: .leading, spacing: 8) {
        if let creator = creator {
          Text("@\(creator.username)")
            .font(.headline)
        }

        if let caption = video.caption {
          Text(caption)
            .font(.subheadline)
        }

        HStack {
          ForEach(video.hashtags, id: \.self) { tag in
            Text("#\(tag)")
              .font(.caption)
              .foregroundColor(.blue)
          }
        }
      }
      .padding()
      .background(
        LinearGradient(
          gradient: Gradient(colors: [.clear, .black.opacity(0.5)]),
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }
    .task {
      // Load creator info
      await loadCreator()
    }
    .sheet(isPresented: $viewModel.showShareSheet) {
      ShareSheet(video: video)
    }
  }

  private func loadCreator() async {
    do {
      let db = Firestore.firestore()
      creator = try await db.collection("users")
        .document(video.creatorId)
        .getDocument(as: User.self)
    } catch {
      print("Error loading creator: \(error)")
    }
  }
}

struct ActionButton: View {
  let icon: String
  var count: Int?
  var color: Color = .white
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.system(size: 28))

        if let count = count {
          Text("\(count)")
            .font(.caption)
            .foregroundColor(.white)
        }
      }
    }
  }
}

struct VideoProgressBar: View {
  @Binding var currentTime: TimeInterval
  let duration: TimeInterval
  let isPlaying: Bool

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.white.opacity(0.3))
          .frame(height: 2)

        Rectangle()
          .fill(Color.white)
          .frame(width: geometry.size.width * progress, height: 2)
      }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          let progress = value.location.x / value.startLocation.x
          currentTime = duration * Double(progress)
        }
    )
  }

  private var progress: CGFloat {
    duration > 0 ? CGFloat(currentTime / duration) : 0
  }
}

#Preview {
  FeedView()
}
