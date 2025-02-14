@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import SwiftUI

enum FollowListType {
  case followers
  case following
}

struct FollowListView: View {
  let userId: String
  let listType: FollowListType
  @StateObject private var viewModel = FollowListViewModel()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Group {
      if viewModel.isLoading {
        ProgressView()
      } else if !viewModel.hasAccess {
        VStack(spacing: 16) {
          Image(systemName: "lock.fill")
            .font(.system(size: 50))
            .foregroundColor(.gray)
          Text("This profile is private")
            .font(.headline)
          Text(
            "Follow this user to see their \(listType == .followers ? "followers" : "following")"
          )
          .foregroundColor(.gray)
        }
      } else if viewModel.users.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "person.2.slash.fill")
            .font(.system(size: 50))
            .foregroundColor(.gray)
          Text("\(listType == .followers ? "No followers yet" : "Not following anyone")")
            .font(.headline)
        }
      } else {
        List(viewModel.users) { user in
          NavigationLink {
            ProfileViewContainer(userId: user.id)
          } label: {
            HStack(spacing: 12) {
              // Profile Image
              if let imageURL = user.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                  image
                    .resizable()
                    .scaledToFill()
                } placeholder: {
                  Image(systemName: "person.circle.fill")
                    .resizable()
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
              } else {
                Image(systemName: "person.circle.fill")
                  .resizable()
                  .frame(width: 40, height: 40)
                  .foregroundColor(.gray)
              }

              // User Info
              VStack(alignment: .leading, spacing: 4) {
                Text(user.username)
                  .font(.headline)
                Text(user.fullName)
                  .font(.subheadline)
                  .foregroundColor(.gray)
              }

              Spacer()
            }
          }
        }
      }
    }
    .navigationTitle(listType == .followers ? "Followers" : "Following")
    .task {
      await viewModel.loadUsers(userId: userId, listType: listType)
    }
    .refreshable {
      await viewModel.loadUsers(userId: userId, listType: listType)
    }
  }
}

@MainActor
final class FollowListViewModel: ObservableObject {
  @Published private(set) var users: [User] = []
  @Published private(set) var isLoading = false
  @Published private(set) var hasAccess = false
  private let db = Firestore.firestore()

  func loadUsers(userId: String, listType: FollowListType) async {
    isLoading = true
    defer { isLoading = false }

    do {
      // First check if we have access to this profile
      let userDoc = try await db.collection("users").document(userId).getDocument()
      guard let userData = userDoc.data() else { return }

      let isPrivate = userData["isPrivate"] as? Bool ?? false
      let currentUserId = Auth.auth().currentUser?.uid

      // Check access
      let isFollowingUser =
        if let currentUserId = currentUserId {
          await isFollowing(currentUserId: currentUserId, targetUserId: userId)
        } else {
          false
        }

      hasAccess =
        !isPrivate  // Public profile
        || userId == currentUserId  // Own profile
        || (isPrivate && isFollowingUser)  // Private but following

      guard hasAccess else { return }

      // Fetch the appropriate list
      let collection = listType == .followers ? "followers" : "following"
      let querySnapshot = try await db.collection("users")
        .document(userId)
        .collection(collection)
        .getDocuments()

      // Get user IDs
      let userIds = querySnapshot.documents.compactMap { doc -> String? in
        listType == .followers
          ? doc.data()["followerId"] as? String : doc.data()["followedId"] as? String
      }

      // Create a sendable user data type
      struct UserData: Sendable {
        let id: String
        let username: String
        let fullName: String
        let profileImageURL: String?

        init?(id: String, data: [String: Any]) {
          guard let username = data["username"] as? String,
            let fullName = data["fullName"] as? String
          else {
            return nil
          }

          self.id = id
          self.username = username
          self.fullName = fullName
          self.profileImageURL = data["profileImageURL"] as? String
        }
      }

      // Fetch user documents
      let userDocs = try await withThrowingTaskGroup(of: UserData?.self) { group in
        for id in userIds {
          group.addTask {
            let doc = try await self.db.collection("users").document(id).getDocument()
            guard let data = doc.data() else { return nil }
            return UserData(id: id, data: data)
          }
        }

        var users: [UserData] = []
        for try await result in group {
          if let result = result {
            users.append(result)
          }
        }
        return users
      }

      // Convert UserData to User objects
      self.users = userDocs.map { userData in
        var user = User(
          username: userData.username,
          email: "",  // Not needed for display
          fullName: userData.fullName,
          profileImageURL: userData.profileImageURL,
          gender: .other  // Not needed for display
        )
        user.id = userData.id
        return user
      }

    } catch {
      print("[ERROR] Failed to load \(listType): \(error)")
      hasAccess = false
      users = []
    }
  }

  private func isFollowing(currentUserId: String, targetUserId: String) async -> Bool {
    do {
      let doc = try await db.collection("users")
        .document(currentUserId)
        .collection("following")
        .document(targetUserId)
        .getDocument()

      return doc.exists
    } catch {
      return false
    }
  }
}

#Preview {
  NavigationStack {
    FollowListView(userId: "preview_user_id", listType: .followers)
  }
}
