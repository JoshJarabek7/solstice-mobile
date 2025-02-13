@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
import SwiftUI

// MARK: - Async Extensions
extension Sequence {
  func asyncMap<T>(
    _ transform: (Element) async throws -> T
  ) async rethrows -> [T] {
    var values = [T]()
    for element in self {
      try await values.append(transform(element))
    }
    return values
  }
}

// Wrapper class to make listeners Sendable
@MainActor
final class SendableListeners {
  private(set) var listeners: [ListenerRegistration] = []

  func add(_ listener: ListenerRegistration) {
    listeners.append(listener)
  }

  func addContentsOf(_ newListeners: [ListenerRegistration]) {
    listeners.append(contentsOf: newListeners)
  }

  func removeAll() {
    listeners.forEach { $0.remove() }
    listeners.removeAll()
  }

  // Cleanup function that can be called from any context
  nonisolated func cleanup() {
    // Since we can't make deinit async, we'll use a detached task
    Task.detached { @MainActor in
      // Capture the listeners in the actor context
      let listenersToRemove = self.listeners
      // Remove each listener
      listenersToRemove.forEach { $0.remove() }
    }
  }
}

@MainActor
@Observable
final class MessagesViewModel {
  @ObservationIgnored private let db = Firestore.firestore()
  @ObservationIgnored private let listeners = SendableListeners()
  @ObservationIgnored private let currentUserId: String
  
  var regularChats: [Chat] = [] {
    didSet {
      print("[DEBUG] Regular chats updated, count: \(regularChats.count)")
      if let lastChat = regularChats.first {
        print("[DEBUG] First chat last message: \(lastChat.lastMessage?.content ?? "nil")")
      }
    }
  }
  var groupChats: [Chat] = []
  var datingChats: [Chat] = []
  var isLoading = false
  var error: Error?
  var errorMessage: String?

  private func fetchUser(id userId: String) async throws -> User {
    let userDoc = try await db.collection("users").document(userId).getDocument()
    guard let userData = userDoc.data() else {
      throw ChatError.userNotFound
    }
    
    // Handle nested ageRange structure
    var data = userData
    if let ageRange = data["ageRange"] as? [String: Any] {
      data["ageRange.min"] = ageRange["min"] as? Int ?? 18
      data["ageRange.max"] = ageRange["max"] as? Int ?? 100
      data.removeValue(forKey: "ageRange")
    }
    
    let decoder = Firestore.Decoder()
    var user = try decoder.decode(User.self, from: data)
    user.id = userId
    return user
  }

  init() {
    print("[DEBUG] Initializing MessagesViewModel")
    self.currentUserId = Auth.auth().currentUser?.uid ?? ""
    print("[DEBUG] Current user ID: \(currentUserId)")
    
    // Start loading chats immediately
    Task {
      print("[DEBUG] Starting initial chat load")
      await loadChats()
      print("[DEBUG] Completed initial chat load")
      print("[DEBUG] Regular chats: \(regularChats.count)")
      print("[DEBUG] Group chats: \(groupChats.count)")
      print("[DEBUG] Dating chats: \(datingChats.count)")
    }
  }

  deinit {
    print("[DEBUG] MessagesViewModel deinit - cleaning up listeners")
    listeners.cleanup()
  }

  func loadChats() async {
    guard !currentUserId.isEmpty else {
      print("[ERROR] Cannot load chats - user not authenticated")
      errorMessage = "User not authenticated"
      return
    }
    
    print("[DEBUG] Loading chats for user: \(currentUserId)")
    isLoading = true
    error = nil
    errorMessage = nil

    // Remove existing listeners
    listeners.removeAll()
    print("[DEBUG] Removed existing listeners")

    do {
      print("[DEBUG] Fetching chats...")
      // Immediately fetch latest data for each chat type
      async let regularChatsTask = fetchLatestChats(isDating: false, isGroup: false)
      async let groupChatsTask = fetchLatestChats(isDating: false, isGroup: true)
      async let datingChatsTask = fetchLatestChats(isDating: true, isGroup: false)
      
      // Wait for all fetches to complete
      let (regularResults, groupResults, datingResults) = try await (regularChatsTask, groupChatsTask, datingChatsTask)
      
      print("[DEBUG] Fetched chats - Regular: \(regularResults.count), Group: \(groupResults.count), Dating: \(datingResults.count)")
      
      // Update the chat arrays
      self.regularChats = regularResults
      self.groupChats = groupResults
      self.datingChats = datingResults
      
      // Setup real-time listeners for future updates
      print("[DEBUG] Setting up real-time listeners")
      let regularListener = setupChatListener(isDating: false, isGroup: false)
      let groupListener = setupChatListener(isDating: false, isGroup: true)
      let datingListener = setupChatListener(isDating: true, isGroup: false)
      
      listeners.addContentsOf([regularListener, groupListener, datingListener])
      print("[DEBUG] Listeners setup complete")
    } catch {
      print("[ERROR] Error refreshing chats: \(error)")
      self.error = error
      self.errorMessage = "Error refreshing chats: \(error.localizedDescription)"
    }
    
    isLoading = false
  }

