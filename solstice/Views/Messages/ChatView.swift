@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
import SwiftUI

struct ChatView: View {
  @State var chat: Chat
  @State private var viewModel: ChatViewModel
  @State private var messageText = ""
  @State private var selectedMessage: Message?
  @State private var showMessageOptions = false
  @State private var showReactionPicker = false
  @State private var showChatOptions = false
  @State private var replyingTo: Message?
  @State private var isSearching = false
  @State private var searchText = ""
  @State private var dotOffset: CGFloat = 0
  @FocusState private var isInputFocused: Bool
  @Environment(\.dismiss) private var dismiss
  private let commonReactions = ["❤️", "👍", "👎", "😂", "😮", "😢"]

  init(chat: Chat) {
    self._chat = State(initialValue: chat)
    _viewModel = State(initialValue: ChatViewModel(chat: chat))
  }

  var body: some View {
    Group {
      if isSearching {
        searchView
      } else {
        chatView
      }
    }
    .navigationTitle(chat.displayName(currentUserId: viewModel.currentUserId))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbarContent }
    .task {
      await viewModel.loadMessages()
    }
    .onDisappear {
      Task {
        await viewModel.updateTypingStatus(isTyping: false)
      }
    }
    .confirmationDialog(
      "Message Options", isPresented: $showMessageOptions, presenting: selectedMessage
    ) { message in
      Button("Reply") {
        replyingTo = message
        isInputFocused = true
      }
      Button("React") {
        showReactionPicker = true
      }
      Button("Hide Message") {
        Task {
          await viewModel.hideMessage(message)
        }
      }
      if message.senderId == viewModel.currentUserId {
        Button("Delete Message", role: .destructive) {
          Task {
            await viewModel.deleteMessage(message)
          }
        }
      }
    }
    .confirmationDialog(
      "Add Reaction", isPresented: $showReactionPicker, presenting: selectedMessage
    ) { message in
      ForEach(commonReactions, id: \.self) { emoji in
        Button(emoji) {
          Task {
            if message.hasReaction(emoji, by: viewModel.currentUserId) {
              await viewModel.removeReaction(emoji, from: message)
            } else {
              await viewModel.addReaction(emoji, to: message)
            }
          }
        }
      }
    }
    .confirmationDialog("Chat Options", isPresented: $showChatOptions) {
      Button("Clear Chat History") {
        Task {
          await viewModel.clearChatHistory()
        }
      }
      if chat.isDatingChat {
        Button("Unmatch", role: .destructive) {
          Task {
            await viewModel.unmatch()
            dismiss()
          }
        }
      } else if chat.isOwner(viewModel.currentUserId) {
        Button("Delete Chat", role: .destructive) {
          Task {
            await viewModel.deleteChat()
            dismiss()
          }
        }
      } else {
        Button("Delete Chat for Me", role: .destructive) {
          Task {
            await viewModel.deleteChatForMe()
            dismiss()
          }
        }
      }
    }
  }

  private var mainView: some View {
    VStack(spacing: 0) {
      if isSearching {
        searchView
      } else {
        chatView
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigationBarTrailing) {
      Button {
        isSearching.toggle()
        if !isSearching {
          searchText = ""
        }
      } label: {
        Image(systemName: isSearching ? "xmark" : "magnifyingglass")
      }
    }
    ToolbarItem(placement: .navigationBarTrailing) {
      Button {
        showChatOptions = true
      } label: {
        Image(systemName: "ellipsis")
      }
    }
    if chat.isGroup {
      ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink {
          GroupInfoView(chat: chat)
        } label: {
          Image(systemName: "info.circle")
        }
      }
    }
    if isSearching {
      ToolbarItem(placement: .navigationBarLeading) {
        SearchBar(
          text: $searchText,
          placeholder: "Search in conversation",
          onSubmit: {
            // Search is handled by filteredMessages computed property
          }
        )
      }
    }
  }

  private var searchView: some View {
    List(filteredMessages) { message in
      Button {
        isSearching = false
        searchText = ""
        if let messageId = message.id {
          Task {
            await viewModel.scrollToMessage(messageId)
          }
        }
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            if let sender = chat.participants.first(where: { $0.id == message.senderId }
            ) {
              Text(sender.username)
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            Spacer()
            Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
              .font(.caption)
              .foregroundColor(.gray)
          }
          Text(message.content)
            .foregroundColor(.primary)
            .lineLimit(2)
        }
      }
    }
  }

  private var chatView: some View {
    VStack(spacing: 0) {
      messagesScrollView
      messageInputSection
    }
  }

  private var searchResults: [Message] {
    guard !searchText.isEmpty else { return [] }
    let items = viewModel.messagesAndEvents
    let messages = items.compactMap { item -> Message? in
      if case .message(let message) = item {
        return message
      }
      return nil
    }
    return messages
  }

  private var filteredMessages: [Message] {
    let results = searchResults
    return results.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
  }

  private var messagesScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(viewModel.messagesAndEvents) { item in
            chatItemView(for: item)
          }
        }
        .padding()
      }
      .overlay(alignment: .bottom) {
        if !viewModel.typingUsers.isEmpty {
          typingIndicatorView
            .id("typingIndicator")
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 8)
        }
      }
      .onChange(of: viewModel.messagesAndEvents.map { $0.id }) { _, _ in
        if let lastId = viewModel.messagesAndEvents.last?.id {
          withAnimation {
            proxy.scrollTo(lastId, anchor: .bottom)
          }
        }
      }
      .onChange(of: viewModel.typingUsers) { _, _ in
        withAnimation {
          proxy.scrollTo("typingIndicator", anchor: .bottom)
        }
      }
    }
  }

  @ViewBuilder
  private func chatItemView(for item: ChatItem) -> some View {
    switch item {
    case .message(let message):
      if !viewModel.isMessageHidden(message) {
        MessageBubble(
          message: message,
          isFromCurrentUser: message.senderId == viewModel.currentUserId
        ) {
          selectedMessage = message
          showMessageOptions = true
        }
        .id(message.id)
      }
    case .event(let event):
      Text(event.displayText)
        .font(.caption)
        .foregroundColor(.gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .id(event.id)
    }
  }

  @ViewBuilder
  private var typingIndicatorView: some View {
    HStack {
      if viewModel.typingUsernames.count == 1 {
        Text("\(viewModel.typingUsernames[0]) is typing")
          .font(.caption)
          .foregroundColor(.gray)
      } else if viewModel.typingUsernames.count == 2 {
        Text("\(viewModel.typingUsernames[0]) and \(viewModel.typingUsernames[1]) are typing")
          .font(.caption)
          .foregroundColor(.gray)
      } else if viewModel.typingUsernames.count > 2 {
        Text(
          "\(viewModel.typingUsernames[0]), \(viewModel.typingUsernames[1]), and \(viewModel.typingUsernames.count - 2) others are typing"
        )
        .font(.caption)
        .foregroundColor(.gray)
      }
      HStack(spacing: 4) {
        ForEach(0..<3) { index in
          Circle()
            .fill(Color.gray)
            .frame(width: 4, height: 4)
            .offset(y: dotOffset)
            .animation(
              Animation.easeInOut(duration: 0.3)
                .repeatForever()
                .delay(0.2 * Double(index)),
              value: dotOffset
            )
        }
      }
      .onAppear {
        dotOffset = -5
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color(.systemGray6))
    .cornerRadius(20)
    .shadow(radius: 2)
  }

  private var messageInputSection: some View {
    VStack(spacing: 0) {
      Divider()
      if let replyingTo = replyingTo {
        HStack {
          Rectangle()
            .frame(width: 2)
            .foregroundColor(.gray)
          VStack(alignment: .leading, spacing: 2) {
            Text("Replying to")
              .font(.caption)
              .foregroundColor(.gray)
            Text(replyingTo.content)
              .font(.caption)
              .foregroundColor(.gray)
              .lineLimit(1)
          }
          Spacer()
          Button {
            self.replyingTo = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.gray)
          }
        }
        .padding(.horizontal)
        .padding(.top, 8)
      }
      HStack(spacing: 12) {
        TextField("Message", text: $messageText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .focused($isInputFocused)
          .lineLimit(1...5)
          .onChange(of: messageText) { _, newValue in
            // Only trigger typing status if actually typing
            if !newValue.isEmpty {
              Task {
                await viewModel.updateTypingStatus(isTyping: true)
              }
            } else {
              Task {
                await viewModel.updateTypingStatus(isTyping: false)
              }
            }
          }
          .onSubmit {
            Task {
              await viewModel.updateTypingStatus(isTyping: false)
            }
          }
        Button {
          Task {
            do {
              try await sendMessage(messageText, replyingTo: replyingTo)
            } catch {
              print("Error sending message: \(error)")
            }
          }
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
        }
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding()
    }
  }

  private func sendMessage(_ content: String, replyingTo: Message? = nil) async throws {
    // Create message with document ID
    let messageRef = Firestore.firestore().collection("chats").document(chat.id ?? "").collection(
      "messages"
    ).document()
    let message = Message(
      id: messageRef.documentID,
      senderId: viewModel.currentUserId,
      content: content,
      timestamp: Date(),
      type: .text,
      replyTo: replyingTo?.id,
      replyPreview: replyingTo.map {
        ReplyPreview(
          messageId: $0.id ?? "",
          content: $0.content,
          senderId: $0.senderId,
          type: $0.type
        )
      },
      deliveredTo: [viewModel.currentUserId]
    )

    // Check if chat exists in Firebase
    var chatExists = false
    if let chatId = chat.id {
      let doc = try await Firestore.firestore().collection("chats").document(chatId).getDocument()
      chatExists = doc.exists
    }

    if !chatExists {
      let messagesViewModel = MessagesViewModel()
      chat = try await messagesViewModel.createChatInFirebase(chat, firstMessage: message)
      // Update viewModel with new chat
      viewModel = ChatViewModel(chat: chat)
      await viewModel.loadMessages()

      // Refresh the messages list
      Task {
        await messagesViewModel.loadChats()
      }
    } else {
      // Chat exists, just add the message
      try await viewModel.addMessage(to: chat, message: message)
    }

    messageText = ""
    self.replyingTo = nil
    await viewModel.updateTypingStatus(isTyping: false)
  }
}

struct MessageBubble: View {
  let message: Message
  let isFromCurrentUser: Bool
  let onLongPress: () -> Void

  private let commonReactions = ["❤️", "👍", "👎", "😂", "😮", "😢"]

  var body: some View {
    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
      if let preview = message.replyPreview {
        ReplyPreviewView(preview: preview)
          .padding(.bottom, 4)
      }
      HStack {
        if isFromCurrentUser {
          Spacer()
        }
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
          contentView
            .padding(12)
            .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
            .foregroundColor(isFromCurrentUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
          if !message.reactions.isEmpty {
            ReactionsView(reactions: message.reactions)
          }
          HStack(spacing: 4) {
            Text(message.timestamp.timeAgo())
              .font(.caption2)
              .foregroundColor(.gray)
            if isFromCurrentUser {
              Image(systemName: message.readStatus.icon)
                .font(.caption2)
                .foregroundColor(message.readStatus.color)
            }
          }
        }
        if !isFromCurrentUser {
          Spacer()
        }
      }
    }
    .contentShape(Rectangle())
    .onLongPressGesture {
      onLongPress()
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch message.type {
    case .text:
      Text(message.content)
    case .image:
      if let url = message.metadata?.imageUrl {
        AsyncImage(url: URL(string: url)) { phase in
          switch phase {
          case .empty:
            ProgressView()
          case .success(let image):
            image.resizable().scaledToFit()
          case .failure:
            Text("Image failed to load")
          @unknown default:
            EmptyView()
          }
        }
        .frame(maxWidth: 200, maxHeight: 200)
      }
    case .video:
      VideoMessagePreview(metadata: message.metadata)
    case .sharedPost:
      SharedPostPreview(metadata: message.metadata)
    case .sharedProfile:
      SharedProfilePreview(metadata: message.metadata)
    }
  }
}

struct VideoMessagePreview: View {
  let metadata: MessageMetadata?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Video Creator Info
      if let creator = metadata?.videoCreator {
        HStack(spacing: 8) {
          Image(systemName: "person.circle.fill")
            .foregroundColor(.gray)
          Text("@\(creator)")
            .font(.caption)
            .foregroundColor(.gray)
        }
      }

      // Video Thumbnail with Play Button
      if let thumbnailURL = metadata?.videoThumbnail {
        ZStack {
          AsyncImage(url: URL(string: thumbnailURL)) { phase in
            switch phase {
            case .empty:
              Rectangle()
                .fill(Color.gray.opacity(0.2))
            case .success(let image):
              image
                .resizable()
                .scaledToFill()
            case .failure:
              Rectangle()
                .fill(Color.gray.opacity(0.2))
            @unknown default:
              EmptyView()
            }
          }
          .frame(height: 200)
          .clipShape(RoundedRectangle(cornerRadius: 12))

          // Play Button Overlay
          Image(systemName: "play.circle.fill")
            .font(.system(size: 44))
            .foregroundColor(.white)
            .shadow(radius: 2)
        }
      }

      // Video Caption
      if let caption = metadata?.videoCaption {
        Text(caption)
          .font(.caption)
          .lineLimit(2)
      }
    }
    .frame(width: 250)
  }
}

