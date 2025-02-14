@preconcurrency import CoreLocation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import SwiftUI
import Observation

@Observable
final class DatingViewModel: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
  private let database = Firestore.firestore()
  private var lastDocument: DocumentSnapshot?
  private let locationManager: CLLocationManager
  private var isInitialized = false
  private var isFetching = false  // Add fetching flag

  var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
  var currentLocation: CLLocation?
  private var locationAuthorizationContinuation: CheckedContinuation<Void, Error>?

  var profiles = [User]()
  var cardOffsets = [CGSize]()
  var cardRotations = [Angle]()
  var filters = DatingFilters()
  
  // Track if we're returning from profile view
  private var isReturningFromProfile = false
  private var lastProfileCount = 0
  private var seenProfileIds = Set<String>()  // Add set to track seen profiles
  private var shownMatchIds = Set<String>()  // Add set to track shown matches

  var showMatchAlert = false
  var matchedUser: User?
  var matchedChatId: String?

  override init() {
    self.locationManager = CLLocationManager()
    super.init()
    setupLocationManager()
    setupMatchListener()
  }

  private func setupMatchListener() {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    // Listen for likes where current user is the liked person
    database.collection("likes")
      .whereField("likedId", isEqualTo: currentUserId)
      .addSnapshotListener { [weak self] snapshot, error in
        guard let self = self,
              let snapshot = snapshot else { return }
        
        for change in snapshot.documentChanges {
          if change.type == .added {
            let data = change.document.data()
            guard let likerId = data["likerId"] as? String else { continue }
            
            // Skip if we've already shown this match
            if self.shownMatchIds.contains(likerId) {
              continue
            }
            
            // Check if we've also liked them
            Task {
              do {
                let ourLikeDoc = try await self.database.collection("likes")
                  .document("\(currentUserId)_\(likerId)")
                  .getDocument()
                
                if ourLikeDoc.exists {
                  // It's a match! Get the user profile
                  let matchedUser = try await self.fetchUser(userId: likerId)
                  
                  // Find the chat that was created for this match
                  let chats = try await self.database.collection("chats")
                    .whereField("participantIds", arrayContains: currentUserId)
                    .whereField("isDatingChat", isEqualTo: true)
                    .getDocuments()
                  
                  let matchChat = chats.documents.first { doc in
                    let participantIds = doc.data()["participantIds"] as? [String] ?? []
                    return participantIds.contains(likerId)
                  }
                  
                  await MainActor.run {
                    // Add to shown matches before showing alert
                    self.shownMatchIds.insert(likerId)
                    self.matchedUser = matchedUser
                    self.matchedChatId = matchChat?.documentID
                    self.showMatchAlert = true
                  }
                }
              } catch {
                print("[ERROR] Error checking for match: \(error)")
              }
            }
          }
        }
      }
  }

  private func fetchUser(userId: String) async throws -> User {
    print("[DEBUG] Fetching user with ID: \(userId)")
    let userDoc = try await database.collection("users").document(userId).getDocument()
    
    guard var userData = userDoc.data() else {
      print("[ERROR] No data found for user: \(userId)")
      throw DatingError.userNotFound
    }
    
    // Add the document ID to the user data
    userData["id"] = userId
    
    // Handle nested ageRange structure
    if let ageRange = userData["ageRange"] as? [String: Any] {
      userData["ageRange.min"] = ageRange["min"] as? Int ?? 18
      userData["ageRange.max"] = ageRange["max"] as? Int ?? 100
      userData.removeValue(forKey: "ageRange")
    }
    
    // Convert boolean fields from numbers if necessary
    if let isDatingEnabled = userData["isDatingEnabled"] as? Int {
      userData["isDatingEnabled"] = isDatingEnabled != 0
    }
    if let isPrivate = userData["isPrivate"] as? Int {
      userData["isPrivate"] = isPrivate != 0
    }
    
    let decoder = Firestore.Decoder()
    return try decoder.decode(User.self, from: userData)
  }

  func initialize() async throws {
    guard !isInitialized else { return }
    isInitialized = true
    seenProfileIds.removeAll()  // Clear seen profiles on initialize
    try await fetchProfiles()
  }

  private func setupLocationManager() {
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 100  // Update location every 100 meters
  }

  func refreshProfiles() async throws {
    guard isInitialized else { return }
    
    // If returning from profile view, don't clear the stack
    if !isReturningFromProfile {
      profiles.removeAll()
      cardOffsets.removeAll()
      cardRotations.removeAll()
      seenProfileIds.removeAll()  // Clear seen profiles on refresh
    } else {
      isReturningFromProfile = false
    }

    // Fetch new profiles
    try await fetchProfiles()
  }

  // MARK: - CLLocationManagerDelegate

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      self.currentLocation = location
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("[DEBUG] Location manager error: \(error.localizedDescription)")
    Task { @MainActor in
      self.locationAuthorizationContinuation?.resume(throwing: error)
      self.locationAuthorizationContinuation = nil
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      self.locationAuthorizationStatus = manager.authorizationStatus

      switch manager.authorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways:
        locationManager.startUpdatingLocation()
        self.locationAuthorizationContinuation?.resume()
        self.locationAuthorizationContinuation = nil
      case .denied, .restricted:
        let error = DatingError.locationPermissionDenied
        self.locationAuthorizationContinuation?.resume(throwing: error)
        self.locationAuthorizationContinuation = nil
      case .notDetermined:
        // Wait for user response
        break
      @unknown default:
        let error = DatingError.locationNotAvailable
        self.locationAuthorizationContinuation?.resume(throwing: error)
        self.locationAuthorizationContinuation = nil
      }
    }
  }

  private func checkLocationServices() async throws -> Bool {
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: CLLocationManager.locationServicesEnabled())
      }
    }
  }

  private func waitForLocationAuthorization() async throws {
    // If already authorized, return immediately
    let status = locationAuthorizationStatus
    if status == .authorizedWhenInUse || status == .authorizedAlways {
      return
    }

    // If already denied or restricted, throw immediately
    if status == .denied || status == .restricted {
      throw DatingError.locationPermissionDenied
    }

    // Request authorization and wait for callback
    return try await withCheckedThrowingContinuation { continuation in
      self.locationAuthorizationContinuation = continuation
      locationManager.requestWhenInUseAuthorization()
    }
  }

  private func getCurrentUserPreferences(_ userId: String) async throws -> (String, [String: Any]) {
    let currentUserDoc = try await database.collection("users").document(userId).getDocument()
    guard let currentUserData = currentUserDoc.data() else {
      print("[ERROR] Current user document has no data")
      throw DatingError.userNotFound
    }

    guard let currentUserGender = currentUserData["gender"] as? String else {
      print("[ERROR] Current user missing gender field")
      throw DatingError.invalidUserData
    }

    print("[DEBUG] Current user gender: \(currentUserGender)")
    return (currentUserGender, currentUserData)
  }

  private func buildDatingQuery(currentUserGender: String) -> Query {
    print("[DEBUG] Building dating query with filters: \(filters)")
    var query = database.collection("users")
      .whereField("isDatingEnabled", isEqualTo: true)

    // Apply gender filter based on mutual matching
    if !filters.interestedIn.isEmpty {
      let genderValues = filters.interestedIn.map { $0.rawValue }
      print("[DEBUG] Applying gender filter: \(genderValues)")
      query = query.whereField("gender", in: genderValues)
        .whereField("interestedIn", arrayContains: currentUserGender)
    }

    return query
  }

  private func filterProfile(
    _ data: [String: Any], currentUserId: String, userLocation: CLLocation
  ) -> Bool {
    // Skip current user
    guard data["id"] as? String != currentUserId else {
      print("[DEBUG] Skipping current user document")
      return false
    }

    // Check age range compatibility
    if let ageRange = data["ageRange"] as? [String: Any],
       let theirAgeMin = ageRange["min"] as? Int,
       let theirAgeMax = ageRange["max"] as? Int
    {
      print("[DEBUG] Checking age range compatibility:")
      print("[DEBUG] Their range: \(theirAgeMin)-\(theirAgeMax)")
      print("[DEBUG] Our range: \(filters.ageRange.lowerBound)-\(filters.ageRange.upperBound)")
      
      // Check if their max age is greater than or equal to our minimum age
      // AND their min age is less than or equal to our maximum age
      guard theirAgeMax >= filters.ageRange.lowerBound && theirAgeMin <= filters.ageRange.upperBound else {
        print("[DEBUG] Profile filtered out due to age range mismatch")
        return false
      }
    } else {
      print("[DEBUG] Profile missing age range data")
      return false
    }

    // Check distance if filter is set
    if let maxDistance = filters.maxDistance,
      let geoPoint = data["location"] as? GeoPoint
    {
      let profileLocation = CLLocation(
        latitude: geoPoint.latitude, longitude: geoPoint.longitude)
      let distance = userLocation.distance(from: profileLocation) / 1609.34  // Convert to miles
      print("[DEBUG] Distance between users: \(distance) miles")
      guard distance <= maxDistance else {
        print("[DEBUG] Profile filtered out due to distance (\(distance) miles > \(maxDistance) miles)")
        return false
      }
    }

    print("[DEBUG] Profile passed all filters")
    return true
  }

  private func fetchProfiles() async throws {
    print("[DEBUG] Starting profile fetch")
    
    // Prevent concurrent fetches
    guard !isFetching else {
      print("[DEBUG] Fetch already in progress, skipping")
      return
    }
    
    isFetching = true
    
    defer {
      isFetching = false
    }

    // Get current user ID
    guard let currentUserId = Auth.auth().currentUser?.uid else {
      print("[ERROR] No authenticated user")
      throw DatingError.authenticationRequired
    }

    // Get current user preferences first
    let (currentUserGender, userData) = try await getCurrentUserPreferences(currentUserId)

    // Check if dating is enabled for current user
    guard (userData["isDatingEnabled"] as? Bool) == true else {
      print("[DEBUG] Dating is disabled for current user")
      profiles = []
      cardOffsets = []
      cardRotations = []
      return
    }

    // Check if location services are enabled
    guard try await checkLocationServices() else {
      print("[ERROR] Location services not available")
      throw DatingError.locationNotAvailable
    }

    // Wait for location authorization
    try await waitForLocationAuthorization()

    // Get current location
    guard let location = currentLocation ?? locationManager.location else {
      print("[ERROR] No location available, starting location updates")
      locationManager.startUpdatingLocation()
      throw DatingError.locationNotAvailable
    }

    print("[DEBUG] Current location: \(location)")

    do {
      // Get already liked profiles
      let likedProfiles = try await database.collection("likes")
        .whereField("likerId", isEqualTo: currentUserId)
        .getDocuments()
      let likedIds = Set(likedProfiles.documents.compactMap { $0.data()["likedId"] as? String })
      
      // Get passed profiles
      let passedProfiles = try await database.collection("passes")
        .whereField("passerId", isEqualTo: currentUserId)
        .getDocuments()
      let passedIds = Set(passedProfiles.documents.compactMap { $0.data()["passedId"] as? String })
      
      print("[DEBUG] Found \(likedIds.count) liked and \(passedIds.count) passed profiles")

      // Build and execute query
      let query = buildDatingQuery(currentUserGender: currentUserGender)
      let snapshot = try await query.limit(to: 50).getDocuments()
      print("[DEBUG] Query returned \(snapshot.documents.count) documents")

      // Filter and decode profiles
      print("[DEBUG] Filtering and decoding profiles")
      let decoder = Firestore.Decoder()
      let newProfiles = snapshot.documents.compactMap { doc -> User? in
        var userData = doc.data()
        userData["id"] = doc.documentID
        
        // Skip if we've already interacted with this profile
        guard !likedIds.contains(doc.documentID) && !passedIds.contains(doc.documentID) else {
          print("[DEBUG] Skipping previously interacted profile: \(doc.documentID)")
          return nil
        }

        // Skip if we've already seen this profile in this session
        guard !seenProfileIds.contains(doc.documentID) else {
          print("[DEBUG] Skipping already seen profile: \(doc.documentID)")
          return nil
        }

        guard filterProfile(userData, currentUserId: currentUserId, userLocation: location) else {
          return nil
        }

        // Add to seen profiles if successfully decoded
        if let user = try? decoder.decode(User.self, from: userData) {
          seenProfileIds.insert(doc.documentID)
          return user
        }
        return nil
      }

      print("[DEBUG] Successfully filtered and decoded \(newProfiles.count) profiles")

      // Update profiles
      await MainActor.run {
        if self.profiles.isEmpty {
          self.profiles = newProfiles
        } else {
          self.profiles.append(contentsOf: newProfiles)
        }

        print("[DEBUG] Total profiles in view model: \(self.profiles.count)")

        // Update card states
        self.cardOffsets = Array(repeating: .zero, count: self.profiles.count)
        self.cardRotations = Array(repeating: .zero, count: self.profiles.count)
      }

    } catch {
      print("[ERROR] Failed to fetch profiles: \(error)")
      throw error
    }
  }

  @MainActor
  func updateCardOffset(at index: Int, offset: CGSize) {
    guard index < cardOffsets.count else { return }

    // Limit the vertical movement
    let limitedOffset = CGSize(
      width: offset.width,
      height: min(abs(offset.height), 50) * (offset.height < 0 ? -1 : 1)
    )
    cardOffsets[index] = limitedOffset

    // Calculate rotation based on horizontal movement
    let screenWidth = UIScreen.main.bounds.width
    let rotationAngle = Double(offset.width / screenWidth) * 15  // Reduced rotation angle
    cardRotations[index] = Angle(degrees: rotationAngle)
  }

  @MainActor
  func handleSwipe(at index: Int, translation: CGSize) throws {
    guard index < profiles.count else {
      throw DatingError.swipeError
    }

    let threshold: CGFloat = 150  // Increased threshold for more intentional swipes
    let screenWidth = UIScreen.main.bounds.width

    if abs(translation.width) > threshold {
      let profile = profiles[index]
      let swipeDirection = translation.width > 0 ? 1.0 : -1.0

      // Animate the card off screen
      cardOffsets[index] = CGSize(
        width: swipeDirection * screenWidth * 1.5,
        height: translation.height
      )

      Task {
        // Swipe right (like)
        if translation.width > threshold {
          await likeProfile(profile)
        }
        // Swipe left (pass)
        else if translation.width < -threshold {
          await passProfile(profile)
        }

        await MainActor.run {
          // Remove the profile
          profiles.remove(at: index)
          cardOffsets.remove(at: index)
          cardRotations.remove(at: index)

          // Fetch more profiles if running low
          if profiles.count < 3 {
            Task {
              do {
                try await fetchProfiles()
              } catch {
                print("Error fetching additional profiles: \(error)")
              }
            }
          }
        }
      }
    } else {
      // Reset position with spring animation
      cardOffsets[index] = .zero
      cardRotations[index] = .zero
    }
  }

  // MARK: - Profile Actions
  
  func likeProfile(_ profile: User) async {
    guard let currentUserId = Auth.auth().currentUser?.uid,
          let profileId = profile.id else { return }
    
    print("[DEBUG] Liking profile: \(profileId)")
    
    do {
      // Add like to database
      try await database.collection("likes")
        .document("\(currentUserId)_\(profileId)")
        .setData([
          "likerId": currentUserId,
          "likedId": profileId,
          "timestamp": FieldValue.serverTimestamp()
        ])
      
      print("[DEBUG] Successfully added like to database")
      
      // Check if they've also liked us
      let theirLikeDoc = try await database.collection("likes")
        .document("\(profileId)_\(currentUserId)")
        .getDocument()
      
      if theirLikeDoc.exists {
        print("[DEBUG] Match found! Creating chat...")
        // It's a match! Create a chat
        let chatRef = database.collection("chats").document()
        let timestamp = Timestamp(date: Date())
        
        let chatData: [String: Any] = [
          "participantIds": [currentUserId, profileId],
          "lastActivity": timestamp,
          "isGroup": false,
          "isDatingChat": true,
          "unreadCounts": [
            currentUserId: 0,
            profileId: 0
          ],
          "deletedForUsers": [],
          "hiddenMessagesForUsers": [:],
          "typingUsers": [],
          "createdAt": timestamp,
          "createdBy": currentUserId
        ]
        
        // Create the chat document first
        try await chatRef.setData(chatData)
        print("[DEBUG] Created new chat: \(chatRef.documentID)")
        
        // Verify the chat was created and is properly initialized
        let chatDoc = try await chatRef.getDocument()
        guard chatDoc.exists else {
          print("[ERROR] Chat document not found after creation")
          return
        }
        
        // Show match alert
        await MainActor.run {
          self.matchedUser = profile
          self.matchedChatId = chatRef.documentID
          self.showMatchAlert = true
        }
      }
    } catch {
      print("[ERROR] Error liking profile: \(error)")
    }
  }

  func passProfile(_ profile: User) async {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }

    do {
      print("[DEBUG] Passing profile: \(profile.id ?? "unknown")")
      
      // Record the pass in Firestore
      let passRef = database.collection("passes").document("\(currentUserId)_\(profile.id!)")
      try await passRef.setData([
        "passerId": currentUserId,
        "passedId": profile.id!,
        "timestamp": FieldValue.serverTimestamp(),
      ])
      
      print("[DEBUG] Successfully added pass to database")
    } catch {
      print("[ERROR] Error passing profile: \(error)")
    }
  }

  func setReturningFromProfile(_ returning: Bool) {
    isReturningFromProfile = returning
  }

  @MainActor
  func removeProfile(at index: Int) async {
    guard index < profiles.count else { return }
    
    print("[DEBUG] Removing profile at index: \(index)")
    withAnimation {
      profiles.remove(at: index)
      cardOffsets.remove(at: index)
      cardRotations.remove(at: index)
    }
    
    // Fetch more profiles if running low
    if profiles.count < 3 {
      print("[DEBUG] Profile count low (\(profiles.count)), fetching more profiles")
      Task {
        try? await fetchProfiles()
      }
    }
  }

  // Add function to clear match state
  func clearMatchState() {
    showMatchAlert = false
    matchedUser = nil
    matchedChatId = nil
  }
}

enum DatingError: Error {
  case locationNotAvailable
  case locationPermissionDenied
  case locationPermissionRequired
  case invalidUserData
  case networkError(Error)
  case insufficientProfiles
  case swipeError
  case filterError
  case authenticationRequired
  case userNotFound

  var localizedDescription: String {
    switch self {
    case .locationNotAvailable:
      return
        "Location services are not available. Please enable location services to see nearby profiles."
    case .locationPermissionDenied:
      return
        "Location permission denied. Please enable location access in Settings to see nearby profiles."
    case .locationPermissionRequired:
      return
        "Location permission is required. Please allow access to your location to see nearby profiles."
    case .invalidUserData:
      return "Unable to process user data. Please try again later."
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .insufficientProfiles:
      return "Not enough profiles available in your area. Try expanding your search radius."
    case .swipeError:
      return "Unable to process your swipe. Please try again."
    case .filterError:
      return "Unable to apply filters. Please check your filter settings."
    case .authenticationRequired:
      return "Authentication is required to fetch profiles."
    case .userNotFound:
      return "Unable to find your user profile. Please ensure your profile is complete."
    }
  }
}

#Preview {
  DatingView()
}
