import AVKit
import SwiftUI
import FirebaseFirestore

struct FeedLoadingView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyFeedView: View {
    let feedType: FeedType
    let onRefresh: () async -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No videos available")
                .font(.headline)
            
            Text("Check back later for new content")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Button {
                Task {
                    await onRefresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Custom Feed Type Button
struct FeedTypeButton: View {
    let type: FeedType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(type == .following ? "Following" : "For You")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color.clear)
                )
        }
    }
}

// Custom Segmented Control
struct FeedTypeSegmentedControl: View {
    @Binding var selection: FeedType
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach([FeedType.following, FeedType.forYou], id: \.self) { type in
                FeedTypeButton(
                    type: type,
                    isSelected: selection == type
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = type
                    }
                }
            }
        }
        .padding(2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .frame(width: 200)
    }
}

struct FeedTopNavigation: View {
    @Binding var feedType: FeedType
    let errorMessage: String?
    
    var body: some View {
        VStack {
            HStack(spacing: 20) {
                FeedTypeSegmentedControl(selection: $feedType)
            }
            .padding(.top, 60)
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            
            Spacer()
        }
    }
}

struct CaughtUpView: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack {
            Spacer()
            Text("You're all caught up!")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .padding(.bottom, 50)
        }
        .transition(.opacity)
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
}

