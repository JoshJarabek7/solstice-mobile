import CoreLocation
import FirebaseFirestore
import SwiftUI

struct DatingView: View {
  @State private var viewModel = DatingViewModel()
  @State private var showFilters = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var isLoading = true
  @State private var currentFilters: DatingFilters
  @Environment(\.locationManager) private var locationManager
  @Environment(UserViewModel.self) private var userViewModel

  init() {
    print("[DEBUG] DatingView - Initializing - Calling UserViewModel")
    _currentFilters = State(initialValue: DatingFilters())
  }

  var body: some View {
    NavigationStack {
      ZStack {
        if isLoading {
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Finding matches...")
              .foregroundColor(.gray)
          }
        } else if viewModel.profiles.isEmpty {
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
        } else {
          ForEach(viewModel.profiles.indices.reversed(), id: \.self) { index in
            DatingCardView(profile: viewModel.profiles[index])
              .offset(viewModel.cardOffsets[index])
              .rotationEffect(viewModel.cardRotations[index])
              .gesture(
                DragGesture()
                  .onChanged { gesture in
                    viewModel.updateCardOffset(at: index, offset: gesture.translation)
                  }
                  .onEnded { gesture in
                    do {
                      try viewModel.handleSwipe(at: index, translation: gesture.translation)
                    } catch {
                      showError = true
                      errorMessage = error.localizedDescription
                    }
                  }
              )
          }
        }
      }
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
    }
  }
}

struct DatingCardView: View {
  let profile: User
  @State private var currentImageIndex = 0
  @Environment(\.locationManager) private var locationManager

  var body: some View {
    ZStack(alignment: .bottom) {
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

      VStack(alignment: .leading, spacing: 8) {
        Text(
          "\(profile.fullName), \(Calendar.current.dateComponents([.year], from: Date()).year! - Calendar.current.dateComponents([.year], from: profile.createdAt).year!)"
        )
        .font(.title2)
        .bold()

        if let bio = profile.bio {
          Text(bio)
            .font(.body)
            .lineLimit(3)
        }

        HStack {
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

          Spacer()

          if let location = profile.location {
            Text("\(calculateDistance(to: location)) miles away")
              .font(.caption)
              .foregroundColor(.white)
          }
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
    }
    .frame(
      width: UIScreen.main.bounds.width - 40,
      height: UIScreen.main.bounds.height * 0.7
    )
    .cornerRadius(20)
    .shadow(radius: 5)
  }

  private func calculateDistance(to location: GeoPoint) -> Double {
    guard let userLocation = locationManager.currentLocation else { return 0 }
    let cardLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
    return userLocation.distance(from: cardLocation) / 1609.34  // Convert meters to miles
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
