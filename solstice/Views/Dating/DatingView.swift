import CoreLocation
import FirebaseFirestore
import SwiftUI
import Observation

struct DatingView: View {
  @State private var viewModel = DatingViewModel()
  @State private var showFilters = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var isLoading = true
  @State private var currentFilters: DatingFilters
  @State private var navigationPath = NavigationPath()
  @Environment(\.locationManager) private var locationManager
  @Environment(UserViewModel.self) private var userViewModel

  init() {
    print("[DEBUG] DatingView - Initializing - Calling UserViewModel")
    _currentFilters = State(initialValue: DatingFilters())
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        if isLoading {
          DatingLoadingView()
        } else if viewModel.profiles.isEmpty {
          EmptyStateView(showFilters: $showFilters)
            .transition(.opacity)
        } else {
          ProfileStackView(
            viewModel: viewModel,
            onError: { error in
              showError = true
              errorMessage = error.localizedDescription
            }
          )
          .transition(.opacity)
        }
      }
      .animation(.easeInOut, value: viewModel.profiles.isEmpty)
      .navigationTitle("Dating")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: { showFilters.toggle() }) {
            Image(systemName: "slider.horizontal.3")
          }
        }
      }
      .sheet(isPresented: $showFilters) {
        DatingFiltersView(
          filters: $currentFilters,
          onSave: {
            Task {
              try? await viewModel.refreshProfiles()
            }
          }
        )
        .presentationDetents([.medium])
      }
      .alert("Error", isPresented: $showError) {
        Button("OK") {}
      } message: {
        Text(errorMessage)
      }
      .alert("It's a Match! 🎉", isPresented: $viewModel.showMatchAlert) {
        Button("Start Chatting") {
          if let chatId = viewModel.matchedChatId {
            // Navigate to the chat view
            navigationPath.append(Route.chat(chatId))
          }
        }
        Button("Keep Swiping", role: .cancel) {
          // Clear the matched user and chat ID
          viewModel.matchedUser = nil
          viewModel.matchedChatId = nil
        }
      } message: {
        if let matchedUser = viewModel.matchedUser {
          Text("You and \(matchedUser.fullName) liked each other! Start chatting now to get to know each other better.")
        }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .chat(let chatId):
          if let chat = MessagesViewModel.shared.chats.first(where: { $0.id == chatId }) {
            ChatView(chat: chat)
          }
        }
      }
      .task {
        do {
          isLoading = true
          try await viewModel.initialize()
          isLoading = false
        } catch {
          showError = true
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
      .onChange(of: currentFilters) { _, newFilters in
        viewModel.filters = newFilters
        Task {
          do {
            isLoading = true
            try await viewModel.refreshProfiles()
            isLoading = false
          } catch {
            showError = true
            errorMessage = error.localizedDescription
            isLoading = false
          }
        }
      }
      .onAppear {
        viewModel.setReturningFromProfile(true)
      }
    }
  }
}

enum Route: Hashable {
  case chat(String)
}

// MARK: - Profile Stack View
private struct ProfileStackView: View {
  let viewModel: DatingViewModel
  let onError: (Error) -> Void
  
  var body: some View {
    ProfileCardsView(
      profiles: viewModel.profiles,
      onLike: { profile, index in handleLike(profile: profile, at: index) },
      onPass: { profile, index in handlePass(profile: profile, at: index) }
    )
  }
  
  private func handleLike(profile: User, at index: Int) {
    Task {
      await viewModel.likeProfile(profile)
      await viewModel.removeProfile(at: index)
      
      // Fetch more profiles if running low
      if viewModel.profiles.count < 3 {
        do {
          try await viewModel.refreshProfiles()
        } catch {
          onError(error)
        }
      }
    }
  }
  
  private func handlePass(profile: User, at index: Int) {
    Task {
      await viewModel.passProfile(profile)
      await viewModel.removeProfile(at: index)
      
      // Fetch more profiles if running low
      if viewModel.profiles.count < 3 {
        do {
          try await viewModel.refreshProfiles()
        } catch {
          onError(error)
        }
      }
    }
  }
}

// MARK: - Profile Cards View
private struct ProfileCardsView: View {
  let profiles: [User]
  let onLike: (User, Int) -> Void
  let onPass: (User, Int) -> Void
  
  var body: some View {
    ZStack {
      ForEach(Array(profiles.enumerated().reversed()), id: \.element.id) { index, profile in
        DatingCardView(
          profile: profile,
          onLike: { onLike(profile, index) },
          onPass: { onPass(profile, index) }
        )
        .id("\(profile.id ?? "")-\(index)")
        .zIndex(Double(profiles.count - index))
      }
    }
  }
}

// MARK: - Supporting Views

private struct DatingLoadingView: View {
  var body: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
      Text("Finding matches...")
        .foregroundColor(.gray)
    }
  }
}

private struct EmptyStateView: View {
  @Binding var showFilters: Bool
  
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "heart.slash.circle.fill")
        .font(.system(size: 60))
        .foregroundColor(.gray)
      Text("No more profiles to show")
        .font(.title2)
      Text("Try adjusting your filters or check back later")
        .foregroundColor(.gray)
      Button(action: { showFilters.toggle() }) {
        Label("Adjust Filters", systemImage: "slider.horizontal.3")
          .padding()
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(10)
      }
    }
    .padding()
  }
}

private struct DatingCardView: View {
  private enum SwipeDirection {
    case none, vertical, horizontal
  }

  let profile: User
  let onLike: () -> Void
  let onPass: () -> Void
  @State private var currentImageIndex = 0
  @State private var offset = CGSize.zero
  @State private var swipeDirection: SwipeDirection = .none
  @State private var showMatchAlert = false
  @State private var isDragging = false
  @Environment(\.locationManager) private var locationManager