  // Update the ChatDocumentData struct to use Timestamp instead of Date
  struct ChatDocumentData: Codable {
    let participantIds: [String]
    let lastActivity: Timestamp
    let isGroup: Bool
    let name: String?
    let unreadCounts: [String: Int]
    let isDatingChat: Bool
    let deletedForUsers: [String]
    let hiddenMessagesForUsers: [String: [String]]
    let typingUsers: [String]
    let createdAt: Timestamp
    let createdBy: String
    private let lastMessage: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case participantIds, lastActivity, isGroup, name, unreadCounts, isDatingChat,
             deletedForUsers, hiddenMessagesForUsers, typingUsers, createdAt, createdBy, lastMessage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantIds = try container.decode([String].self, forKey: .participantIds)
        lastActivity = try container.decode(Timestamp.self, forKey: .lastActivity)
        isGroup = try container.decode(Bool.self, forKey: .isGroup)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        unreadCounts = try container.decode([String: Int].self, forKey: .unreadCounts)
        isDatingChat = try container.decode(Bool.self, forKey: .isDatingChat)
        deletedForUsers = try container.decode([String].self, forKey: .deletedForUsers)
        hiddenMessagesForUsers = try container.decode([String: [String]].self, forKey: .hiddenMessagesForUsers)
        typingUsers = try container.decode([String].self, forKey: .typingUsers)
        createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        
        // Get the raw data from the decoder's userInfo
        if let rawData = decoder.userInfo[.documentDataKey],
           let lastMessageData = (rawData as? [String: Any])?["lastMessage"] as? [String: Any] {
            self.lastMessage = lastMessageData
        } else {
            self.lastMessage = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(participantIds, forKey: .participantIds)
        try container.encode(lastActivity, forKey: .lastActivity)
        try container.encode(isGroup, forKey: .isGroup)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(unreadCounts, forKey: .unreadCounts)
        try container.encode(isDatingChat, forKey: .isDatingChat)
        try container.encode(deletedForUsers, forKey: .deletedForUsers)
        try container.encode(hiddenMessagesForUsers, forKey: .hiddenMessagesForUsers)
        try container.encode(typingUsers, forKey: .typingUsers)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(createdBy, forKey: .createdBy)
        // Skip encoding lastMessage as it's handled separately
    }
    
    init(participantIds: [String], lastActivity: Timestamp, isGroup: Bool, name: String?, 
         unreadCounts: [String: Int], isDatingChat: Bool, deletedForUsers: [String],
         hiddenMessagesForUsers: [String: [String]], typingUsers: [String], 
         createdAt: Timestamp, createdBy: String, lastMessage: [String: Any]?) {
        self.participantIds = participantIds
        self.lastActivity = lastActivity
        self.isGroup = isGroup
        self.name = name
        self.unreadCounts = unreadCounts
        self.isDatingChat = isDatingChat
        self.deletedForUsers = deletedForUsers
        self.hiddenMessagesForUsers = hiddenMessagesForUsers
        self.typingUsers = typingUsers
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.lastMessage = lastMessage
    }
    
