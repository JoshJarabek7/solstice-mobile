import FirebaseFirestore
import Foundation

struct BookmarkCollection: Identifiable, Codable {
  @DocumentID var id: String?
  let name: String
  let userId: String
  let isDefault: Bool
  var videos: [String]  // Video IDs
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case userId
    case isDefault
    case videos
    case createdAt
  }

  init(name: String, userId: String, isDefault: Bool, videos: [String]) {
    self.name = name
    self.userId = userId
    self.isDefault = isDefault
    self.videos = videos
    self.createdAt = Date()
  }
}