struct ReplyPreviewView: View {
  let preview: ReplyPreview

  var body: some View {
    HStack {
      Rectangle()
        .frame(width: 2)
        .foregroundColor(.gray)
      VStack(alignment: .leading, spacing: 2) {
        Text(preview.senderId)
          .font(.caption)
          .foregroundColor(.gray)
        Text(preview.truncatedContent)
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background(Color(.systemGray6))
    .cornerRadius(8)
  }
}

struct ReactionsView: View {
  let reactions: [String: [String]]
  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(reactions.keys), id: \.self) { emoji in
        if let count = reactions[emoji]?.count, count > 0 {
          HStack(spacing: 2) {
            Text(emoji)
            if count > 2 {
              Text("\(count)")
                .font(.caption2)
            }
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color(.systemGray6))
          .cornerRadius(12)
        }
      }
    }
  }
}

struct SharedPostPreview: View {
  let metadata: MessageMetadata?
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let creator = metadata?.postCreator {
        Text("@\(creator)")
          .font(.caption)
          .foregroundColor(.gray)
      }
      if let thumbnailURL = metadata?.postThumbnail {
        AsyncImage(url: URL(string: thumbnailURL)) { phase in
          switch phase {
          case .empty:
            Color.gray.opacity(0.2)
          case .success(let image):
            image.resizable().scaledToFit()
          case .failure:
            Color.gray.opacity(0.2)
          @unknown default:
            EmptyView()
          }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      if let caption = metadata?.truncatedPostCaption {
        Text(caption)
          .font(.caption)
          .lineLimit(2)
      }
    }
    .frame(width: 200)
    .padding(8)
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

struct SharedProfilePreview: View {
  let metadata: MessageMetadata?
  var body: some View {
    HStack(spacing: 12) {
      if let imageURL = metadata?.profileImage {
        AsyncImage(url: URL(string: imageURL)) { phase in
          switch phase {
          case .empty:
            Color.gray.opacity(0.2)
          case .success(let image):
            image.resizable().scaledToFill()
          case .failure:
            Color.gray.opacity(0.2)
          @unknown default:
            EmptyView()
          }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
      }
      VStack(alignment: .leading, spacing: 4) {
        if let username = metadata?.profileUsername {
          Text("@\(username)")
            .font(.headline)
        }
        if let fullName = metadata?.profileFullName {
          Text(fullName)
            .font(.subheadline)
        }
        if let bio = metadata?.truncatedProfileBio {
          Text(bio)
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(2)
        }
      }
    }
    .frame(width: 250)
    .padding(8)
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

@Observable
class ChatViewModel {
  var messagesAndEvents: [ChatItem] = []
  var error: Error?
  var typingUsers: [String] = []
  private let typingDebounceTime: TimeInterval = 1.5

  private let chat: Chat
  private let db = Firestore.firestore()
  private var listener: ListenerRegistration?
  private var typingListener: ListenerRegistration?
  private var typingTimer: Timer?
  let currentUserId: String
  private var hiddenMessageIds: Set<String> = []

  var typingUsernames: [String] {
    chat.participants
      .filter { user in
        typingUsers.contains(user.id ?? "") && user.id != currentUserId
      }
      .map { $0.username }
  }

  init(chat: Chat) {
    self.chat = chat
    self.currentUserId = Auth.auth().currentUser?.uid ?? ""
    self.hiddenMessageIds = Set(chat.hiddenMessageIds(for: currentUserId))
  }

  func isMessageHidden(_ message: Message) -> Bool {
    hiddenMessageIds.contains(message.id ?? "")
  }

  func hideMessage(_ message: Message) async {
    guard let chatId = chat.id, let messageId = message.id else { return }
    do {
      try await db.collection("chats").document(chatId).updateData([
        "hiddenMessagesForUsers.\(currentUserId)": FieldValue.arrayUnion([messageId])
      ])
      hiddenMessageIds.insert(messageId)
    } catch {
      print("Error hiding message: \(error)")
      self.error = error
    }
  }

  func deleteMessage(_ message: Message) async {
    guard let chatId = chat.id,
      let messageId = message.id,
      message.senderId == currentUserId
    else { return }
    do {
      try await db.collection("chats")
        .document(chatId)
        .collection("messages")
        .document(messageId)
        .delete()
    } catch {
      print("Error deleting message: \(error)")
      self.error = error
    }
  }

  func clearChatHistory() async {
    guard let chatId = chat.id else { return }
    do {
      let messages = messagesAndEvents.compactMap { item -> String? in
        if case .message(let message) = item {
          return message.id
        }
        return nil
      }
      try await db.collection("chats").document(chatId).updateData([
        "hiddenMessagesForUsers.\(currentUserId)": messages
      ])
      hiddenMessageIds = Set(messages)
    } catch {
      print("Error clearing chat history: \(error)")
      self.error = error
    }
  }

  func unmatch() async {
    guard let chatId = chat.id, chat.isDatingChat else { return }
    do {
      try await deleteEntireChat(chatId)
      for participant in chat.participants {
        if let userId = participant.id {
          try await db.collection("users").document(userId).updateData([
            "matches": FieldValue.arrayRemove([chatId])
          ])
        }
      }
    } catch {
      print("Error unmatching: \(error)")
      self.error = error
    }
  }

  func deleteChat() async {
    guard let chatId = chat.id, chat.isOwner(currentUserId) else { return }
    do {
      try await deleteEntireChat(chatId)
    } catch {
      print("Error deleting chat: \(error)")
      self.error = error
    }
  }

  func deleteChatForMe() async {
    guard let chatId = chat.id else { return }
    do {
      try await db.collection("chats").document(chatId).updateData([
        "deletedForUsers": FieldValue.arrayUnion([currentUserId])
      ])
    } catch {
      print("Error deleting chat for user: \(error)")
      self.error = error
    }
  }

  private func deleteEntireChat(_ chatId: String) async throws {
    let messagesSnapshot = try await db.collection("chats")
      .document(chatId)
      .collection("messages")
      .getDocuments()
    for doc in messagesSnapshot.documents {
      try await doc.reference.delete()
    }
    let eventsSnapshot = try await db.collection("chats")
      .document(chatId)
      .collection("events")
      .getDocuments()
    for doc in eventsSnapshot.documents {
      try await doc.reference.delete()
    }
    try await db.collection("chats").document(chatId).delete()
  }

  func loadMessages() async {
    guard let chatId = chat.id else {
      print("[ERROR] Invalid chat ID")
      return
    }

    // Clean up existing listeners
    listener?.remove()
    typingListener?.remove()

    // Set up typing listener
    typingListener = db.collection("chats").document(chatId)
      .addSnapshotListener { [weak self] snapshot, error in
        guard let self = self,
          let data = snapshot?.data(),
          let typingUsers = data["typingUsers"] as? [String]
        else {
          if let error = error {
            print("[ERROR] Typing listener error: \(error)")
          }
          return
        }
        self.typingUsers = typingUsers
      }

    // Set up messages listener with proper error handling
    let messagesQuery = db.collection("chats")
      .document(chatId)
      .collection("messages")
      .order(by: "timestamp", descending: false)

    let eventsQuery = db.collection("chats")
      .document(chatId)
      .collection("events")
      .order(by: "timestamp", descending: false)

    listener = messagesQuery.addSnapshotListener { [weak self] messageSnapshot, error in
      guard let self = self else { return }

      if let error = error {
        print("[ERROR] Failed to load messages: \(error)")
        self.error = error
        return
      }

      Task {
        do {
          // Process messages with improved error handling
          let messages =
            messageSnapshot?.documents.compactMap { document -> Message? in
              do {
                let data = document.data()
                print("[DEBUG] Processing message document: \(data)")

                let decoder = Firestore.Decoder()
                decoder.userInfo[.documentDataKey] = data

                let message = try document.data(as: Message.self, decoder: decoder)
                print(
                  "[DEBUG] Successfully decoded message: \(message.id ?? "unknown") - \(message.content)"
                )
                return message
              } catch {
                print("[ERROR] Failed to decode message: \(error)")
                return nil
              }
            } ?? []

          print("[DEBUG] Successfully decoded \(messages.count) messages")

          // Process events
          let eventSnapshot = try await eventsQuery.getDocuments()
          let events = eventSnapshot.documents.compactMap { document -> ChatEvent? in
            do {
              let data = document.data()
              print("[DEBUG] Processing event document: \(data)")

              let decoder = Firestore.Decoder()
              decoder.userInfo[.documentDataKey] = data

              let event = try document.data(as: ChatEvent.self, decoder: decoder)
              print("[DEBUG] Successfully decoded event: \(event.id ?? "unknown")")
              return event
            } catch {
              print("[ERROR] Failed to decode event: \(error)")
              return nil
            }
          }

          print("[DEBUG] Found \(events.count) chat events")

          // Combine and sort items
          var items: [ChatItem] = []
          items += messages.map { ChatItem.message($0) }
          items += events.map { ChatItem.event($0) }

          items.sort { item1, item2 in
            switch (item1, item2) {
            case (.message(let message1), .message(let message2)):
              return message1.timestamp < message2.timestamp
            case (.event(let event1), .event(let event2)):
              return event1.timestamp < event2.timestamp
            case (.message(let message), .event(let event)):
              return message.timestamp < event.timestamp
            case (.event(let event), .message(let message)):
              return event.timestamp < message.timestamp
            }
          }

          print("[DEBUG] Total chat items after sorting: \(items.count)")

          // Update UI state
          await MainActor.run {
            self.messagesAndEvents = items
          }

        } catch {
          print("[ERROR] Error processing messages and events: \(error)")
          self.error = error
        }
      }
    }

    // Handle read status and unread count
    do {
      let chatDoc = try await db.collection("chats").document(chatId).getDocument()
      if chatDoc.exists {
        Task {
          do {
            // Get unread messages from the last 30 days
            let thirtyDaysAgo =
              Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let unreadMessages = try await db.collection("chats")
              .document(chatId)
              .collection("messages")
              .whereField("timestamp", isGreaterThan: Timestamp(date: thirtyDaysAgo))
              .getDocuments()

            // Batch update for marking messages as read
            let batch = db.batch()
            var hasUnreadMessages = false

            for doc in unreadMessages.documents {
              let data = doc.data()
              if let senderId = data["senderId"] as? String,
                senderId != currentUserId,
                let readBy = data["readBy"] as? [String],
                !readBy.contains(currentUserId)
              {
                hasUnreadMessages = true
                batch.updateData(
                  [
                    "readBy": FieldValue.arrayUnion([currentUserId])
                  ], forDocument: doc.reference)
              }
            }

            if hasUnreadMessages {
              // Reset unread count for current user
              batch.updateData(
                [
                  "unreadCounts.\(currentUserId)": 0
                ], forDocument: db.collection("chats").document(chatId))

              try await batch.commit()
            }
          } catch {
            print("[ERROR] Failed to update read status: \(error)")
          }
        }
      } else {
        print("[ERROR] Chat document not found")
      }
    } catch {
      print("[ERROR] Failed to check chat existence: \(error)")
    }
  }

  private func markMessagesAsDelivered() async {
    guard let chatId = chat.id else { return }
    do {
      let snapshot = try await db.collection("chats")
        .document(chatId)
        .collection("messages")
        .whereField("deliveredTo", arrayContains: currentUserId)
        .getDocuments()
      for doc in snapshot.documents {
        try await doc.reference.updateData([
          "deliveredTo": FieldValue.arrayUnion([currentUserId])
        ])
      }
    } catch {
      print("Error marking messages as delivered: \(error)")
    }
  }

  private func markMessageAsRead(_ messageId: String) async {
    guard let chatId = chat.id else { return }
    do {
      try await db.collection("chats")
        .document(chatId)
        .collection("messages")
        .document(messageId)
        .updateData([
          "readBy": FieldValue.arrayUnion([currentUserId])
        ])
    } catch {
      print("Error marking message as read: \(error)")
    }
  }

  func addReaction(_ emoji: String, to message: Message) async {
    guard let chatId = chat.id, let messageId = message.id else { return }
    do {
      try await db.collection("chats")
        .document(chatId)
        .collection("messages")
        .document(messageId)
        .updateData([
          "reactions.\(emoji)": FieldValue.arrayUnion([currentUserId])
        ])
    } catch {
      print("Error adding reaction: \(error)")
      self.error = error
    }
  }

  func removeReaction(_ emoji: String, from message: Message) async {
    guard let chatId = chat.id, let messageId = message.id else { return }
    do {
      try await db.collection("chats")
        .document(chatId)
        .collection("messages")
        .document(messageId)
        .updateData([
          "reactions.\(emoji)": FieldValue.arrayRemove([currentUserId])
        ])
    } catch {
      print("Error removing reaction: \(error)")
      self.error = error
    }
  }

  private func cancelTypingTimer() {
    if let timer = typingTimer {
      DispatchQueue.main.async {
        timer.invalidate()
      }
      typingTimer = nil
    }
  }

  private func startTypingTimer() {
    cancelTypingTimer()
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.typingTimer = Timer.scheduledTimer(
        withTimeInterval: self.typingDebounceTime, repeats: false
      ) { [weak self] _ in
        Task { [weak self] in
          await self?.updateTypingStatus(isTyping: false)
        }
      }
    }
  }

  func updateTypingStatus(isTyping: Bool) async {
    guard let chatId = chat.id else { return }

    // Always cancel the existing timer
    cancelTypingTimer()

    do {
      // First check if the chat document exists
      let chatDoc = try await db.collection("chats").document(chatId).getDocument()
      guard chatDoc.exists else { return }

      if isTyping {
        try await db.collection("chats").document(chatId).updateData([
          "typingUsers": FieldValue.arrayUnion([currentUserId])
        ])
        startTypingTimer()
      } else {
        try await db.collection("chats").document(chatId).updateData([
          "typingUsers": FieldValue.arrayRemove([currentUserId])
        ])
      }
    } catch {
      print("Error updating typing status: \(error)")
    }
  }

  func scrollToMessage(_ messageId: String) async {
    // objectWillChange.send() is handled automatically by the @Observable macro
  }

  deinit {
    listener?.remove()
    typingListener?.remove()
    cancelTypingTimer()
  }

  func addMessage(to chat: Chat, message: Message) async throws {
    guard let chatId = chat.id else { throw ChatError.invalidChat }
    guard let messageId = message.id else { throw ChatError.invalidMessage }

    // Create message document with the provided ID
    let messageRef = db.collection("chats")
      .document(chatId)
      .collection("messages")
      .document(messageId)

    let messageData: [String: Any] = [
      "id": messageId,
      "content": message.content,
      "senderId": message.senderId,
      "timestamp": Timestamp(date: message.timestamp),
      "type": message.type.rawValue,
      "readBy": [message.senderId],
      "deliveredTo": [message.senderId],
      "reactions": [:],
      "metadata": message.metadata?.asDictionary() ?? NSNull(),
      "replyTo": message.replyTo as Any,
      "replyPreview": message.replyPreview?.asDictionary() as Any,
    ]

    // Batch write to ensure atomicity
    let batch = db.batch()

    // Add message
    batch.setData(messageData, forDocument: messageRef)

    // Update chat document
    let chatRef = db.collection("chats").document(chatId)
    var chatUpdateData: [String: Any] = [
      "lastMessage": messageData,
      "lastActivity": Timestamp(date: Date()),
      "unreadCounts.\(currentUserId)": 0,
    ]

    // Update unread counts for other participants
    let otherParticipantIds = chat.participants
      .compactMap { $0.id }
      .filter { $0 != currentUserId }

    for participantId in otherParticipantIds {
      chatUpdateData["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
    }

    batch.updateData(chatUpdateData, forDocument: chatRef)

    // Commit the batch
    try await batch.commit()
  }
}

extension ChatViewModel: @unchecked Sendable {}

enum ChatItem: Identifiable {
  case message(Message)
  case event(ChatEvent)

  var id: String {
    switch self {
    case .message(let message):
      return message.id ?? UUID().uuidString
    case .event(let event):
      return event.id ?? UUID().uuidString
    }
  }
}

extension ReplyPreview {
  func asDictionary() -> [String: Any] {
    [
      "messageId": messageId,
      "content": content,
      "senderId": senderId,
      "type": type.rawValue,
    ]
  }
}

struct ChatView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      ChatView(
        chat: Chat(
          id: "test",
          participants: [
            User(
              username: "user1",
              email: "user1@test.com",
              fullName: "User One",
              gender: .other
            ),
            User(
              username: "user2",
              email: "user2@test.com",
              fullName: "User Two",
              gender: .other
            ),
          ],
          lastActivity: Date(),
          isGroup: true,
          name: "Test Group",
          unreadCounts: [:],
          isDatingChat: false
        )
      )
    }
  }
}
