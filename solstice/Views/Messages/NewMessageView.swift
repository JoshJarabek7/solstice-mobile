import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchViewModel = UserSearchViewModel()
    @StateObject private var messagesViewModel = MessagesViewModel()
    @State private var searchText = ""
    @State private var selectedUsers: Set<User> = []
    @State private var isGroup = false
    @State private var groupTitle = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedChat: Chat?
    @State private var navigateToChat: Chat?
    let videoToShare: Video?
    
    init(videoToShare: Video? = nil) {
        self.videoToShare = videoToShare
    }
    
    private var sortedSelectedUsers: [User] {
        Array(selectedUsers).sorted(by: { $0.username < $1.username })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchSection
                selectedUsersSection
                groupChatSection
                Divider()
                searchResultsSection
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatView(chat: chat)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                await searchViewModel.searchUsers(newValue)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchSection: some View {
        SearchBar(
            text: $searchText,
            placeholder: "Search users",
            onSubmit: {
                Task {
                    await searchViewModel.searchUsers(searchText)
                }
            }
        )
        .padding()
    }
    
    private var selectedUsersSection: some View {
        if !selectedUsers.isEmpty {
            AnyView(
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<sortedSelectedUsers.count, id: \.self) { index in
                            SelectedUserBubble(user: sortedSelectedUsers[index], onRemove: {
                                withAnimation(.easeInOut) {
                                    selectedUsers = selectedUsers.filter { $0.id != sortedSelectedUsers[index].id }
                                }
                            })
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            )
        } else {
            AnyView(EmptyView())
        }
    }
    
    private var groupChatSection: some View {
        Group {
            if selectedUsers.count > 1 {
                VStack(spacing: 16) {
                    Toggle("Create Group Chat", isOn: $isGroup)
                        .padding(.horizontal)
                    
                    if isGroup {
                        TextField("Group Title", text: $groupTitle)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical)
                .animation(.easeInOut, value: isGroup)
            }
        }
    }
    
    private var searchResultsSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchViewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if searchViewModel.error != nil {
                    Text("Error loading results")
                        .foregroundColor(.red)
                        .padding()
                } else if searchViewModel.searchResults.isEmpty && !searchText.isEmpty {
                    Text("No users found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(searchViewModel.searchResults) { user in
                        MessageUserRow(
                            user: user,
                            isSelected: selectedUsers.contains(user)
                        ) {
                            withAnimation {
                                if selectedUsers.contains(user) {
                                    selectedUsers.remove(user)
                                } else {
                                    selectedUsers.insert(user)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
                dismiss()
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Create") {
                createChat()
            }
            .disabled(
                selectedUsers.isEmpty
                || (isGroup && groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
    
    // MARK: - Functions
    
    @MainActor
    private func createChat() {
        Task {
            let isGroupChat = isGroup && selectedUsers.count > 1
            let title = isGroupChat ? groupTitle.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            if isGroupChat && title?.isEmpty == true {
                errorMessage = "Please enter a group title"
                showError = true
                return
            }
            
            let localSelectedUsers = Array(selectedUsers)
            let chat = await Task.detached {
                let chatRef = Firestore.firestore().collection("chats").document()
                return Chat(
                    id: chatRef.documentID,
                    participants: localSelectedUsers,
                    lastActivity: Date(),
                    isGroup: isGroupChat,
                    name: title,
                    unreadCounts: Dictionary(uniqueKeysWithValues: localSelectedUsers.compactMap { ($0.id!, 0) }),
                    isDatingChat: false,
                    ownerId: Auth.auth().currentUser?.uid,
                    lastMessage: nil as Message?,
                    deletedForUsers: [],
                    hiddenMessagesForUsers: [:],
                    typingUsers: [],
                    createdAt: Date(),
                    createdBy: Auth.auth().currentUser?.uid
                )
            }.value
            
            // If there's a video to share, create a message with the video
            if let video = videoToShare {
                let metadata = MessageMetadata(
                    videoId: video.id,
                    videoThumbnail: video.thumbnailURL,
                    videoCaption: video.caption,
                    videoCreator: Auth.auth().currentUser?.uid ?? ""
                )
                
                let message = Message(
                    id: UUID().uuidString,
                    senderId: Auth.auth().currentUser?.uid ?? "",
                    content: video.caption ?? "",
                    timestamp: Date(),
                    type: .video,
                    metadata: metadata,
                    reactions: [:],
                    replyTo: nil,
                    replyPreview: nil,
                    readBy: [],
                    deliveredTo: []
                )
                
                try await messagesViewModel.sendMessage(message, in: chat)
            }
            
            selectedChat = chat
            navigateToChat = chat
            dismiss()
        }
    }
}

// MARK: - Supporting Views

struct SelectedUserBubble: View {
    let user: User
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(user.username)
                .font(.subheadline)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
}

struct MessageUserRow: View {
    let user: User
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                userAvatar
                userInfo
                Spacer()
                selectionIndicator
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
    
    private var userAvatar: some View {
        Group {
            if let imageURL = user.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var userInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.username)
                .font(.headline)
            Text(user.fullName)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var selectionIndicator: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NewMessageView(
            videoToShare: nil
        )
    }
}