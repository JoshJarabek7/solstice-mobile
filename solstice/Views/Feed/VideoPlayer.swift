import AVKit
import SwiftUI
import UIKit

@MainActor
struct VideoPlayer: View {
  let video: Video
  @Binding var playbackState: Video.PlaybackState
  let isActive: Bool
  let videoGravity: AVLayerVideoGravity

  @StateObject private var viewModel = VideoPlayerViewModel()
  @State private var player: AVPlayer?
  @State private var backgroundPlayer: AVPlayer?
  @State private var currentOrientation = UIDevice.current.orientation
  @State private var loadingState: LoadingState = .loading
  @State private var errorMessage: String?
  @State private var timeObserver: VideoPlayerObserver?
  @State private var playerItemObserver: NSKeyValueObservation?

  init(
    video: Video,
    playbackState: Binding<Video.PlaybackState>,
    isActive: Bool,
    videoGravity: AVLayerVideoGravity = .resizeAspectFill
  ) {
    self.video = video
    self._playbackState = playbackState
    self.isActive = isActive
    self.videoGravity = videoGravity
  }

  var body: some View {
    GeometryReader { geometry in
      // Container that clips to device bounds
      ZStack {
        // Background container
        if let backgroundPlayer = backgroundPlayer {
          ZStack {
            VideoPlayerUIKit(player: backgroundPlayer, videoGravity: .resizeAspectFill)
              .blur(radius: 50)
              .opacity(0.6)
              .scaleEffect(1.5)
          }
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()
        }

        // Main video container
        ZStack {
          if let player = player {
            VideoPlayerUIKit(player: player, videoGravity: videoGravity)
              .onAppear {
                if isActive {
                  player.play()
                  backgroundPlayer?.play()
                  playbackState.isPlaying = true
                }
              }
              .onDisappear {
                player.pause()
                backgroundPlayer?.pause()
                playbackState.isPlaying = false
              }
              .onChange(of: isActive) { _, newValue in
                if newValue {
                  player.seek(
                    to: CMTime(
                      seconds: playbackState.currentTime,
                      preferredTimescale: 600))
                  backgroundPlayer?.seek(
                    to: CMTime(
                      seconds: playbackState.currentTime,
                      preferredTimescale: 600))
                  player.play()
                  backgroundPlayer?.play()
                  playbackState.isPlaying = true
                } else {
                  player.pause()
                  backgroundPlayer?.pause()
                  playbackState.isPlaying = false
                }
              }
              .rotationEffect(
                currentOrientation.isLandscape ? .degrees(-90) : .degrees(0)
              )
              .animation(.easeInOut, value: currentOrientation)
          } else {
            Color.black
          }

          // Loading and Error States
          switch loadingState {
          case .loading:
            LoadingView()
          case .error(let message):
            ErrorView(
              message: message,
              retry: {
                Task { await setupPlayer() }
              })
          case .ready:
            EmptyView()
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
      .gesture(
        TapGesture(count: 2)
          .onEnded {
            viewModel.handleDoubleTap()
            Task { await HapticManager.like() }
          }
      )
      .sheet(isPresented: $viewModel.showShareSheet) {
        ShareSheet(video: video)
      }
    }
    .task(priority: .high) {
      await setupPlayer()
      setupOrientationNotification()
    }
    .onDisappear {
      cleanup()
      NotificationCenter.default.removeObserver(
        self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }
  }

  private func setupOrientationNotification() {
    NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
    ) { _ in
      Task { @MainActor in
        currentOrientation = UIDevice.current.orientation
      }
    }
  }

  private func setupPlayer() async {
    guard let url = URL(string: video.videoURL) else {
      loadingState = .error("Invalid video URL")
      return
    }

    do {
      loadingState = .loading

      // Create player item using iOS 18 API
      let asset = AVURLAsset(url: url)

      // Check playability
      let isPlayable = try await asset.load(.isPlayable)
      guard isPlayable else {
        throw VideoPlayerError.unplayable
      }

      let playerItem = AVPlayerItem(asset: asset)
      let backgroundPlayerItem = AVPlayerItem(asset: asset)
      backgroundPlayerItem.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.varispeed

      let newPlayer = AVPlayer(playerItem: playerItem)
      let newBackgroundPlayer = AVPlayer(playerItem: backgroundPlayerItem)
      newBackgroundPlayer.isMuted = true

      // Create time observer
      timeObserver = VideoPlayerObserver(player: newPlayer) { time in
        Task { @MainActor in
          playbackState.currentTime = time
        }
      }

      // Observe duration
      let duration = try await asset.load(.duration)
      playbackState.duration = duration.seconds

      // Observe buffering state
      playerItemObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp) { item, _ in
        Task { @MainActor in
          playbackState.isLoading = !item.isPlaybackLikelyToKeepUp
        }
      }

      // Handle video completion
      NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
      ) { [weak newPlayer, weak newBackgroundPlayer] _ in
        Task { @MainActor in
          newPlayer?.seek(to: .zero)
          newBackgroundPlayer?.seek(to: .zero)
          newPlayer?.play()
          newBackgroundPlayer?.play()
        }
      }

      self.player = newPlayer
      self.backgroundPlayer = newBackgroundPlayer
      loadingState = .ready
      await HapticManager.lightTap()
    } catch {
      loadingState = .error(error.localizedDescription)
      await HapticManager.error()
    }
  }

  private func cleanup() {
    player?.pause()
    backgroundPlayer?.pause()
    timeObserver = nil
    playerItemObserver?.invalidate()
    playerItemObserver = nil
    player = nil
    backgroundPlayer = nil
  }
}

struct VideoPlayerUIKit: UIViewControllerRepresentable {
  let player: AVPlayer
  let videoGravity: AVLayerVideoGravity

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = false
    controller.videoGravity = videoGravity
    return controller
  }

