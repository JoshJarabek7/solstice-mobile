import FirebaseFirestore
import Foundation

struct DatingProfile: Codable, Identifiable {
  @DocumentID var id: String?
  let userId: String
  var bio: String
  var photos: [String]
  var interests: [String]
  var maxDistance: Double
  var isActive: Bool
  var lastActive: Date
  var location: FirebaseFirestore.GeoPoint?
  var interestedIn: [User.Gender]
  var gender: User.Gender

  enum CodingKeys: String, CodingKey {
    case id
    case userId
    case bio
    case photos
    case interests
    case maxDistance
    case isActive
    case lastActive
    case location
    case interestedIn
    case gender
  }
}
