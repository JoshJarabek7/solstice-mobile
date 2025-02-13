@preconcurrency import FirebaseFirestore
@preconcurrency import Foundation

struct Video: Identifiable, Codable, Hashable {
  @DocumentID var id: String?
  var creatorId: String
  var caption: String?
  var videoURL: String
  var thumbnailURL: String?
  var likes: Int = 0
  var comments: Int = 0
  var shares: Int = 0
  var createdAt: Date = Date()
  var duration: TimeInterval
  var hashtags: [String] = []

  // Engagement metrics for recommendations
  var viewCount: Int = 0
  var completionRate: Double = 0  // percentage of video watched
  var engagementScore: Double = 0  // calculated based on likes, comments, shares, and views
  var aspectRatio: VideoAspectRatio = .portrait  // Default to portrait

  // For video state management
  var lastPlaybackPosition: TimeInterval?

  enum CodingKeys: String, CodingKey {
    case id
    case creatorId
    case caption
    case videoURL
    case thumbnailURL
    case likes
    case comments
    case shares
    case createdAt
    case duration
    case hashtags
    case viewCount
    case completionRate
    case engagementScore
    case aspectRatio
    case lastPlaybackPosition
  }

  // Implement hash(into:) for Hashable conformance
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(creatorId)
    hasher.combine(videoURL)
    hasher.combine(createdAt)
  }

  // Implement Equatable
  static func == (lhs: Video, rhs: Video) -> Bool {
    lhs.id == rhs.id && lhs.creatorId == rhs.creatorId && lhs.videoURL == rhs.videoURL
      && lhs.createdAt == rhs.createdAt
  }
}

// Since DocumentID isn't Sendable, we need to implement Sendable manually
// and ensure our implementation is safe for concurrent access
extension Video: @unchecked Sendable {
  // All properties are either value types or optional String,
  // which are all safe for concurrent access
}

enum VideoAspectRatio: String, Codable {
  case portrait
  case landscape
  case square

  var aspectRatio: CGFloat {
    switch self {
    case .portrait: return 9 / 16
    case .landscape: return 16 / 9
    case .square: return 1
    }
  }
}

// Extension for video state management
extension Video {
  struct PlaybackState {
    var isPlaying: Bool = false
    var isMuted: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isLoading: Bool = true
  }
}
