import FirebaseAuth
import FirebaseFirestore
import Photos
import SwiftUI

struct ShareSheet: View {
  let video: Video
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ShareSheetViewModel()
  @State private var searchText = ""
  @State private var isDownloading = false

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Search bar
        SearchBar(
          text: $searchText,
          placeholder: "Search users to share with",
          onSubmit: {
            Task {
              await viewModel.searchUsers(query: searchText)
            }
          }
        )
        .padding()

        // Recent chats and search results
        ScrollView {
          LazyVStack(spacing: 0) {
            if searchText.isEmpty {
              // Recent chats
              if !viewModel.recentChats.isEmpty {
                Section(header: SectionHeader(title: "Recent")) {
                  ForEach(viewModel.recentChats) { chat in
                    ChatRow(chat: chat) {
                      Task {
                        await viewModel.shareToChat(
                          video: video, chat: chat)
                        dismiss()
                      }
                    }
                  }
                }
              }

              // Download button
              ShareOptionRow(
                icon: "arrow.down.circle.fill",
                title: isDownloading ? "Downloading..." : "Download Video",
                isSystemImage: true
              ) {
                Task {
                  isDownloading = true
                  await viewModel.downloadVideo(video)
                  isDownloading = false
                  dismiss()
                }
              }
              .disabled(isDownloading)
              
              if isDownloading {
                ProgressView()
                  .padding()
              }
            } else {
              // Search results
              ForEach(viewModel.searchResults) { user in
                UserRow(user: user) {
                  Task {
                    await viewModel.createChatAndShare(with: user, video: video)
                    dismiss()
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle("Share")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
    .onChange(of: searchText) { _, newValue in
      Task {
        await viewModel.searchUsers(query: newValue)
      }
    }
  }
}

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.subheadline)
      .foregroundColor(.gray)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(.systemGroupedBackground))
  }
}

struct ChatRow: View {
  let chat: Chat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if chat.isGroup {
          GroupChatAvatar(users: chat.participants)
        } else {
          UserAvatar(user: chat.participants.first!)
        }

        VStack(alignment: .leading, spacing: 4) {
          if let name = chat.name {
            Text(name)
              .font(.headline)
          } else {
            Text("Chat")
              .font(.headline)
          }
          Text(
            chat.participants.map { $0.username }.joined(separator: ", ")
          )
          .font(.subheadline)
          .foregroundColor(.gray)
        }

        Spacer()
      }
      .padding()
    }
    .buttonStyle(.plain)
  }
}

struct UserRow: View {
  let user: User
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        UserAvatar(user: user)

        VStack(alignment: .leading, spacing: 4) {
          Text(user.username)
            .font(.headline)
          Text(user.fullName)
            .font(.subheadline)
            .foregroundColor(.gray)
        }

        Spacer()
      }
      .padding()
    }
    .buttonStyle(.plain)
  }
}

@MainActor
class ShareSheetViewModel: ObservableObject {
  @Published var recentChats: [Chat] = []
  @Published var searchResults: [User] = []

  private let db = Firestore.firestore()
  private let currentUserId: String

  init() {
    self.currentUserId = Auth.auth().currentUser?.uid ?? ""
    Task {
      await loadRecentChats()
    }
  }

  private func loadRecentChats() async {
    do {
      let snapshot = try await db.collection("chats")
        .whereField("participants", arrayContains: currentUserId)
        .order(by: "lastActivity", descending: true)
        .limit(to: 10)
        .getDocuments()

      let chats = snapshot.documents.compactMap { try? $0.data(as: Chat.self) }
      await MainActor.run {
        self.recentChats = chats
      }
    } catch {
      print("Error loading recent chats: \(error)")
    }
  }

  func searchUsers(query: String) async {
    guard !query.isEmpty else {
      searchResults = []
      return
    }

    do {
      // First, search following
      let followingSnapshot = try await db.collection("users")
        .whereField("followers", arrayContains: currentUserId)
        .whereField("username", isGreaterThanOrEqualTo: query)
        .whereField("username", isLessThan: query + "z")
        .limit(to: 5)
        .getDocuments()

      // Then, search followers
      let followersSnapshot = try await db.collection("users")
        .whereField("following", arrayContains: currentUserId)
        .whereField("username", isGreaterThanOrEqualTo: query)
        .whereField("username", isLessThan: query + "z")
        .limit(to: 5)
        .getDocuments()

      // Finally, search all users
      let allUsersSnapshot = try await db.collection("users")
        .whereField("username", isGreaterThanOrEqualTo: query)
        .whereField("username", isLessThan: query + "z")
        .limit(to: 5)
        .getDocuments()

      let results =
        followingSnapshot.documents + followersSnapshot.documents
        + allUsersSnapshot.documents
      let users = results.compactMap { try? $0.data(as: User.self) }

      // Remove duplicates and current user
      let filteredUsers = Array(Set(users)).filter { $0.id != currentUserId }

      await MainActor.run {
        self.searchResults = filteredUsers
      }
    } catch {
      print("Error searching users: \(error)")
    }
  }

