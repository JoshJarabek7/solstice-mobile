import FirebaseFirestore
import Foundation
import SwiftUI

enum ChatType: String, Codable {
  case regular
  case group
  case dating
}

struct Chat: Identifiable, Codable {
  @DocumentID var id: String?
  var participants: [User]
  var lastMessage: Message?
  var lastActivity: Date
  var isGroup: Bool
  var name: String?  // Optional group title
  var unreadCounts: [String: Int] = [:]  // User ID -> Unread count
  var isDatingChat: Bool  // True if this chat was created from a dating match
  var ownerId: String?  // Creator of group chat
  var deletedForUsers: [String] = []  // Users who have "deleted" the chat from their view
  var hiddenMessagesForUsers: [String: [String]] = [:]  // User ID -> Array of message IDs they've hidden
  var typingUsers: [String] = []  // Array of user IDs currently typing
  var createdAt: Date?
  var createdBy: String?

  enum CodingKeys: String, CodingKey {
    case id
    case participants
    case lastMessage
    case lastActivity
    case isGroup
    case name
    case unreadCounts
    case unreadCount  // Old format
    case isDatingChat
    case ownerId
    case deletedForUsers
    case hiddenMessagesForUsers
    case typingUsers
    case createdAt
    case createdBy
  }

  private enum MessageCodingKeys: String, CodingKey {
    case id
    case senderId
    case content
    case timestamp
    case type
    case reactions
    case readBy
    case deliveredTo
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    self.id = try container.decodeIfPresent(String.self, forKey: .id)
    self.participants = try container.decode([User].self, forKey: .participants)
    
    // Handle lastMessage decoding
    if let messageContainer = try? container.nestedContainer(keyedBy: MessageCodingKeys.self, forKey: .lastMessage) {
        self.lastMessage = Message(
            id: try? messageContainer.decode(String.self, forKey: .id),
            senderId: try messageContainer.decode(String.self, forKey: .senderId),
            content: try messageContainer.decode(String.self, forKey: .content),
            timestamp: (try? messageContainer.decode(Timestamp.self, forKey: .timestamp))?.dateValue() ?? Date(),
            type: Message.MessageType(rawValue: (try? messageContainer.decode(String.self, forKey: .type)) ?? "text") ?? .text,
            reactions: (try? messageContainer.decode([String: [String]].self, forKey: .reactions)) ?? [:],
            readBy: (try? messageContainer.decode([String].self, forKey: .readBy)) ?? [],
            deliveredTo: (try? messageContainer.decode([String].self, forKey: .deliveredTo)) ?? []
        )
    } else {
        self.lastMessage = try container.decodeIfPresent(Message.self, forKey: .lastMessage)
    }
    
    self.isGroup = try container.decode(Bool.self, forKey: .isGroup)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.isDatingChat = try container.decode(Bool.self, forKey: .isDatingChat)
    self.ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId)
    self.deletedForUsers = try container.decodeIfPresent([String].self, forKey: .deletedForUsers) ?? []
    self.hiddenMessagesForUsers = try container.decodeIfPresent([String: [String]].self, forKey: .hiddenMessagesForUsers) ?? [:]
    self.typingUsers = try container.decodeIfPresent([String].self, forKey: .typingUsers) ?? []
    self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    
    // Handle Timestamp conversion for dates
    if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .lastActivity) {
      self.lastActivity = timestamp.dateValue()
    } else {
      self.lastActivity = Date()
    }
    
    if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: .createdAt) {
      self.createdAt = timestamp.dateValue()
    } else {
      self.createdAt = nil
    }
    
    // Handle both old and new unread count formats
    if let unreadCounts = try? container.decode([String: Int].self, forKey: .unreadCounts) {
      self.unreadCounts = unreadCounts
    } else if let oldUnreadCount = try? container.decode(Int.self, forKey: .unreadCount) {
      // Convert old format to new format - initialize all participants with the old count
      let newUnreadCounts: [String: Int] = Dictionary(
        uniqueKeysWithValues: participants.compactMap { user in
          guard let userId = user.id else { return nil }
          return (userId, oldUnreadCount)
        }
      )
      self.unreadCounts = newUnreadCounts
      
      // Update the document to use the new format
      if let chatId = id {
        // Capture values in local variables to avoid capturing self
        let db = Firestore.firestore()
        Task {
          do {
            try await db.collection("chats").document(chatId).updateData([
              "unreadCounts": newUnreadCounts,
              "unreadCount": FieldValue.delete()
            ])
          } catch {
            print("Error migrating unreadCount to unreadCounts: \(error)")
          }
        }
      }
    } else {
      self.unreadCounts = [:]
    }
  }

  init(
    id: String? = nil,
    participants: [User],
    lastActivity: Date,
    isGroup: Bool,
    name: String? = nil,
    unreadCounts: [String: Int],
    isDatingChat: Bool,
    ownerId: String? = nil,
    lastMessage: Message? = nil,
    deletedForUsers: [String] = [],
    hiddenMessagesForUsers: [String: [String]] = [:],
    typingUsers: [String] = [],
    createdAt: Date? = nil,
    createdBy: String? = nil
  ) {
    self.id = id
    self.participants = participants
    self.lastActivity = lastActivity
    self.isGroup = isGroup
    self.name = name
    self.unreadCounts = unreadCounts
    self.isDatingChat = isDatingChat
    self.ownerId = ownerId
    self.lastMessage = lastMessage
    self.deletedForUsers = deletedForUsers
    self.hiddenMessagesForUsers = hiddenMessagesForUsers
    self.typingUsers = typingUsers
    self.createdAt = createdAt
    self.createdBy = createdBy
  }

  var displayName: String {
    if isGroup {
      if let name = name {
        return name
      } else {
        let participantNames = participants.map { $0.username }
        if participantNames.count <= 3 {
          return participantNames.joined(separator: ", ")
        } else {
          return
            "\(participantNames[0]), \(participantNames[1]), and \(participantNames.count - 2) others"
        }
      }
    } else {
      return participants.first?.username ?? ""
    }
  }

  func isOwner(_ userId: String) -> Bool {
    if isGroup {
      return ownerId == userId || createdBy == userId
    } else {
      return participants.contains { $0.id == userId }
    }
  }

  func isVisibleTo(_ userId: String) -> Bool {
    !deletedForUsers.contains(userId)
  }

  func hiddenMessageIds(for userId: String) -> [String] {
    hiddenMessagesForUsers[userId] ?? []
  }

  // Helper function to get unread count for a specific user
  func unreadCount(for userId: String) -> Int {
    return unreadCounts[userId] ?? 0
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(participants, forKey: .participants)
    try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
    try container.encode(Timestamp(date: lastActivity), forKey: .lastActivity)
    try container.encode(isGroup, forKey: .isGroup)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encode(unreadCounts, forKey: .unreadCounts)
    try container.encode(isDatingChat, forKey: .isDatingChat)
    try container.encodeIfPresent(ownerId, forKey: .ownerId)
    try container.encode(deletedForUsers, forKey: .deletedForUsers)
    try container.encode(hiddenMessagesForUsers, forKey: .hiddenMessagesForUsers)
    try container.encode(typingUsers, forKey: .typingUsers)
    if let createdAt = createdAt {
      try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    }
    try container.encodeIfPresent(createdBy, forKey: .createdBy)
  }
}

