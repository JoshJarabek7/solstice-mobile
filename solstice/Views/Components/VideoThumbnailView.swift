import SwiftUI

struct VideoThumbnailView: View {
  let video: Video
  let fixedHeight: CGFloat?
  
  init(video: Video, fixedHeight: CGFloat? = nil) {
    self.video = video
    self.fixedHeight = fixedHeight
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomLeading) {
        AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
        }
        .frame(
          width: geometry.size.width,
          height: fixedHeight ?? geometry.size.width * (16/9)
        )
        .clipped()
        .contentShape(Rectangle())

        // Video Info Overlay
        VStack(alignment: .leading, spacing: 4) {
          Spacer()
          
          HStack {
            // Duration
            Text(formatDuration(video.duration))
              .font(.caption2)
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(.ultraThinMaterial)
              .cornerRadius(2)
            
            Spacer()
            
            // View Count
            HStack(spacing: 2) {
              Image(systemName: "eye.fill")
                .imageScale(.small)
              Text(formatCount(video.viewCount))
            }
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .cornerRadius(2)
          }
          .foregroundColor(.white)
          .padding(6)
        }
      }
    }
    .aspectRatio(9/16, contentMode: .fit) // Force portrait aspect ratio for grid
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let remainingSeconds = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
  }
  
  private func formatCount(_ count: Int) -> String {
    if count >= 1_000_000 {
      return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
      return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
  }
}

#Preview {
  VideoThumbnailView(
    video: Video(
      id: "preview",
      creatorId: "user1",
      caption: "Test video",
      videoURL: "https://example.com/video.mp4",
      thumbnailURL: "https://example.com/thumbnail.jpg",
      likes: 0,
      comments: 0,
      shares: 0,
      createdAt: Date(),
      duration: 65,
      hashtags: ["test"],
      viewCount: 1000,
      completionRate: 0.8,
      engagementScore: 0.7,
      aspectRatio: .portrait
    )
  )
  .frame(width: 200)
}