  func shareToChat(video: Video, chat: Chat) async {
    guard let chatId = chat.id else { return }

    do {
      // Create message
      let message = Message(
        senderId: currentUserId,
        content: "Shared a video",
        timestamp: Date(),
        type: .video,
        metadata: MessageMetadata(
          videoId: video.id ?? "",
          videoThumbnail: video.thumbnailURL ?? "",
          videoCaption: video.caption
        )
      )

      // Add message to chat
      try db.collection("chats").document(chatId)
        .collection("messages").addDocument(from: message)

      // Update chat's last activity
      try await db.collection("chats").document(chatId).updateData([
        "lastMessage": message,
        "lastActivity": Timestamp(date: Date()),
      ])

      // Increment share count
      if let videoId = video.id {
        try await db.collection("videos").document(videoId).updateData([
          "shares": FieldValue.increment(Int64(1))
        ])
      }
    } catch {
      print("Error sharing to chat: \(error)")
    }
  }

  func createChatAndShare(with user: User, video: Video) async {
    do {
      // Check if chat already exists
      let existingChat = try await findExistingChat(with: user.id ?? "")

      if let existingChat = existingChat {
        await shareToChat(video: video, chat: existingChat)
        return
      }

      // Create new chat
      let newChat = Chat(
        id: nil,
        participants: [user],
        lastActivity: Date(),
        isGroup: false,
        name: nil,
        unreadCounts: [user.id ?? "": 0, currentUserId: 0],
        isDatingChat: false,
        ownerId: nil,
        lastMessage: nil,
        deletedForUsers: [],
        hiddenMessagesForUsers: [:],
        typingUsers: [],
        createdAt: Date(),
        createdBy: currentUserId
      )

      let chatRef = try db.collection("chats").addDocument(from: newChat)

      // Create initial message
      let message = Message(
        senderId: currentUserId,
        content: "Shared a video",
        timestamp: Date(),
        type: .video,
        metadata: MessageMetadata(
          videoId: video.id ?? "",
          videoThumbnail: video.thumbnailURL ?? "",
          videoCaption: video.caption
        )
      )

      try chatRef.collection("messages").addDocument(from: message)

      // Update chat with last message
      try await chatRef.updateData([
        "lastMessage": message,
        "lastActivity": Timestamp(date: Date()),
      ])

      // Increment share count
      if let videoId = video.id {
        try await db.collection("videos").document(videoId).updateData([
          "shares": FieldValue.increment(Int64(1))
        ])
      }
    } catch {
      print("Error creating chat and sharing: \(error)")
    }
  }

  private func findExistingChat(with userId: String) async throws -> Chat? {
    let snapshot = try await db.collection("chats")
      .whereField("participants", arrayContains: currentUserId)
      .whereField("isGroup", isEqualTo: false)
      .getDocuments()

    return snapshot.documents
      .compactMap { try? $0.data(as: Chat.self) }
      .first { chat in
        chat.participants.contains { $0.id == userId }
      }
  }

  func downloadVideo(_ video: Video) async {
    guard let url = URL(string: video.videoURL) else { return }

    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      try await PhotosManager.saveVideoToPhotos(data)
    } catch {
      print("Error downloading video: \(error)")
    }
  }
}

// Helper for saving to photos
enum PhotosManager {
  static func saveVideoToPhotos(_ videoData: Data) async throws {
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .photo, data: videoData, options: nil)
    }
  }
}

#Preview {
  ShareSheet(
    video: Video(
      id: "test",
      creatorId: "creator",
      caption: "Test video",
      videoURL: "https://example.com/video.mp4",
      thumbnailURL: nil,
      likes: 0,
      comments: 0,
      shares: 0,
      createdAt: Date(),
      duration: 120,
      hashtags: ["test"],
      viewCount: 0,
      completionRate: 0,
      engagementScore: 0,
      lastPlaybackPosition: nil
    )
  )
}