  func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    // Update if needed
  }
}

class VideoPlayerViewModel: ObservableObject {
  @Published var isLiked = false
  @Published var isBookmarked = false
  @Published var showShareSheet = false

  func handleDoubleTap() {
    isLiked.toggle()
  }

  func showShare() {
    showShareSheet = true
  }

  func handleBookmark() {
    isBookmarked.toggle()
  }

  func showComments() {
    // Implement comments functionality
  }
}

extension UIDeviceOrientation {
  var isLandscape: Bool {
    return self == .landscapeLeft || self == .landscapeRight
  }
}

// Loading State Views
struct LoadingView: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.5)
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
        .scaleEffect(1.5)
    }
  }
}

struct ErrorView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 40))
        .foregroundColor(.yellow)

      Text("Error loading video")
        .font(.headline)

      Text(message)
        .font(.subheadline)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)

      Button(action: retry) {
        Label("Retry", systemImage: "arrow.clockwise")
          .padding()
          .background(.ultraThinMaterial)
          .cornerRadius(10)
      }
    }
    .padding()
  }
}

enum LoadingState {
  case loading
  case error(String)
  case ready
}

enum VideoPlayerError: LocalizedError {
  case unplayable

  var errorDescription: String? {
    switch self {
    case .unplayable:
      return "This video cannot be played"
    }
  }
}

@objc final class VideoPlayerObserver: NSObject, @unchecked Sendable {
  private weak var player: AVPlayer?
  private let onTimeUpdate: @Sendable (TimeInterval) -> Void
  private var timeObserverToken: Any?

  init(player: AVPlayer, onTimeUpdate: @escaping @Sendable (TimeInterval) -> Void) {
    self.player = player
    self.onTimeUpdate = onTimeUpdate
    super.init()

    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      self?.onTimeUpdate(time.seconds)
    }
  }

  deinit {
    if let token = timeObserverToken {
      player?.removeTimeObserver(token)
      timeObserverToken = nil
    }
  }
}

#Preview {
  VideoPlayer(
    video: Video(
      id: "test",
      creatorId: "creator",
      caption: "Test video",
      videoURL: "https://example.com/video.mp4",
      thumbnailURL: nil,
      likes: 0,
      comments: 0,
      shares: 0,
      createdAt: Date(),
      duration: 120,
      hashtags: ["test"],
      viewCount: 0,
      completionRate: 0,
      engagementScore: 0,
      lastPlaybackPosition: nil
    ),
    playbackState: .constant(Video.PlaybackState()),
    isActive: true
  )
}
