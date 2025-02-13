import FirebaseAuth
import FirebaseCore
import SwiftUI

struct ContentView: View {
  @StateObject private var authViewModel = AuthViewModel()
  @State private var userViewModel: UserViewModel?

  // Store MessagesViewModel using @State, because @Observable ≠ ObservableObject.
  // This ensures the same instance persists while ContentView lives.
  @State private var messagesViewModel = MessagesViewModel()

  var body: some View {
    Group {
      if authViewModel.userSession == nil {
        AuthView()
          .environmentObject(authViewModel)
      } else {
        // Pass messagesViewModel into MainTabView so it can be shared by the entire app.
        MainTabView(messagesViewModel: messagesViewModel)
          .environmentObject(authViewModel)
          .environment(userViewModel ?? UserViewModel())
      }
    }
  }
}

struct MainTabView: View {
  @EnvironmentObject var authViewModel: AuthViewModel
  @Environment(UserViewModel.self) var userViewModel

  // We accept the existing MessagesViewModel from ContentView,
  // so SwiftUI always uses the same instance (i.e. no “Build Failed”).
  let messagesViewModel: MessagesViewModel

  @State private var selectedTab = 0

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        FeedView()
      }
      .tabItem {
        Image(systemName: "play.square")
        Text("Feed")
      }
      .tag(0)

      NavigationStack {
        ExploreView()
      }
      .tabItem {
        Image(systemName: "magnifyingglass")
        Text("Explore")
      }
      .tag(1)

      NavigationStack {
        VideoCreationView()
      }
      .tabItem {
        Image(systemName: "plus")
        Text("Create")
      }
      .tag(2)

      // Reuse the same MessagesViewModel instance here:
      NavigationStack {
        MessagesView(viewModel: messagesViewModel)
      }
      .tabItem {
        Image(systemName: "message")
        Text("Messages")
      }
      .tag(3)

      NavigationStack {
        ProfileViewContainer(userId: nil)
      }
      .tabItem {
        Label("Profile", systemImage: "person.fill")
      }
      .tag(4)
    }
    .onAppear {
      if let currentUser = authViewModel.currentUser {
        if let userId = currentUser.id, !userId.isEmpty {
          Task {
            try? await userViewModel.loadUser(userId: userId)
          }
        }
      }
    }
    .onChange(of: authViewModel.currentUser) { _, newValue in
      if let user = newValue {
        if let userId = user.id, !userId.isEmpty {
          Task {
            try? await userViewModel.loadUser(userId: userId)
          }
        }
      }
    }
  }
}

#Preview {
  ContentView()
}