struct Message: Identifiable, Codable {
  @DocumentID var id: String?
  var senderId: String
  var content: String
  var timestamp: Date
  var type: MessageType
  var metadata: MessageMetadata?
  var reactions: [String: [String]] = [:]  // emoji: [userIds]
  var replyTo: String?  // ID of message being replied to
  var replyPreview: ReplyPreview?  // Preview of replied message
  var readBy: [String] = []  // Array of user IDs who have read the message
  var deliveredTo: [String] = []  // Array of user IDs who have received the message

  enum MessageType: String, Codable {
    case text
    case image
    case video
    case sharedPost
    case sharedProfile
  }

  var readStatus: ReadStatus {
    if !readBy.isEmpty {
      return .read
    } else if !deliveredTo.isEmpty {
      return .delivered
    } else {
      return .sent
    }
  }

  enum CodingKeys: String, CodingKey {
    case id
    case senderId
    case content
    case timestamp
    case type
    case metadata
    case reactions
    case replyTo
    case replyPreview
    case readBy
    case deliveredTo
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    id = try container.decodeIfPresent(String.self, forKey: .id)
    senderId = try container.decode(String.self, forKey: .senderId)
    content = try container.decode(String.self, forKey: .content)
    
    if let timestamp = try? container.decode(Timestamp.self, forKey: .timestamp) {
      self.timestamp = timestamp.dateValue()
    } else {
      self.timestamp = Date()
    }
    
    type = try container.decode(MessageType.self, forKey: .type)
    metadata = try container.decodeIfPresent(MessageMetadata.self, forKey: .metadata)
    reactions = try container.decodeIfPresent([String: [String]].self, forKey: .reactions) ?? [:]
    replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)
    
    // Handle empty replyPreview object
    if let replyPreviewData = try? container.decode([String: String].self, forKey: .replyPreview),
       !replyPreviewData.isEmpty,
       let messageId = replyPreviewData["messageId"],
       let content = replyPreviewData["content"],
       let senderId = replyPreviewData["senderId"],
       let typeString = replyPreviewData["type"],
       let type = MessageType(rawValue: typeString) {
      self.replyPreview = ReplyPreview(messageId: messageId, content: content, senderId: senderId, type: type)
    } else {
      self.replyPreview = nil
    }
    
