@preconcurrency import Firebase
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import Foundation

enum AuthError: LocalizedError {
  case emptyFields
  case invalidEmail
  case invalidUsername
  case weakPassword
  case usernameTaken
  case networkError
  case unknown(Error)

  var errorDescription: String? {
    switch self {
    case .emptyFields:
      return "Please fill in all fields"
    case .invalidEmail:
      return "Please enter a valid email address"
    case .invalidUsername:
      return
        "Username must be at least 3 characters and contain only letters, numbers, and underscores"
    case .weakPassword:
      return "Password must be at least 8 characters long"
    case .usernameTaken:
      return "This username is already taken"
    case .networkError:
      return "Please check your internet connection and try again"
    case .unknown(let error):
      return error.localizedDescription
    }
  }
}

@MainActor
class AuthViewModel: ObservableObject {
  @Published var userSession: FirebaseAuth.User?
  @Published var currentUser: User?
  @Published var isLoading = false

  static let shared = AuthViewModel()
  private let auth = Auth.auth()
  private let firestore = Firestore.firestore()
  private let networkManager = NetworkManager.shared

  init() {
    self.userSession = auth.currentUser
    Task {
      await fetchUser()
    }
  }

  private func validateSignUpInput(email: String, password: String, username: String) throws {
    // Check network first
    guard networkManager.isConnected else {
      throw AuthError.networkError
    }

    // Check for empty fields
    guard !email.isEmpty && !password.isEmpty && !username.isEmpty else {
      throw AuthError.emptyFields
    }

    // Validate email format
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    guard emailPredicate.evaluate(with: email) else {
      throw AuthError.invalidEmail
    }

    // Validate username
    let usernameRegex = "^[a-zA-Z0-9_]{3,20}$"
    let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
    guard usernamePredicate.evaluate(with: username) else {
      throw AuthError.invalidUsername
    }

    // Validate password strength
    guard password.count >= 8 else {
      throw AuthError.weakPassword
    }
  }

  private func checkUsernameAvailability(_ username: String) async throws {
    let snapshot = try await firestore.collection("users")
      .whereField("username", isEqualTo: username)
      .getDocuments()

    guard snapshot.documents.isEmpty else {
      throw AuthError.usernameTaken
    }
  }

  private func createAppUser(
    from firebaseUser: FirebaseAuth.User, username: String? = nil, fullName: String? = nil
  ) -> User {
    User(
      username: username ?? firebaseUser.email?.components(separatedBy: "@").first ?? "",
      email: firebaseUser.email ?? "",
      fullName: fullName ?? "",
      bio: nil,
      isPrivate: false,
      isDatingEnabled: false,
      profileImageURL: nil,
      location: nil,
      gender: .other,
      interestedIn: [],
      maxDistance: 50,
      ageRangeMin: 18,
      ageRangeMax: 100,
      birthday: nil
    )
  }

  func signIn(withEmail email: String, password: String) async throws {
    do {
      let authResult = try await auth.signIn(withEmail: email, password: password)
      await MainActor.run {
        self.userSession = authResult.user
      }
      // Fetch user data after setting userSession
      await fetchUser()
    } catch {
      throw AuthError.unknown(error)
    }
  }

