import FirebaseFirestore
import SwiftUI

extension Date {
  func timeAgo() -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: self, relativeTo: Date())
  }
}

enum MessageTab {
  case regular
  case groups

  var title: String {
    switch self {
    case .regular: return "Messages"
    case .groups: return "Groups"
    }
  }
}

@Observable
final class MessagesTimerState {
  var lastUpdate = Date()
  
  func update() {
    lastUpdate = Date()
  }
}

struct MessagesView: View {
  // IMPORTANT: We rely on the new Observations system (@Observable).
  // So instead of requiring ObservableObject & @ObservedObject / @StateObject,
  // we do this. SwiftUI will track changes in real time on iOS 17+.
  @Bindable var viewModel: MessagesViewModel

  @State private var showNewMessage = false
  @State private var searchText = ""
  @State private var selectedTab: MessageTab = .regular
  @State private var navigationPath = NavigationPath()
  @State private var selectedChat: Chat?
  @State private var timerState = MessagesTimerState()

  // No default init(...) because we must pass in a shared viewModel.
  init(viewModel: MessagesViewModel) {
    self.viewModel = viewModel
  }

  private var filteredChats: [Chat] {
    let chats: [Chat]
    switch selectedTab {
    case .regular:
      chats = viewModel.regularChats
    case .groups:
      chats = viewModel.groupChats
    }
    
    if searchText.isEmpty {
      return chats
    }
    
    return chats.filter { chat in
      chat.displayName.localizedCaseInsensitiveContains(searchText)
        || chat.lastMessage?.content.localizedCaseInsensitiveContains(searchText) == true
    }
  }
  
  var body: some View {
    NavigationStack(path: $navigationPath) {
      MessagesContentView(
        viewModel: viewModel,
        selectedTab: $selectedTab,
        searchText: $searchText,
        filteredChats: filteredChats,
        timerState: timerState
      )
      .navigationTitle("Messages")
      .navigationDestination(for: Chat.self) { chat in
        ChatView(chat: chat)
      }
      .toolbar {
        MessagesToolbar(showNewMessage: $showNewMessage)
      }
      .sheet(isPresented: $showNewMessage) {
        MessagesNewChatSheet(
          viewModel: viewModel,
          selectedChat: $selectedChat,
          showNewMessage: $showNewMessage,
          navigationPath: $navigationPath
        )
      }
    }
    .task {
      await viewModel.loadChats()
      
      // Setup periodic updates
      let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
        Task { @MainActor in
          timerState.update()
        }
      }
      timer.tolerance = 5
    }
  }
}

private struct MessagesToolbar: ToolbarContent {
  @Binding var showNewMessage: Bool
  
  var body: some ToolbarContent {
    ToolbarItem(placement: .navigationBarTrailing) {
      Button(action: { showNewMessage = true }) {
        Image(systemName: "square.and.pencil")
      }
    }
  }
}

private struct MessagesNewChatSheet: View {
  let viewModel: MessagesViewModel
  @Binding var selectedChat: Chat?
  @Binding var showNewMessage: Bool
  @Binding var navigationPath: NavigationPath
  
  var body: some View {
    NavigationStack {
      NewMessageView(
        messagesViewModel: viewModel
      )
    }
    .onChange(of: selectedChat) { _, newChat in
      if let chat = newChat {
        showNewMessage = false
        selectedChat = nil
        navigationPath.append(chat)
      }
    }
  }
}

private struct MessagesContentView: View {
  let viewModel: MessagesViewModel
  @Binding var selectedTab: MessageTab
  @Binding var searchText: String
  let filteredChats: [Chat]
  let timerState: MessagesTimerState
  
  var body: some View {
    VStack(spacing: 0) {
      // Custom tab picker
      Picker("Message Type", selection: $selectedTab) {
        Text("Messages").tag(MessageTab.regular)
        Text("Groups").tag(MessageTab.groups)
      }
      .pickerStyle(.segmented)
      .padding()

      // Search bar
      SearchBar(
        text: $searchText,
        placeholder: "Search messages",
        onSubmit: {}
      )
      .padding(.horizontal)

      // Chat list
      ChatListView(
        filteredChats: filteredChats,
        viewModel: viewModel,
        timerState: timerState
      )
    }
  }
}

private struct ChatListView: View {
  let filteredChats: [Chat]
  let viewModel: MessagesViewModel
  let timerState: MessagesTimerState
  
  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(filteredChats) { chat in
          NavigationLink(value: chat) {
            ChatListRow(chat: chat)
              .id("chat_\(chat.id ?? "")_\(chat.lastMessage?.id ?? "")_\(chat.lastMessage?.timestamp.timeIntervalSince1970 ?? 0)")
          }
          Divider()
            .padding(.leading, 76)
        }
      }
    }
    .refreshable {
      await viewModel.loadChats()
    }
  }
}

struct ChatListRow: View {
  let chat: Chat
  @Environment(\.colorScheme) var colorScheme
  @EnvironmentObject var authViewModel: AuthViewModel
  
  var body: some View {
    HStack(spacing: 12) {
      // Avatar
      if chat.isGroup {
        GroupChatAvatar(users: chat.participants)
      } else {
        UserAvatar(user: chat.participants.first!)
      }

      // Chat info
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(chat.displayName)
            .font(.headline)

          Spacer()

          if let lastMessage = chat.lastMessage {
            Text(lastMessage.timestamp.timeAgo())
              .font(.caption)
              .foregroundColor(.gray)
          }
        }

        HStack {
          if let lastMessage = chat.lastMessage {
            Text(lastMessage.content)
              .font(.subheadline)
              .foregroundColor(.gray)
              .lineLimit(1)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()

          let unreadCount = chat.unreadCount(for: authViewModel.currentUser?.id ?? "")
          if unreadCount > 0 {
            Text("\(unreadCount)")
              .font(.caption)
              .foregroundColor(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.blue)
              .clipShape(Capsule())
          }
        }
      }
    }
    .padding()
    .contentShape(Rectangle())
    .background(colorScheme == .dark ? Color.black : Color.white)
  }
}

struct GroupChatAvatar: View {
  let users: [User]

  var body: some View {
    ZStack {
      ForEach(users.prefix(4).indices, id: \.self) { index in
        if let url = users[index].profileImageURL {
          AsyncImage(url: URL(string: url)) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            Image(systemName: "person.circle.fill")
              .resizable()
          }
          .frame(width: 30, height: 30)
          .clipShape(Circle())
          .offset(
            x: CGFloat(index % 2) * 15,
            y: CGFloat(index / 2) * 15)
        }
      }
    }
    .frame(width: 60, height: 60)
  }
}

#Preview {
  MessagesView(viewModel: MessagesViewModel())
}