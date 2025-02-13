import FirebaseFirestore
import SwiftUI

struct ExploreView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ExploreViewModel()
  @Environment(UserViewModel.self) private var userViewModel
  @State private var searchText = ""
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var selectedTab: ExploreTab = .explore

  enum ExploreTab {
    case explore
    case dating
    case search
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Segmented control for tabs
        if userViewModel.user.isDatingEnabled {
          Picker("Section", selection: $selectedTab) {
            Text("Explore").tag(ExploreTab.explore)
            Text("Dating").tag(ExploreTab.dating)
            Text("Search").tag(ExploreTab.search)
          }
          .pickerStyle(.segmented)
          .padding()
        } else {
          Picker("Section", selection: $selectedTab) {
            Text("Explore").tag(ExploreTab.explore)
            Text("Search").tag(ExploreTab.search)
          }
          .pickerStyle(.segmented)
          .padding()
        }

        // Search bar always visible in search tab
        if selectedTab == .search {
          SearchBar(
            text: $searchText,
            placeholder: "Search videos, users, or hashtags",
            onSubmit: {
              viewModel.search(query: searchText)
            }
          )
          .padding(.horizontal)
        }

        ScrollView(.vertical) {
          switch selectedTab {
          case .explore:
            exploreContent
          case .dating where userViewModel.user.isDatingEnabled:
            DatingView()
          case .search:
            searchContent
          default:
            EmptyView()
          }
        }
        .padding(.vertical)
      }
      .navigationTitle(selectedTab.title)
      .alert("Error", isPresented: $showError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
      .onChange(of: searchText) { _, newValue in
        if selectedTab == .search {
          viewModel.search(query: newValue)
        }
      }
    }
  }

  private var exploreContent: some View {
    LazyVStack(spacing: 20) {
      // Trending hashtags
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(viewModel.trendingHashtags, id: \.self) { hashtag in
            Button(action: {
              searchText = "#\(hashtag)"
              selectedTab = .search
            }) {
              Text("#\(hashtag)")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            }
          }
        }
        .padding(.horizontal)
      }

      // Recommended users
      VStack(alignment: .leading) {
        Text("Recommended Users")
          .font(.headline)
          .padding(.horizontal)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 16) {
            ForEach(viewModel.suggestedUsers) { user in
              NavigationLink {
                ProfileViewContainer(userId: user.id ?? "unknown")
              } label: {
                RecommendedUserCell(viewModel: viewModel, user: user)
              }
            }
          }
          .padding(.horizontal)
        }
      }

      // Trending videos grid
      VStack(alignment: .leading) {
        Text("Trending Videos")
          .font(.headline)
          .padding(.horizontal)

        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 1),
            GridItem(.flexible(), spacing: 1),
            GridItem(.flexible(), spacing: 1),
          ], spacing: 1
        ) {
          ForEach(viewModel.trendingVideos) { video in
            NavigationLink(
              destination: VideoDetailView(video: video, videos: viewModel.trendingVideos)
            ) {
              VideoThumbnailView(video: video)
                .aspectRatio(9 / 16, contentMode: .fill)
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  private var searchContent: some View {
    LazyVStack(spacing: 16) {
      ForEach(viewModel.searchResults) { result in
        SearchResultCell(viewModel: viewModel, result: result)
      }
    }
  }
}

extension ExploreView.ExploreTab {
  var title: String {
    switch self {
    case .explore:
      return "Explore"
    case .dating:
      return "Dating"
    case .search:
      return "Search"
    }
  }
}

struct RecommendedUserCell: View {
  @ObservedObject var viewModel: ExploreViewModel
  @State private var showError = false
  @State private var errorMessage = ""
  let user: User

  var body: some View {
    VStack {
      if let imageURL = user.profileImageURL {
        AsyncImage(url: URL(string: imageURL)) { image in
          image
            .resizable()
            .scaledToFill()
        } placeholder: {
          Image(systemName: "person.circle.fill")
            .resizable()
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
      } else {
        Image(systemName: "person.circle.fill")
          .resizable()
          .frame(width: 80, height: 80)
          .foregroundColor(.gray)
      }

      Text(user.username)
        .font(.subheadline)
        .lineLimit(1)

      Button(action: {
        Task {
          do {
            try await viewModel.followUser(userId: user.id ?? "")
          } catch let error as ExploreViewModel.ExploreError {
            errorMessage = error.localizedDescription
            showError = true
          } catch {
            errorMessage = "Failed to follow user"
            showError = true
          }
        }
      }) {
        Text(viewModel.isFollowing[user.id ?? ""] == true ? "Following" : "Follow")
          .font(.caption)
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(Color.blue)
          .cornerRadius(12)
      }
    }
    .frame(width: 100)
  }
}

struct SearchResultCell: View {
  @ObservedObject var viewModel: ExploreViewModel
  let result: SearchResult

  var body: some View {
    switch result {
    case .user(let user):
      NavigationLink {
        ProfileViewContainer(userId: user.id ?? "unknown")
      } label: {
        HStack {
          if let imageURL = user.profileImageURL {
            AsyncImage(url: URL(string: imageURL)) { image in
              image
                .resizable()
                .scaledToFill()
            } placeholder: {
              Image(systemName: "person.circle.fill")
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
          }

          VStack(alignment: .leading) {
            Text(user.username)
              .font(.headline)
            Text(user.fullName)
              .font(.subheadline)
              .foregroundColor(.gray)
          }
        }
        .padding(.horizontal)
      }

    case .hashtag(let tag):
      NavigationLink(destination: HashtagVideosView(hashtag: tag)) {
        HStack {
          Image(systemName: "number")
            .foregroundColor(.blue)
            .frame(width: 40, height: 40)

          Text("#\(tag)")
            .font(.headline)

          Spacer()

          Image(systemName: "chevron.right")
            .foregroundColor(.gray)
        }
        .padding(.horizontal)
      }
    }
  }
}

struct HashtagVideosView: View {
  let hashtag: String
  @StateObject private var viewModel = HashtagVideosViewModel()

  var body: some View {
    ScrollView {
      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 1),
          GridItem(.flexible(), spacing: 1),
          GridItem(.flexible(), spacing: 1),
        ], spacing: 1
      ) {
        ForEach(viewModel.videos) { video in
          NavigationLink(destination: VideoDetailView(video: video, videos: viewModel.videos)) {
            VideoThumbnailView(video: video)
              .aspectRatio(9 / 16, contentMode: .fill)
          }
        }
      }
    }
    .navigationTitle("#\(hashtag)")
    .task {
      await viewModel.fetchVideos(forHashtag: hashtag)
    }
  }
}

#Preview {
  ExploreView()
}