    func getLastMessage() -> Message? {
        guard let lastMessage = lastMessage else { return nil }
        
        let messageId = lastMessage["id"] as? String ?? UUID().uuidString
        let content = lastMessage["content"] as? String ?? ""
        let senderId = lastMessage["senderId"] as? String ?? ""
        let timestamp = (lastMessage["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        let readBy = lastMessage["readBy"] as? [String] ?? []
        let deliveredTo = lastMessage["deliveredTo"] as? [String] ?? []
        let reactions = lastMessage["reactions"] as? [String: [String]] ?? [:]
        let replyTo = lastMessage["replyTo"] as? String
        
        return Message(
            id: messageId,
            senderId: senderId,
            content: content,
            timestamp: timestamp,
            type: .text,
            metadata: MessageMetadata(),
            reactions: reactions,
            replyTo: replyTo,
            replyPreview: nil,
            readBy: readBy,
            deliveredTo: deliveredTo
        )
    }
    
    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "participantIds": participantIds,
            "lastActivity": lastActivity,
            "isGroup": isGroup,
            "unreadCounts": unreadCounts,
            "isDatingChat": isDatingChat,
            "deletedForUsers": deletedForUsers,
            "hiddenMessagesForUsers": hiddenMessagesForUsers,
            "typingUsers": typingUsers,
            "createdAt": createdAt,
            "createdBy": createdBy
        ]
        
        if let name = name {
            dict["name"] = name
        }
        
        if let lastMessage = lastMessage {
            dict["lastMessage"] = lastMessage
        }
        
        return dict
    }
  }

  private func processDocument(_ document: QueryDocumentSnapshot) async throws -> Chat? {
    do {
      // Create decoder with document data in userInfo
      let decoder = Firestore.Decoder()
      decoder.userInfo[.documentDataKey] = document.data()
      
      // Decode the chat data
      let chatData = try document.data(as: ChatDocumentData.self, decoder: decoder)
      
      // Filter deleted chats
      if chatData.deletedForUsers.contains(currentUserId) {
        return nil
      }
      
      // Fetch user information for each participant
      var participants: [User] = []
      for userId in chatData.participantIds {
        do {
          let user = try await fetchUser(id: userId)
          participants.append(user)
        } catch {
          print("[ERROR] Failed to fetch user \(userId): \(error)")
          // Continue with other participants even if one fails
          continue
        }
      }
      
      // Create the full chat object
      return Chat(
        id: document.documentID,
        participants: participants,
        lastActivity: chatData.lastActivity.dateValue(),
        isGroup: chatData.isGroup,
        name: chatData.name,
        unreadCounts: chatData.unreadCounts,
        isDatingChat: chatData.isDatingChat,
        ownerId: chatData.createdBy,
        lastMessage: chatData.getLastMessage(),
        deletedForUsers: chatData.deletedForUsers,
        hiddenMessagesForUsers: chatData.hiddenMessagesForUsers,
        typingUsers: chatData.typingUsers,
        createdAt: chatData.createdAt.dateValue(),
        createdBy: chatData.createdBy
      )
    } catch {
      print("[ERROR] Error processing chat document \(document.documentID): \(error)")
      return nil
    }
  }

  // Update fetchLatestChats to use the new processing function
  private func fetchLatestChats(isDating: Bool, isGroup: Bool) async throws -> [Chat] {
    print("[DEBUG] Fetching \(isDating ? "dating" : isGroup ? "group" : "regular") chats")
    print("[DEBUG] Current user ID: \(currentUserId)")
    
    let query = db.collection("chats")
        .whereField("participantIds", arrayContains: currentUserId)
        .whereField("isDatingChat", isEqualTo: isDating)
        .whereField("isGroup", isEqualTo: isGroup)
        .order(by: "lastActivity", descending: true)
        .limit(to: 50)
    
    print("[DEBUG] Executing query: \(query)")
    let snapshot = try await query.getDocuments()
    print("[DEBUG] Found \(snapshot.documents.count) documents")
    
    var updatedChats: [Chat] = []
    
    for document in snapshot.documents {
      if let chat = try await processDocument(document) {
        updatedChats.append(chat)
      }
    }
    
    // Sort the chats by lastActivity
    updatedChats.sort { chat1, chat2 in
      let date1 = chat1.lastMessage?.timestamp ?? chat1.lastActivity
      let date2 = chat2.lastMessage?.timestamp ?? chat2.lastActivity
      return date1 > date2
    }
    
    print("[DEBUG] Returning \(updatedChats.count) chats")
    return updatedChats
  }