struct VideoFeedItemView: View {
    let video: Video
    let geometry: GeometryProxy
    let index: Int
    let currentIndex: Int
    let videosCount: Int
    let onVideoViewed: (Int) -> Void
    let onNearEnd: () async -> Void
    @StateObject private var viewModel = VideoDetailViewModel()
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var playbackState = Video.PlaybackState()
    @State private var showProfile = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Video Player Container
            ZStack {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                // Video Player
                VideoPlayer(
                    video: video,
                    playbackState: $playbackState,
                    isActive: currentIndex == index,
                    videoGravity: .resizeAspect
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .scaleEffect(video.aspectRatio == .portrait ? 1.0 : 0.7) // Scale down landscape videos
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .tag(index)
            
            // Overlay Controls
            VStack {
                Spacer()
                
                // Right-side action buttons
                HStack {
                    // Left side - Caption and creator info
                    VStack(alignment: .leading, spacing: 8) {
                        // Creator info
                        if let creator = viewModel.creator, let creatorId = creator.id, !creatorId.isEmpty {
                            NavigationLink {
                                ProfileViewContainer(userId: creatorId)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(creator.fullName)
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("@\(creator.username)")
                                        .foregroundColor(.white.opacity(0.9))
                                        .font(.system(size: 14))
                                }
                            }
                        }
                        
                        // Caption
                        if let caption = video.caption {
                            Text(caption)
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        
                        // Hashtags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(video.hashtags, id: \.self) { hashtag in
                                    NavigationLink {
                                        HashtagVideosView(hashtag: hashtag)
                                    } label: {
                                        Text("#\(hashtag)")
                                            .foregroundColor(.white)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading)
                    .padding(.bottom, 60)
                    
                    Spacer()
                    
                    // Right side buttons
                    VStack(spacing: 20) {
                        // Creator Profile Picture
                        if let creator = viewModel.creator, let creatorId = creator.id, !creatorId.isEmpty {
                            NavigationLink {
                                ProfileViewContainer(userId: creatorId)
                            } label: {
                                AsyncImage(url: URL(string: creator.profileImageURL ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                        
                        // Like Button
                        Button {
                            Task {
                                try? await viewModel.toggleLike(videoId: video.id ?? "")
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 30))
                                    .foregroundColor(viewModel.isLiked ? .red : .white)
                                Text("\(viewModel.likeCount)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Comments Button
                        Button {
                            showComments = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                Text("\(video.comments)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Share Button
                        Button {
                            showShareSheet = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                Text("\(video.shares)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if newValue == index {
                onVideoViewed(index)
                if index >= videosCount - 3 {
                    Task {
                        await onNearEnd()
                    }
                }
            }
        }
        .task {
            if currentIndex == index {
                await viewModel.loadCreator(creatorId: video.creatorId, videoId: video.id ?? "")
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(
                video: video,
                comments: viewModel.comments,
                commentText: $viewModel.commentText,
                onPostComment: {
                    Task {
                        try? await viewModel.addComment(
                            videoId: video.id ?? "",
                            text: viewModel.commentText
                        )
                    }
                },
                onLikeComment: { commentId in
                    Task {
                        try? await viewModel.toggleCommentLike(
                            videoId: video.id ?? "",
                            commentId: commentId
                        )
                    }
                },
                onProfileTap: { userId in
                    showComments = false
                    showProfile = true
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(video: video)
        }
        .navigationDestination(isPresented: $showProfile) {
            if let creator = viewModel.creator, let creatorId = creator.id {
                ProfileViewContainer(userId: creatorId)
            }
        }
    }
}

struct VideoFeedTabView: View {
    let geometry: GeometryProxy
    let videos: [Video]
    @Binding var currentIndex: Int
    let onVideoViewed: (Int) -> Void
    let onNearEnd: () async -> Void
    
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                VideoFeedItemView(
                    video: video,
                    geometry: geometry,
                    index: index,
                    currentIndex: currentIndex,
                    videosCount: videos.count,
                    onVideoViewed: onVideoViewed,
                    onNearEnd: onNearEnd
                )
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}

struct FeedStateView: View {
    let geometry: GeometryProxy
    let viewModel: FeedViewModel
    let feedType: FeedType
    @Binding var currentIndex: Int
    
    var body: some View {
        if viewModel.isLoading && viewModel.videos.isEmpty {
            FeedLoadingView()
        } else if viewModel.videos.isEmpty {
            EmptyFeedView(feedType: feedType) {
                await viewModel.refreshFeed(type: feedType)
            }
        } else {
            FeedContentView(
                geometry: geometry,
                viewModel: viewModel,
                currentIndex: $currentIndex
            )
        }
    }
}

struct FeedContentView: View {
    let geometry: GeometryProxy
    let viewModel: FeedViewModel
    @Binding var currentIndex: Int
    @State private var showCaughtUp = false
    
    var body: some View {
        ZStack {
            VideoFeedTabView(
                geometry: geometry,
                videos: viewModel.videos,
                currentIndex: $currentIndex,
                onVideoViewed: { index in
                    viewModel.videoViewed(at: index)
                },
                onNearEnd: {
                    await viewModel.fetchMoreVideos()
                }
            )
            
            if !viewModel.hasMoreVideos && currentIndex == viewModel.videos.count - 1 {
                if showCaughtUp {
                    CaughtUpView(isVisible: $showCaughtUp)
                }
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if !viewModel.hasMoreVideos && newValue == viewModel.videos.count - 1 {
                withAnimation {
                    showCaughtUp = true
                }
            }
        }
    }
}

struct FeedView: View {
    @State private var feedViewModel = FeedViewModel()
    @State private var currentIndex = 0
    @State private var feedType: FeedType = .forYou
    @State private var scrollPosition: Int?
    
    var body: some View {
        ZStack(alignment: .top) {
            if feedViewModel.isLoading && feedViewModel.videos.isEmpty {
                FeedLoadingView()
            } else if feedViewModel.videos.isEmpty {
                EmptyFeedView(feedType: feedType) {
                    await feedViewModel.refreshFeed(type: feedType)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(feedViewModel.videos.enumerated()), id: \.element.id) { index, video in
                            ZStack(alignment: .bottom) {
                                // Video Player
                                VideoPlayer(
                                    video: video,
                                    playbackState: .constant(Video.PlaybackState()),
                                    isActive: currentIndex == index,
                                    videoGravity: .resizeAspect
                                )
                                .frame(
                                    width: UIScreen.main.bounds.width,
                                    height: UIScreen.main.bounds.height
                                )
                                .background(Color.black)
                                
                                // Overlay Controls
                                VideoOverlayView(
                                    video: video,
                                    index: index,
                                    currentIndex: currentIndex
                                )
                            }
                            .id(index)
                            .edgesIgnoringSafeArea(.all)
                        }
                    }
                    .scrollTargetLayout()
                }
                .background(Color.black)
                .edgesIgnoringSafeArea(.all)
                .scrollPosition(id: $scrollPosition)
                .scrollTargetBehavior(.paging)
                .onChange(of: scrollPosition) { oldValue, newValue in
                    if let newIndex = newValue {
                        // Ensure index is within bounds
                        if newIndex >= 0 && newIndex < feedViewModel.videos.count {
                            currentIndex = newIndex
                            
                            // Check if we're near the end to fetch more videos
                            if newIndex >= feedViewModel.videos.count - 3 {
                                Task {
                                    await feedViewModel.fetchMoreVideos()
                                }
                            }
                        }
                    }
                }
            }
            
            FeedTopNavigation(
                feedType: $feedType,
                errorMessage: feedViewModel.errorMessage
            )
        }
        .onChange(of: feedType) { oldValue, newValue in
            Task {
                currentIndex = 0 // Reset index when changing feed type
                scrollPosition = 0
                await feedViewModel.refreshFeed(type: newValue)
            }
        }
        .task {
            await feedViewModel.refreshFeed(type: feedType)
        }
    }
}

struct VideoOverlayView: View {
    let video: Video
    let index: Int
    let currentIndex: Int
    @StateObject private var viewModel = VideoDetailViewModel()
    @State private var showComments = false
    @State private var showShareSheet = false
    @State private var showProfile = false
    
    var body: some View {
        VStack {
            Spacer()
            
            // Right-side action buttons
            HStack {
                // Left side - Caption and creator info
                VStack(alignment: .leading, spacing: 8) {
                    // Creator info
                    if let creator = viewModel.creator, let creatorId = creator.id, !creatorId.isEmpty {
                        NavigationLink {
                            ProfileViewContainer(userId: creatorId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(creator.fullName)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .semibold))
                                Text("@\(creator.username)")
                                    .foregroundColor(.white.opacity(0.9))
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    
                    // Caption
                    if let caption = video.caption {
                        Text(caption)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    
                    // Hashtags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(video.hashtags, id: \.self) { hashtag in
                                NavigationLink {
                                    HashtagVideosView(hashtag: hashtag)
                                } label: {
                                    Text("#\(hashtag)")
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(.leading)
                .padding(.bottom, 60)
                
                Spacer()
                
                // Right side buttons
                VStack(spacing: 20) {
                    // Creator Profile Picture
                    if let creator = viewModel.creator, let creatorId = creator.id, !creatorId.isEmpty {
                        NavigationLink {
                            ProfileViewContainer(userId: creatorId)
                        } label: {
                            AsyncImage(url: URL(string: creator.profileImageURL ?? "")) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                    }
                    
                    // Like Button
                    Button {
                        Task {
                            try? await viewModel.toggleLike(videoId: video.id ?? "")
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 30))
                                .foregroundColor(viewModel.isLiked ? .red : .white)
                            Text("\(viewModel.likeCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Comments Button
                    Button {
                        showComments = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                            Text("\(video.comments)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Share Button
                    Button {
                        showShareSheet = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                            Text("\(video.shares)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(
                video: video,
                comments: viewModel.comments,
                commentText: $viewModel.commentText,
                onPostComment: {
                    Task {
                        try? await viewModel.addComment(
                            videoId: video.id ?? "",
                            text: viewModel.commentText
                        )
                    }
                },
                onLikeComment: { commentId in
                    Task {
                        try? await viewModel.toggleCommentLike(
                            videoId: video.id ?? "",
                            commentId: commentId
                        )
                    }
                },
                onProfileTap: { userId in
                    showComments = false
                    showProfile = true
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(video: video)
        }
        .navigationDestination(isPresented: $showProfile) {
            if let creator = viewModel.creator, let creatorId = creator.id {
                ProfileViewContainer(userId: creatorId)
            }
        }
        .task {
            if currentIndex == index {
                await viewModel.loadCreator(creatorId: video.creatorId, videoId: video.id ?? "")
            }
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            if newValue == index {
                Task {
                    await viewModel.loadCreator(creatorId: video.creatorId, videoId: video.id ?? "")
                }
            }
        }
    }
}

#Preview {
    FeedView()
}
