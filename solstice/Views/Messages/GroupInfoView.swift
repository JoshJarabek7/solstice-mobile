import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct GroupInfoView: View {
  let chat: Chat
  @StateObject private var viewModel: GroupInfoViewModel
  @State private var showAddMembers = false
  @Environment(\.dismiss) private var dismiss

  init(chat: Chat) {
    self.chat = chat
    _viewModel = StateObject(wrappedValue: GroupInfoViewModel(chat: chat))
  }

  var body: some View {
    List {
      Section("Group Name") {
        Text(chat.displayName)
          .font(.headline)
      }

      Section("Members (\(viewModel.members.count))") {
        ForEach(viewModel.members) { member in
          MemberRow(member: member, viewModel: viewModel)
        }
      }

      Button {
        showAddMembers = true
      } label: {
        Label("Add Members", systemImage: "person.badge.plus")
      }

      if !viewModel.events.isEmpty {
        Section("Chat History") {
          ForEach(viewModel.events) { event in
            Text(event.displayText)
              .font(.subheadline)
              .foregroundColor(.gray)
          }
        }
      }
    }
    .navigationTitle("Group Info")
    .sheet(isPresented: $showAddMembers) {
      AddMembersView(viewModel: viewModel)
    }
    .task {
      await viewModel.loadMembers()
      await viewModel.loadEvents()
    }
  }
}

struct MemberRow: View {
  let member: User
  let viewModel: GroupInfoViewModel

  var body: some View {
    HStack {
      UserAvatar(user: member)
        .frame(width: 40, height: 40)

      VStack(alignment: .leading) {
        Text(member.username)
          .font(.headline)
        Text(member.fullName)
          .font(.subheadline)
          .foregroundColor(.gray)
      }

      Spacer()

      if member.id != viewModel.currentUserId {
        Button(role: .destructive) {
          Task {
            await viewModel.removeMember(member)
          }
        } label: {
          Image(systemName: "person.fill.xmark")
            .foregroundColor(.red)
        }
      }
    }
  }
}

struct AddMembersView: View {
  @ObservedObject var viewModel: GroupInfoViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var selectedUsers: Set<User> = []

  var filteredSearchResults: [User] {
    viewModel.searchResults.filter { user in
      !viewModel.members.contains(where: { $0.id == user.id })
    }
  }

  var body: some View {
    NavigationStack {
      VStack {
        SearchBar(
          text: $searchText,
          placeholder: "Search users to add",
          onSubmit: {
            Task {
              await viewModel.searchUsers(query: searchText)
            }
          }
        )
        .padding()

        if !selectedUsers.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(Array(selectedUsers)) { user in
                VStack {
                  UserAvatar(user: user)
                    .frame(width: 60, height: 60)

                  Text(user.username)
                    .font(.caption)

                  Button {
                    selectedUsers.remove(user)
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .foregroundColor(.red)
                  }
                }
                .padding(8)
              }
            }
            .padding(.horizontal)
          }
          .padding(.vertical, 8)
        }

        List(filteredSearchResults) { user in
          HStack {
            UserAvatar(user: user)
              .frame(width: 40, height: 40)

            VStack(alignment: .leading) {
              Text(user.username)
                .font(.headline)
              Text(user.fullName)
                .font(.subheadline)
                .foregroundColor(.gray)
            }

            Spacer()

            if selectedUsers.contains(user) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            if selectedUsers.contains(user) {
              selectedUsers.remove(user)
            } else {
              selectedUsers.insert(user)
            }
          }
        }
      }
      .navigationTitle("Add Members")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Add") {
            Task {
              await viewModel.addMembers(Array(selectedUsers))
              dismiss()
            }
          }
          .disabled(selectedUsers.isEmpty)
        }
      }
      .onChange(of: searchText) { _, newValue in
        Task {
          await viewModel.searchUsers(query: newValue)
        }
      }
    }
  }
}