  // Cache computed values
  private let age: Int
  
  init(profile: User, onLike: @escaping () -> Void, onPass: @escaping () -> Void) {
    self.profile = profile
    self.onLike = onLike
    self.onPass = onPass
    self.age = profile.age ?? 0
  }
  
  private var formattedDistance: String? {
    guard let location = profile.location,
          let userLocation = locationManager.currentLocation else { return nil }
    
    let cardLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
    let distanceInMiles = userLocation.distance(from: cardLocation) / 1609.34
    if distanceInMiles < 1 {
      return "<1 mile"
    } else {
      let roundedDistance = (distanceInMiles * 10).rounded() / 10
      return "\(roundedDistance) miles"
    }
  }

  private var likeOverlayOpacity: Double {
    let maxOffset: CGFloat = -100 // Threshold for full opacity
    return min(1.0, abs(min(offset.height, 0)) / abs(maxOffset))
  }

  private var passOverlayOpacity: Double {
    let maxOffset: CGFloat = 100 // Threshold for full opacity
    return min(1.0, max(offset.height, 0) / maxOffset)
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Images TabView
      if !profile.datingImages.isEmpty {
        TabView(selection: $currentImageIndex) {
          ForEach(profile.datingImages.indices, id: \.self) { index in
            AsyncImage(url: URL(string: profile.datingImages[index])) { image in
              image
                .resizable()
                .scaledToFill()
            } placeholder: {
              ProgressView()
            }
            .tag(index)
            .clipped()
          }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
      } else {
        AsyncImage(url: URL(string: profile.profileImageURL ?? "")) { image in
          image
            .resizable()
            .scaledToFill()
        } placeholder: {
          ProgressView()
        }
      }

      // Info overlay
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("\(profile.fullName), \(age)")
            .font(.title2)
            .bold()
            .foregroundColor(.white)

          Spacer()

          if let formattedDistance = formattedDistance {
            Text(formattedDistance)
              .font(.subheadline)
              .foregroundColor(.white)
          }
        }

        if let bio = profile.bio {
          Text(bio)
            .font(.body)
            .lineLimit(3)
            .foregroundColor(.white)
        }

        NavigationLink {
          ProfileViewContainer(userId: profile.id!)
        } label: {
          Text("View Full Profile")
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(20)
        }
      }
      .padding()
      .background(
        LinearGradient(
          gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
          startPoint: .top,
          endPoint: .bottom
        )
      )

      // Like overlay (green checkmark)
      ZStack {
        Color.green
          .opacity(0.7 * likeOverlayOpacity)
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 100))
          .foregroundColor(.white)
          .opacity(likeOverlayOpacity)
      }
      .opacity(offset.height < 0 ? likeOverlayOpacity : 0)

      // Pass overlay (red X)
      ZStack {
        Color.red
          .opacity(0.7 * passOverlayOpacity)
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 100))
          .foregroundColor(.white)
          .opacity(passOverlayOpacity)
      }
      .opacity(offset.height > 0 ? passOverlayOpacity : 0)
    }
    .frame(
      width: UIScreen.main.bounds.width - 40,
      height: UIScreen.main.bounds.height * 0.7
    )
    .cornerRadius(20)
    .shadow(radius: 5)
    .offset(offset)
    .rotationEffect(.degrees(Double(offset.width / 10)))
    .gesture(
      DragGesture(minimumDistance: 20)
        .onChanged { gesture in
          isDragging = true
          let translation = gesture.translation
          
          // Only handle vertical swipes for like/pass
          let verticalComponent = abs(translation.height)
          let horizontalComponent = abs(translation.width)
          
          // If the movement is more vertical than horizontal, handle the swipe
          if verticalComponent > horizontalComponent {
            offset = CGSize(width: translation.width * 0.3, height: translation.height)
            swipeDirection = .vertical
          } else {
            // Let TabView handle horizontal swipes
            offset = .zero
            swipeDirection = .horizontal
          }
        }
        .onEnded { gesture in
          isDragging = false
          let translation = gesture.translation
          let velocity = gesture.velocity
          
          // Only process vertical swipes
          if abs(translation.height) > abs(translation.width) {
            let threshold: CGFloat = UIScreen.main.bounds.height * 0.25  // About 25% of screen height
            let velocityThreshold: CGFloat = 300
            let isSwiftSwipe = abs(velocity.height) > velocityThreshold
            
            // Only trigger if we're beyond threshold and moving away from center
            let isFarEnough = abs(translation.height) > threshold
            let isMovingAway = (translation.height < 0 && velocity.height < 0) || 
                              (translation.height > 0 && velocity.height > 0)
            
            if (isFarEnough && isMovingAway) || isSwiftSwipe {
              if translation.height < 0 || velocity.height < -velocityThreshold {
                // Swipe up - Like
                withAnimation(.easeOut(duration: 0.2)) {
                  offset = CGSize(width: 0, height: -1000)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  onLike()
                }
              } else {
                // Swipe down - Pass
                withAnimation(.easeOut(duration: 0.2)) {
                  offset = CGSize(width: 0, height: 1000)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  onPass()
                }
              }
            } else {
              // Reset position with a smoother spring animation
              withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                offset = .zero
              }
            }
          } else {
            // Reset any offset if it was a horizontal swipe
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
              offset = .zero
            }
          }
          
          // Reset swipe direction after animation
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            swipeDirection = .none
          }
        }
    )
  }
}

struct DatingFilters: Equatable {
  var interestedIn: [User.Gender] = []
  var maxDistance: Double?
  var ageRange: ClosedRange<Int> = 18...100
}

#Preview {
  DatingView()
}