  // Update setupChatListener to use the new processing function
  private func setupChatListener(isDating: Bool, isGroup: Bool) -> ListenerRegistration {
    print("[DEBUG] Setting up listener for isDating: \(isDating), isGroup: \(isGroup)")
    
    return db.collection("chats")
        .whereField("participantIds", arrayContains: currentUserId)
        .whereField("isDatingChat", isEqualTo: isDating)
        .whereField("isGroup", isEqualTo: isGroup)
        .whereField("deletedForUsers", notIn: [currentUserId])
        .order(by: "lastActivity", descending: true)
        .addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[ERROR] Chat listener error: \(error)")
                Task { @MainActor in
                    self.error = error
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let snapshot = snapshot else {
                print("[ERROR] No snapshot received")
                return
            }
            
            // Process each change immediately
            for change in snapshot.documentChanges {
                let doc = change.document
                print("[DEBUG] Processing chat document change: \(change.type) - \(doc.documentID)")
                
                // Use Task.detached for proper actor isolation
                Task.detached {
                    do {
                        // Create decoder with document data in userInfo
                        let decoder = Firestore.Decoder()
                        if let data = doc.data() as? [String: Any] {
                            decoder.userInfo[.documentDataKey] = data
                            print("[DEBUG] Chat document data: \(data)")
                        }
                        
                        // Decode chat document data
                        let chatData = try decoder.decode(ChatDocumentData.self, from: doc.data())
                        
                        // Fetch participants
                        let participants = try await chatData.participantIds.asyncMap { userId -> User in
                            try await self.fetchUser(id: userId)
                        }
                        
                        // Create chat object with the latest message
                        let lastMessage = chatData.getLastMessage()
                        print("[DEBUG] Last message content: \(lastMessage?.content ?? "nil")")
                        
                        let chat = Chat(
                            id: doc.documentID,
                            participants: participants,
                            lastActivity: chatData.lastActivity.dateValue(),
                            isGroup: chatData.isGroup,
                            name: chatData.name,
                            unreadCounts: chatData.unreadCounts,
                            isDatingChat: chatData.isDatingChat,
                            lastMessage: lastMessage,
                            deletedForUsers: chatData.deletedForUsers,
                            hiddenMessagesForUsers: chatData.hiddenMessagesForUsers,
                            typingUsers: chatData.typingUsers,
                            createdAt: chatData.createdAt.dateValue(),
                            createdBy: chatData.createdBy
                        )
                        
                        // Update the UI on the main actor
                        await MainActor.run {
                            switch change.type {
                            case .added:
                                self.addChat(chat)
                                print("[DEBUG] Added chat with last message: \(chat.lastMessage?.content ?? "nil")")
                            case .modified:
                                self.updateChat(chat)
                                print("[DEBUG] Modified chat with last message: \(chat.lastMessage?.content ?? "nil")")
                            case .removed:
                                self.removeChat(chat)
                                print("[DEBUG] Removed chat")
                            }
                        }
                    } catch {
                        print("[ERROR] Error processing chat document: \(error)")
                        await MainActor.run {
                            self.error = error
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
  }

  private func addChat(_ chat: Chat) {
    Task { @MainActor in
      if chat.isDatingChat {
        if !datingChats.contains(where: { $0.id == chat.id }) {
          var chats = datingChats
          chats.append(chat)
          chats.sort { $0.lastActivity > $1.lastActivity }
          datingChats = chats
        }
      } else if chat.isGroup {
        if !groupChats.contains(where: { $0.id == chat.id }) {
          var chats = groupChats
          chats.append(chat)
          chats.sort { $0.lastActivity > $1.lastActivity }
          groupChats = chats
        }
      } else {
        if !regularChats.contains(where: { $0.id == chat.id }) {
          var chats = regularChats
          chats.append(chat)
          chats.sort { $0.lastActivity > $1.lastActivity }
          regularChats = chats
        }
      }
    }
  }

  private func updateChat(_ updatedChat: Chat) {
    print("[DEBUG] Updating chat: \(updatedChat.id ?? "unknown") with last message: \(updatedChat.lastMessage?.content ?? "nil")")
    
    Task { @MainActor in
      if updatedChat.isDatingChat {
        if let index = datingChats.firstIndex(where: { $0.id == updatedChat.id }) {
          var chats = datingChats
          chats.remove(at: index)
          chats.insert(updatedChat, at: 0)
          datingChats = chats
          print("[DEBUG] Updated dating chat with message: \(updatedChat.lastMessage?.content ?? "nil")")
        }
      } else if updatedChat.isGroup {
        if let index = groupChats.firstIndex(where: { $0.id == updatedChat.id }) {
          var chats = groupChats
          chats.remove(at: index)
          chats.insert(updatedChat, at: 0)
          groupChats = chats
          print("[DEBUG] Updated group chat with message: \(updatedChat.lastMessage?.content ?? "nil")")
        }
      } else {
        if let index = regularChats.firstIndex(where: { $0.id == updatedChat.id }) {
          var chats = regularChats
          chats.remove(at: index)
          chats.insert(updatedChat, at: 0)
          regularChats = chats
          print("[DEBUG] Updated regular chat with message: \(updatedChat.lastMessage?.content ?? "nil")")
        }
      }
    }
  }

  private func removeChat(_ chat: Chat) {
    if chat.isDatingChat {
        datingChats.removeAll { $0.id == chat.id }
    } else if chat.isGroup {
        groupChats.removeAll { $0.id == chat.id }
    } else {
        regularChats.removeAll { $0.id == chat.id }
    }
  }

  private func findExistingChat(with participants: [User], isDating: Bool = false) async throws -> Chat? {
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        throw ChatError.userNotAuthenticated
    }

    // Get all participant IDs
    let participantIds = participants.compactMap { $0.id }
    guard !participantIds.isEmpty else {
        throw ChatError.invalidUsers
    }

    // Query for chats where current user is a participant
    let chats = try await db.collection("chats")
        .whereField("participantIds", arrayContains: currentUserId)
        .whereField("isGroup", isEqualTo: false)
        .whereField("isDatingChat", isEqualTo: isDating)
        .getDocuments()

    // Check each chat to see if it has exactly the same participants
    for doc in chats.documents {
        if let chatParticipantIds = doc.get("participantIds") as? [String],
           Set(chatParticipantIds) == Set(participantIds) {
            // Found matching chat
            var chat = try doc.data(as: Chat.self)
            chat.id = doc.documentID
            return chat
        }
    }

    return nil
  }

  // Participant preview for efficient loading
  struct ParticipantPreview {
    let id: String
    let username: String
    let profileImageURL: String?
    
    var asDictionary: [String: Any] {
      [
        "id": id,
        "username": username,
        "profileImageURL": profileImageURL as Any
      ]
    }
  }

  // Add Sendable types before the createChatInFirebase function
  private struct SendableChatData: Sendable {
    let participantIds: [String]
    let lastActivity: Timestamp
    let isGroup: Bool
    let name: String?
    let unreadCounts: [String: Int]
    let isDatingChat: Bool
    let deletedForUsers: [String]
    let hiddenMessagesForUsers: [String: [String]]
    let typingUsers: [String]
    let createdAt: Timestamp
    let createdBy: String
    
    var asDictionary: [String: Any] {
      var dict: [String: Any] = [
        "participantIds": participantIds,
        "lastActivity": lastActivity,
        "isGroup": isGroup,
        "unreadCounts": unreadCounts,
        "isDatingChat": isDatingChat,
        "deletedForUsers": deletedForUsers,
        "hiddenMessagesForUsers": hiddenMessagesForUsers,
        "typingUsers": typingUsers,
        "createdAt": createdAt,
        "createdBy": createdBy
      ]
      if let name = name {
        dict["name"] = name
      }
      return dict
    }
  }
  
  // Add Sendable metadata types before SendableMessageData
  private struct SendableMetadata: Sendable {
    let values: [String: String]
    
    var asDictionary: [String: Any] { values }
    
    init(from dict: [String: Any]?) {
      self.values = (dict as? [String: String]) ?? [:]
    }
  }
  
  private struct SendablePreview: Sendable {
    let values: [String: String]
    
    var asDictionary: [String: Any] { values }
    
    init(from dict: [String: Any]?) {
      self.values = (dict as? [String: String]) ?? [:]
    }
  }
  
  private struct SendableMessageData: Sendable {
    let id: String
    let content: String
    let senderId: String
    let timestamp: Timestamp
    let type: String
    let readBy: [String]
    let deliveredTo: [String]
    let reactions: [String: [String]]
    let metadata: SendableMetadata?
    let replyTo: String?
    let replyPreview: SendablePreview?
    
    var asDictionary: [String: Any] {
      [
        "id": id,
        "content": content,
        "senderId": senderId,
        "timestamp": timestamp,
        "type": type,
        "readBy": readBy,
        "deliveredTo": deliveredTo,
        "reactions": reactions,
        "replyTo": replyTo as Any,
        "metadata": metadata?.asDictionary as Any,
        "replyPreview": replyPreview?.asDictionary as Any
      ] as [String: Any]
    }
  }
  
  private struct IsolatedData: Sendable {
    let chatData: SendableChatData
    let messageData: SendableMessageData
    let chatId: String
    let participantIds: [String]
    let senderId: String
  }

  func findOrCreateChat(with participants: [User], type: ChatType, name: String? = nil) async throws -> Chat {
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        throw ChatError.userNotAuthenticated
    }

    // Ensure all participants have IDs
    let participantIds = participants.compactMap { $0.id }
    guard participantIds.count == participants.count else {
        throw ChatError.invalidUsers
    }

    // For regular chats, check if a chat already exists
    if type == .regular {
        // Create a sorted string of participant IDs to use as a unique identifier
        let sortedParticipantIds = participantIds.sorted().joined(separator: "_")
        let chatId = "chat_\(sortedParticipantIds)"
        
        // Try to get the existing chat document
        let chatRef = db.collection("chats").document(chatId)
        let chatDoc = try await chatRef.getDocument()
        
        if chatDoc.exists {
            // Chat exists, return it
            var chat = try chatDoc.data(as: Chat.self)
            chat.id = chatDoc.documentID
            chat.participants = participants
            return chat
        }
        
        // Create a new chat with the deterministic ID
        let chatDict: [String: Any] = [
            "participantIds": participantIds,
            "lastActivity": Timestamp(date: Date()),
            "isGroup": false,
            "name": name as Any,
            "unreadCounts": Dictionary(uniqueKeysWithValues: participants.compactMap { ($0.id!, 0) }),
            "isDatingChat": false,
            "deletedForUsers": [],
            "hiddenMessagesForUsers": [:] as [String: [String]],
            "typingUsers": [],
            "createdAt": Timestamp(date: Date()),
            "createdBy": currentUserId,
            "lastMessage": NSNull() as Any
        ]
        
        // Try to create the chat document
        try await chatRef.setData(chatDict, merge: true)
        
        return Chat(
            id: chatId,
            participants: participants,
            lastActivity: Date(),
            isGroup: false,
            name: name,
            unreadCounts: Dictionary(uniqueKeysWithValues: participants.compactMap { ($0.id!, 0) }),
            isDatingChat: false,
            ownerId: currentUserId,
            lastMessage: nil,
            deletedForUsers: [],
            hiddenMessagesForUsers: [:],
            typingUsers: [],
            createdAt: Date(),
            createdBy: currentUserId
        )
    }

    // For group or dating chats, create new chat with auto-generated ID
    let chatRef = db.collection("chats").document()
    let chatId = chatRef.documentID
    
    let chatDict: [String: Any] = [
        "participantIds": participantIds,
        "lastActivity": Timestamp(date: Date()),
        "isGroup": type == .group,
        "name": name as Any,
        "unreadCounts": Dictionary(uniqueKeysWithValues: participants.compactMap { ($0.id!, 0) }),
        "isDatingChat": type == .dating,
        "deletedForUsers": [],
        "hiddenMessagesForUsers": [:] as [String: [String]],
        "typingUsers": [],
        "createdAt": Timestamp(date: Date()),
        "createdBy": currentUserId,
        "lastMessage": NSNull() as Any
    ]
    
    // Set the chat document data
    try await chatRef.setData(chatDict)
    
    return Chat(
        id: chatId,
        participants: participants,
        lastActivity: Date(),
        isGroup: type == .group,
        name: name,
        unreadCounts: Dictionary(uniqueKeysWithValues: participants.compactMap { ($0.id!, 0) }),
        isDatingChat: type == .dating,
        ownerId: currentUserId,
        lastMessage: nil,
        deletedForUsers: [],
        hiddenMessagesForUsers: [:],
        typingUsers: [],
        createdAt: Date(),
        createdBy: currentUserId
    )
  }
  
  private func getCurrentUser() async throws -> User {
    let userDoc = try await db.collection("users").document(currentUserId).getDocument()
    guard let userData = userDoc.data() else {
      throw ChatError.userNotFound
    }
    
    return User(
      username: userData["username"] as? String ?? "",
      email: userData["email"] as? String ?? "",
      fullName: userData["fullName"] as? String ?? "",
      gender: User.Gender(rawValue: userData["gender"] as? String ?? "") ?? .other
    )
  }

  // Add message to chat
  func addMessageToChat(_ chat: Chat, message: Message) async throws {
    guard let chatId = chat.id else { throw ChatError.invalidChat }
    let userId = currentUserId
    let timestamp = Date()
    
    try await Task.detached {
      // Create message document first to get its ID
      let messageRef = Firestore.firestore().collection("chats").document(chatId).collection("messages").document()
      let messageId = messageRef.documentID
      
      // Create message data with all required fields
      let messageData: [String: Any] = [
        "id": messageId,
        "content": message.content,
        "senderId": message.senderId,
        "timestamp": Timestamp(date: timestamp),
        "type": message.type.rawValue,
        "readBy": [message.senderId],
        "deliveredTo": [message.senderId],
        "reactions": [:],
        "metadata": message.metadata?.asDictionary() as Any,
        "replyTo": message.replyTo as Any,
        "replyPreview": message.replyPreview?.asDictionary() as Any
      ]
      
      // Batch write to ensure atomicity
      let batch = Firestore.firestore().batch()
      
      // Add message to messages collection
      batch.setData(messageData, forDocument: messageRef)
      
      // Update chat document with the new lastMessage
      let chatRef = Firestore.firestore().collection("chats").document(chatId)
      let chatUpdateData: [String: Any] = [
        "lastMessage": messageData,
        "lastActivity": Timestamp(date: timestamp),
        "unreadCounts.\(userId)": 0
      ]
      
      // Update unread counts for other participants
      let otherParticipantIds = chat.participants
        .compactMap { $0.id }
        .filter { $0 != userId }
      
      // Update the chat document
      batch.updateData(chatUpdateData, forDocument: chatRef)
      
      // Update unread counts for other participants
      for participantId in otherParticipantIds {
        batch.updateData(["unreadCounts.\(participantId)": FieldValue.increment(Int64(1))], forDocument: chatRef)
      }
      
      // Commit all changes atomically
      try await batch.commit()
      
      // Force a refresh of the chat list to update the UI
      await MainActor.run {
        Task {
          await self.loadChats()
          
          // Force UI refresh by temporarily clearing and restoring the chat arrays
          let tempRegular = self.regularChats
          let tempGroup = self.groupChats
          let tempDating = self.datingChats
          
          self.regularChats = []
          self.groupChats = []
          self.datingChats = []
          
          self.regularChats = tempRegular
          self.groupChats = tempGroup
          self.datingChats = tempDating
        }
      }
    }.value
  }

  // New function to actually create the chat in Firebase when first message is sent
  func createChatInFirebase(_ chat: Chat, firstMessage: Message) async throws -> Chat {
    guard !currentUserId.isEmpty else { throw ChatError.userNotAuthenticated }
    guard let chatId = chat.id else { throw ChatError.invalidChat }
    
    // Double check one more time for existing chat to prevent race conditions
    if !chat.isGroup {
        let otherUserIds = chat.participants.filter { $0.id != currentUserId }.map { $0.id ?? "" }
        let allParticipantIds = Set([currentUserId] + otherUserIds)
        
        let query = db.collection("chats")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isDatingChat", isEqualTo: chat.isDatingChat)
            .whereField("isGroup", isEqualTo: false)
            .whereField("deletedForUsers", notIn: [currentUserId])
        
        let snapshot = try await query.getDocuments()
        
        for document in snapshot.documents {
            if let participantIds = document.data()["participantIds"] as? [String],
               Set(participantIds) == allParticipantIds {
                if var existingChat = try? document.data(as: Chat.self) {
                    existingChat.id = document.documentID
                    return existingChat
                }
            }
        }
    }
    
    // Get all participant IDs including the current user
    let otherUserIds = chat.participants.compactMap { $0.id }
    let allParticipantIds = [currentUserId] + otherUserIds
    
    // Create sendable chat data
    let chatData = SendableChatData(
        participantIds: allParticipantIds,
        lastActivity: Timestamp(date: Date()),
        isGroup: chat.isGroup,
        name: chat.name,
        unreadCounts: Dictionary(uniqueKeysWithValues: allParticipantIds.map { ($0, 0) }),
        isDatingChat: chat.isDatingChat,
        deletedForUsers: [],
        hiddenMessagesForUsers: [:],
        typingUsers: [],
        createdAt: Timestamp(date: Date()),
        createdBy: currentUserId
    )
    
    // Create sendable message data
    let messageData = SendableMessageData(
        id: firstMessage.id ?? UUID().uuidString,
        content: firstMessage.content,
        senderId: firstMessage.senderId,
        timestamp: Timestamp(date: firstMessage.timestamp),
        type: firstMessage.type.rawValue,
        readBy: [firstMessage.senderId],
        deliveredTo: [firstMessage.senderId],
        reactions: [:],
        metadata: SendableMetadata(from: firstMessage.metadata?.asDictionary()),
        replyTo: firstMessage.replyTo,
        replyPreview: SendablePreview(from: firstMessage.replyPreview?.asDictionary())
    )
    
    // Create isolated data
    let isolatedData = IsolatedData(
        chatData: chatData,
        messageData: messageData,
        chatId: chatId,
        participantIds: allParticipantIds,
        senderId: firstMessage.senderId
    )
    
    // Perform database operations in a detached task to avoid actor isolation issues
    try await Task.detached { @Sendable in
        // Create chat document
        try await Firestore.firestore().collection("chats").document(isolatedData.chatId).setData(isolatedData.chatData.asDictionary)
        
        // Add message to messages subcollection
        try await Firestore.firestore().collection("chats")
            .document(isolatedData.chatId)
            .collection("messages")
            .document(isolatedData.messageData.id)
            .setData(isolatedData.messageData.asDictionary)
        
        // Create update data for the chat document
        var updateData: [String: Any] = [
            "lastMessage": isolatedData.messageData.asDictionary,
            "lastActivity": Timestamp(date: Date())
        ]
        
        // Update unread counts
        for participantId in isolatedData.participantIds {
            if participantId != isolatedData.senderId {
                updateData["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
            } else {
                updateData["unreadCounts.\(participantId)"] = 0
            }
        }
        
        // Update chat document
        try await Firestore.firestore().collection("chats").document(isolatedData.chatId).updateData(updateData)
    }.value
    
    // Create a new chat object with the updated data
    var updatedChat = chat
    updatedChat.lastMessage = firstMessage
    updatedChat.lastActivity = Date()
    
    // Trigger a refresh of the chat list
    Task { @MainActor in
        await loadChats()
    }
    
    return updatedChat
  }
}

enum ChatError: LocalizedError {
  case chatAlreadyExists
  case invalidUsers
  case userNotFound
  case userNotAuthenticated
  case invalidGroupTitle
  case networkError(Error)
  case invalidChat
  case invalidMessage
  case chatCreationFailed

  var errorDescription: String? {
    switch self {
    case .chatAlreadyExists:
      return "A chat with these users already exists"
    case .invalidUsers:
      return "Invalid users selected"
    case .userNotAuthenticated:
      return "User is not authenticated"
    case .invalidGroupTitle:
      return "Invalid group title"
    case .userNotFound:
      return "User not found"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .invalidChat:
      return "Invalid chat"
    case .invalidMessage:
      return "Invalid message: missing ID"
    case .chatCreationFailed:
      return "Failed to create chat"
    }
  }
}

extension CodingUserInfoKey {
    static let documentDataKey = CodingUserInfoKey(rawValue: "documentData")!
}

#Preview {
    MessagesView(viewModel: MessagesViewModel())
}
