import FirebaseFirestore
import Foundation

struct ChatEvent: Identifiable, Codable {
  @DocumentID var id: String?
  var type: EventType
  var userId: String
  var performedBy: String
  var timestamp: Date

  enum EventType: String, Codable {
    case memberAdded
    case memberRemoved
  }

  var displayText: String {
    let formatter = RelativeDateTimeFormatter()
    let timeAgo = formatter.localizedString(for: timestamp, relativeTo: Date())

    switch type {
    case .memberAdded:
      return "Added @\(userId) • \(timeAgo)"
    case .memberRemoved:
      return "Removed @\(userId) • \(timeAgo)"
    }
  }
}

// Since DocumentID isn't Sendable, we need to implement Sendable manually
extension ChatEvent: @unchecked Sendable {
  // All properties are either value types or optional String,
  // which are all safe for concurrent access
}
