import SwiftUI

struct VideoDetailView: View {
  let initialVideo: Video
  let videos: [Video]  // All videos from the profile/collection
  @StateObject private var viewModel = VideoDetailViewModel()
  @Environment(\.dismiss) private var dismiss
  @State private var currentIndex: Int = 0
  @State private var showComments = false
  @State private var showShareSheet = false
  @State private var isVideoActive = true
  @State private var playbackState = Video.PlaybackState()
  @State private var scrollPosition: Int?
  @State private var showProfile = false
  @State private var selectedUserId: String?
  
  init(video: Video, videos: [Video] = []) {
    self.initialVideo = video
    self.videos = videos.isEmpty ? [video] : videos
    if let index = videos.firstIndex(where: { $0.id == video.id }) {
      _currentIndex = State(initialValue: index)
    }
  }

  private var currentVideo: Video {
    videos[currentIndex]
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(spacing: 0) {
        ForEach(videos.indices, id: \.self) { index in
          ZStack(alignment: .bottom) {
            // Video Player
            VideoPlayer(
              video: videos[index],
              playbackState: $playbackState,
              isActive: isVideoActive && currentIndex == index,
              videoGravity: .resizeAspect
            )
            .frame(
              width: UIScreen.main.bounds.width,
              height: UIScreen.main.bounds.height
            )
            .background(Color.black)
            
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
                  if let caption = videos[index].caption {
                    Text(caption)
                      .foregroundColor(.white)
                      .font(.subheadline)
                  }
                  
                  // Hashtags
                  ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                      ForEach(videos[index].hashtags, id: \.self) { hashtag in
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
                  // Creator Profile Picture (above like button)
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
                      try? await viewModel.toggleLike(videoId: videos[index].id ?? "")
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
                      Text("\(videos[index].comments)")
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
                      Text("\(videos[index].shares)")
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
        currentIndex = newIndex
      }
    }
    .sheet(isPresented: $showComments) {
      CommentsSheet(
        video: currentVideo,
        comments: viewModel.comments,
        commentText: $viewModel.commentText,
        onPostComment: {
          Task {
            try? await viewModel.addComment(
              videoId: currentVideo.id ?? "",
              text: viewModel.commentText
            )
          }
        },
        onLikeComment: { commentId in
          Task {
            try? await viewModel.toggleCommentLike(
              videoId: currentVideo.id ?? "",
              commentId: commentId
            )
          }
        },
        onProfileTap: { userId in
          selectedUserId = userId
          showComments = false
          showProfile = true
        }
      )
    }
    .navigationDestination(isPresented: $showProfile) {
      if let userId = selectedUserId {
        ProfileViewContainer(userId: userId)
      }
    }
    .sheet(isPresented: $showShareSheet) {
      ShareSheet(video: currentVideo)
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarHidden(true)
    .task {
      await viewModel.loadCreator(
        creatorId: currentVideo.creatorId,
        videoId: currentVideo.id ?? ""
      )
    }
    .onChange(of: currentIndex) { oldValue, newValue in
      Task {
        await viewModel.loadCreator(
          creatorId: videos[newValue].creatorId,
          videoId: videos[newValue].id ?? ""
        )
      }
    }
  }
}

struct CommentsSheet: View {
  let video: Video
  let comments: [Comment]
  @Binding var commentText: String
  let onPostComment: () -> Void
  let onLikeComment: (String) -> Void
  let onProfileTap: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var isInputFocused: Bool
  
  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("\(comments.count) comment\(comments.count == 1 ? "" : "s")")
          .font(.system(size: 16, weight: .semibold))
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 20))
            .foregroundColor(.primary)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
      .background(colorScheme == .dark ? Color.black : Color.white)
      
      Divider()
      
      // Comments List
      ScrollView {
        LazyVStack(spacing: 20) {
          ForEach(comments) { comment in
            CommentRow(
              comment: comment,
              onLike: onLikeComment,
              onProfileTap: {
                dismiss()
                onProfileTap(comment.userId)
              }
            )
          }
        }
        .padding(.vertical)
      }
      
      Divider()
      
      // Comment Input
      HStack(spacing: 12) {
        TextField("Add comment...", text: $commentText)
          .textFieldStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color(.systemGray6))
          .cornerRadius(20)
          .focused($isInputFocused)
        
        Button {
          if !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onPostComment()
            isInputFocused = false
          }
        } label: {
          Text("Post")
            .fontWeight(.semibold)
            .foregroundColor(!commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .blue : .gray)
        }
        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
      .background(colorScheme == .dark ? Color.black : Color.white)
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

struct CommentRow: View {
  let comment: Comment
  let onLike: (String) -> Void
  let onProfileTap: () -> Void
  
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Profile Image
      Button(action: onProfileTap) {
        AsyncImage(url: URL(string: comment.userProfileImageURL ?? "")) { image in
          image
            .resizable()
            .scaledToFill()
        } placeholder: {
          Image(systemName: "person.circle.fill")
            .foregroundColor(.gray)
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
      }
      
      VStack(alignment: .leading, spacing: 4) {
        // Username and Comment Text
        HStack(alignment: .top, spacing: 0) {
          Button(action: onProfileTap) {
            Text(comment.username)
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.primary)
          }
          Text("  ") +
          Text(comment.text)
            .font(.system(size: 14))
            .foregroundColor(.primary)
        }
        
        // Timestamp
        Text(comment.timestamp.formatted(.relative(presentation: .named)))
          .font(.system(size: 13))
          .foregroundColor(.gray)
      }
      
      Spacer()
      
      // Like Button
      Button {
        if let commentId = comment.id {
          onLike(commentId)
        }
      } label: {
        VStack(spacing: 4) {
          Image(systemName: comment.isLiked == true ? "heart.fill" : "heart")
            .font(.system(size: 18))
            .foregroundColor(comment.isLiked == true ? .red : .gray)
          
          if comment.likes > 0 {
            Text("\(comment.likes)")
              .font(.system(size: 12))
              .foregroundColor(.gray)
          }
        }
      }
      .padding(.leading, 8)
    }
    .padding(.horizontal)
  }
}

#Preview {
  NavigationStack {
    VideoDetailView(
      video: Video(
        id: "preview",
        creatorId: "user1",
        caption: "Test video",
        videoURL: "https://example.com/video.mp4",
        thumbnailURL: "https://example.com/thumbnail.jpg",
        duration: 30,
        hashtags: ["test", "preview"]
      ))
  }
}