    readBy = try container.decodeIfPresent([String].self, forKey: .readBy) ?? []
    deliveredTo = try container.decodeIfPresent([String].self, forKey: .deliveredTo) ?? []
  }

  init(id: String? = nil,
       senderId: String,
       content: String,
       timestamp: Date,
       type: MessageType = .text,
       metadata: MessageMetadata? = nil,
       reactions: [String: [String]] = [:],
       replyTo: String? = nil,
       replyPreview: ReplyPreview? = nil,
       readBy: [String] = [],
       deliveredTo: [String] = []) {
    self.id = id
    self.senderId = senderId
    self.content = content
    self.timestamp = timestamp
    self.type = type
    self.metadata = metadata
    self.reactions = reactions
    self.replyTo = replyTo
    self.replyPreview = replyPreview
    self.readBy = readBy
    self.deliveredTo = deliveredTo
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode(senderId, forKey: .senderId)
    try container.encode(content, forKey: .content)
    try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(metadata, forKey: .metadata)
    try container.encode(reactions, forKey: .reactions)
    try container.encodeIfPresent(replyTo, forKey: .replyTo)
    
    if let preview = replyPreview {
      try container.encode(preview.asDictionary(), forKey: .replyPreview)
    } else {
      try container.encodeNil(forKey: .replyPreview)
    }
    
    try container.encode(readBy, forKey: .readBy)
    try container.encode(deliveredTo, forKey: .deliveredTo)
  }
}

enum ReadStatus {
  case sent
  case delivered
  case read

  var icon: String {
    switch self {
    case .sent:
      return "checkmark"
    case .delivered:
      return "checkmark.circle"
    case .read:
      return "checkmark.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .sent:
      return .gray
    case .delivered:
      return .gray
    case .read:
      return .blue
    }
  }
}

struct MessageMetadata: Codable {
  // Video metadata
  var videoId: String?
  var videoThumbnail: String?
  var videoCaption: String?
  var videoCreator: String?  // Username of video creator

  // Post metadata
  var postId: String?
  var postThumbnail: String?
  var postCaption: String?
  var postCreator: String?

  // Profile metadata
  var profileId: String?
  var profileImage: String?
  var profileUsername: String?
  var profileFullName: String?
  var profileBio: String?

  // Image metadata
  var imageUrl: String?

  func truncatedCaption(_ text: String?) -> String? {
    guard let text = text else { return nil }
    if text.count > 30 {
      return String(text.prefix(30)) + "..."
    }
    return text
  }

  var truncatedPostCaption: String? {
    truncatedCaption(postCaption)
  }

  var truncatedProfileBio: String? {
    truncatedCaption(profileBio)
  }
}

struct ReplyPreview: Codable {
  var messageId: String
  var content: String
  var senderId: String
  var type: Message.MessageType

  enum CodingKeys: String, CodingKey {
    case messageId
    case content
    case senderId
    case type
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    messageId = try container.decode(String.self, forKey: .messageId)
    content = try container.decode(String.self, forKey: .content)
    senderId = try container.decode(String.self, forKey: .senderId)
    
    let typeString = try container.decode(String.self, forKey: .type)
    if let messageType = Message.MessageType(rawValue: typeString) {
      type = messageType
    } else {
      type = .text // Default to text if type is invalid
    }
  }

  init(messageId: String, content: String, senderId: String, type: Message.MessageType) {
    self.messageId = messageId
    self.content = content
    self.senderId = senderId
    self.type = type
  }

  var truncatedContent: String {
    if content.count > 50 {
      return String(content.prefix(50)) + "..."
    }
    return content
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(messageId, forKey: .messageId)
    try container.encode(content, forKey: .content)
    try container.encode(senderId, forKey: .senderId)
    try container.encode(type.rawValue, forKey: .type)
  }

  func asDictionary() -> [String: String] {
    [
      "messageId": messageId,
      "content": content,
      "senderId": senderId,
      "type": type.rawValue
    ]
  }
}

// Extension to make Chat Hashable
extension Chat: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Chat, rhs: Chat) -> Bool {
    lhs.id == rhs.id
  }
}

// Since DocumentID isn't Sendable, we need to implement Sendable manually
extension Chat: @unchecked Sendable {
  // All properties are either value types or optional String,
  // which are all safe for concurrent access
}

// Extension to make Message Hashable
extension Message: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Message, rhs: Message) -> Bool {
    lhs.id == rhs.id
  }
}

// Helper methods for Message
extension Message {
  func addReaction(_ emoji: String, by userId: String) -> Message {
    var newMessage = self
    var userIds = newMessage.reactions[emoji] ?? []
    if !userIds.contains(userId) {
      userIds.append(userId)
      newMessage.reactions[emoji] = userIds
    }
    return newMessage
  }

  func removeReaction(_ emoji: String, by userId: String) -> Message {
    var newMessage = self
    if var userIds = newMessage.reactions[emoji] {
      userIds.removeAll { $0 == userId }
      if userIds.isEmpty {
        newMessage.reactions.removeValue(forKey: emoji)
      } else {
        newMessage.reactions[emoji] = userIds
      }
    }
    return newMessage
  }

  func reactionCount(for emoji: String) -> Int {
    reactions[emoji]?.count ?? 0
  }

  func hasReaction(_ emoji: String, by userId: String) -> Bool {
    reactions[emoji]?.contains(userId) ?? false
  }
}

// Since DocumentID isn't Sendable, we need to implement Sendable manually
extension Message: @unchecked Sendable {
  // All properties are either value types or optional String,
  // which are all safe for concurrent access
}

extension ReplyPreview: @unchecked Sendable {}
