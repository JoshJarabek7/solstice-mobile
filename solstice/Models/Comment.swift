import FirebaseFirestore
import Foundation

struct Comment: Identifiable, Codable {
  @DocumentID var id: String?
  let userId: String
  let text: String
  let timestamp: Date
  let username: String
  var likes: Int
  var isLiked: Bool?
  let userProfileImageURL: String?

  enum CodingKeys: String, CodingKey {
    case id
    case userId
    case text
    case timestamp
    case username
    case likes
    case userProfileImageURL
  }

  init(
    userId: String, text: String, timestamp: Date, username: String,
    userProfileImageURL: String? = nil, likes: Int = 0
  ) {
    self.userId = userId
    self.text = text
    self.timestamp = timestamp
    self.username = username
    self.userProfileImageURL = userProfileImageURL
    self.likes = likes
  }
}