@MainActor
class GroupInfoViewModel: ObservableObject {
  @Published var members: [User] = []
  @Published var events: [ChatEvent] = []
  @Published var searchResults: [User] = []
  @Published var error: Error?

  private let chat: Chat
  private let db = Firestore.firestore()
  let currentUserId: String

  init(chat: Chat) {
    self.chat = chat
    self.currentUserId = Auth.auth().currentUser?.uid ?? ""
  }

  func loadMembers() async {
    members = chat.participants
  }

  func loadEvents() async {
    guard let chatId = chat.id else { return }

    do {
      let snapshot = try await db.collection("chats")
        .document(chatId)
        .collection("events")
        .order(by: "timestamp", descending: true)
        .getDocuments()

      events = snapshot.documents.compactMap { try? $0.data(as: ChatEvent.self) }
    } catch {
      print("Error loading events: \(error)")
      self.error = error
    }
  }

  func searchUsers(query: String) async {
    guard !query.isEmpty else {
      searchResults = []
      return
    }

    do {
      let snapshot = try await db.collection("users")
        .whereField("username", isGreaterThanOrEqualTo: query)
        .whereField("username", isLessThan: query + "z")
        .limit(to: 10)
        .getDocuments()

      searchResults = snapshot.documents.compactMap { try? $0.data(as: User.self) }
    } catch {
      print("Error searching users: \(error)")
      self.error = error
    }
  }

  func addMembers(_ users: [User]) async {
    guard let chatId = chat.id else { return }

    do {
      // Update participants array
      let participantData = users.map { user -> [String: Any] in
        [
          "id": user.id ?? "",
          "username": user.username,
          "email": user.email,
          "fullName": user.fullName,
          "profileImageURL": user.profileImageURL as Any,
          "gender": user.gender.rawValue,
        ]
      }

      try await db.collection("chats").document(chatId).updateData([
        "participants": FieldValue.arrayUnion(participantData)
      ])

      // Add events for each new member
      for user in users {
        let event = ChatEvent(
          type: .memberAdded,
          userId: user.id ?? "",
          performedBy: currentUserId,
          timestamp: Date()
        )

        try db.collection("chats")
          .document(chatId)
          .collection("events")
          .addDocument(from: event)
      }

      // Refresh members list
      members = chat.participants
      await loadEvents()
    } catch {
      print("Error adding members: \(error)")
      self.error = error
    }
  }

  func removeMember(_ user: User) async {
    guard let chatId = chat.id else { return }

    do {
      // Remove from participants array
      let memberData: [String: Any] = [
        "id": user.id ?? "",
        "username": user.username,
        "email": user.email,
        "fullName": user.fullName,
        "profileImageURL": user.profileImageURL as Any,
        "gender": user.gender.rawValue,
      ]

      try await db.collection("chats").document(chatId).updateData([
        "participants": FieldValue.arrayRemove([memberData])
      ])

      // Add removal event
      let event = ChatEvent(
        type: .memberRemoved,
        userId: user.id ?? "",
        performedBy: currentUserId,
        timestamp: Date()
      )

      try db.collection("chats")
        .document(chatId)
        .collection("events")
        .addDocument(from: event)

      // Refresh members list
      members = chat.participants
      await loadEvents()
    } catch {
      print("Error removing member: \(error)")
      self.error = error
    }
  }
}

#Preview {
  NavigationStack {
    GroupInfoView(
      chat: Chat(
        id: "test",
        participants: [
          User(
            username: "user1", email: "user1@test.com", fullName: "User One",
            gender: .other),
          User(
            username: "user2", email: "user2@test.com", fullName: "User Two",
            gender: .other),
        ],
        lastActivity: Date(),
        isGroup: true,
        name: "Test Group",
        unreadCounts: ["test": 0],
        isDatingChat: false,
        createdAt: Date(),
        createdBy: "test"
      )
    )
  }
}