  func createUser(email: String, password: String, username: String, fullName: String) async throws
  {
    isLoading = true
    defer { isLoading = false }

    do {
      // Check network connectivity first
      guard networkManager.isConnected else {
        throw AuthError.networkError
      }

      // Validate input
      try validateSignUpInput(email: email, password: password, username: username)

      // Check if username is available
      try await checkUsernameAvailability(username)

      // Create Firebase Auth user
      let authResult = try await auth.createUser(withEmail: email, password: password)
      let userId = authResult.user.uid

      // Create user document in Firestore
      let user = createAppUser(from: authResult.user, username: username, fullName: fullName)

      // Convert to dictionary manually to avoid Sendable issues
      let userData: [String: Any] = [
        "username": user.username,
        "email": user.email,
        "fullName": user.fullName,
        "bio": user.bio as Any,
        "isPrivate": user.isPrivate,
        "isDatingEnabled": user.isDatingEnabled,
        "profileImageURL": user.profileImageURL as Any,
        "location": user.location as Any,
        "gender": user.gender.rawValue,
        "interestedIn": user.interestedIn.map { $0.rawValue },
        "maxDistance": user.maxDistance,
        "ageRange": ["min": user.ageRangeMin, "max": user.ageRangeMax],
        "followersCount": 0,
        "followingCount": 0,
        "createdAt": FieldValue.serverTimestamp(),
        "datingImages": [],
        "birthday": nil as Any?,  // Add birthday field
        "username_lowercase": user.username.lowercased(),
        "fullName_lowercase": user.fullName.lowercased(),
      ]

      do {
        // Create the user document with the userId as the document ID
        try await firestore.collection("users").document(userId).setData(userData)

        // Update local state on main actor
        await MainActor.run {
          self.userSession = authResult.user
          // Create a new User instance with the ID
          var newUser = user
          newUser.id = userId
          self.currentUser = newUser
        }
      } catch {
        // If Firestore creation fails, delete the Auth user to maintain consistency
        try? await authResult.user.delete()
        throw AuthError.unknown(error)
      }
    } catch let error as AuthError {
      throw error
    } catch let error as NSError {
      if error.domain == NSURLErrorDomain {
        throw AuthError.networkError
      } else {
        throw AuthError.unknown(error)
      }
    }
  }

  func signOut() async throws {
    do {
      try auth.signOut()
      // Ensure we're on the main actor when updating published properties
      await MainActor.run {
        self.userSession = nil
        self.currentUser = nil
      }
      // Clear any cached data or state
      NotificationCenter.default.post(name: NSNotification.Name("UserDidSignOut"), object: nil)
    } catch {
      throw error
    }
  }

  func fetchUser() async {
    guard let uid = auth.currentUser?.uid else { return }

    do {
      let snapshot = try await firestore.collection("users").document(uid).getDocument()
      guard snapshot.exists else {
        // If the user document doesn't exist, sign out
        try? auth.signOut()
        await MainActor.run {
          self.userSession = nil
          self.currentUser = nil
        }
        return
      }

      await MainActor.run {
        self.currentUser = try? snapshot.data(as: User.self)
      }
    } catch let error as NSError {
      print("DEBUG: Failed to fetch user with error: \(error.localizedDescription)")
      if error.domain == FirestoreErrorDomain,
        error.code == FirestoreErrorCode.permissionDenied.rawValue
      {
        print("DEBUG: Permission denied. Please check Firebase rules.")
        try? auth.signOut()
        await MainActor.run {
          self.userSession = nil
          self.currentUser = nil
        }
      }
    }
  }

  func updateUser(_ user: User) async throws {
    guard let id = user.id else { return }

    do {
      // Convert to dictionary manually to avoid Sendable issues
      let userData: [String: Any] = [
        "id": user.id as Any,
        "username": user.username,
        "email": user.email,
        "fullName": user.fullName,
        "bio": user.bio as Any,
        "isPrivate": user.isPrivate,
        "isDatingEnabled": user.isDatingEnabled,
        "profileImageURL": user.profileImageURL as Any,
        "location": user.location as Any,
        "gender": user.gender.rawValue,
        "interestedIn": user.interestedIn.map { $0.rawValue },
        "maxDistance": user.maxDistance,
        "ageRange": [user.ageRange.lowerBound, user.ageRange.upperBound],
        "followersCount": user.followersCount,
        "followingCount": user.followingCount,
        "createdAt": user.createdAt,
        "datingImages": user.datingImages,
      ]

      try await firestore.collection("users").document(id).setData(userData, merge: true)
      self.currentUser = user
    } catch {
      throw error
    }
  }
}
