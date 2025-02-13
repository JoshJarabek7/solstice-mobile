import FirebaseAuth
import FirebaseFirestore
@preconcurrency import FirebaseStorage
@preconcurrency import Foundation
import SwiftUI
import UIKit

@Observable
@MainActor
final class UserViewModel {
  var user: User
  private let db = Firestore.firestore()
  private let storage = Storage.storage()

  init() {
    // Initialize with empty user, will be updated when signed in
    self.user = User(
      username: "",
      email: "",
      fullName: "",
      gender: .other
    )

    // Load user data if signed in
    if let currentUser = Auth.auth().currentUser {
      Task {
        try? await loadUser(userId: currentUser.uid)
      }
    }
  }

  func loadUser(userId: String) async throws {
    print("[DEBUG] loadUser - Starting for userId: \(userId)")
    guard !userId.isEmpty else {
      print("[ERROR] loadUser - Empty userId")
      return
    }
    let docRef = db.collection("users").document(userId)
    print("[DEBUG] loadUser - Document reference: \(docRef)")
    let snapshot = try await docRef.getDocument()
    print("[DEBUG] loadUser - Snapshot: \(snapshot)")

    guard var data = snapshot.data() else {
      print("[DEBUG] loadUser - Document data is nil")
      // If document doesn't exist, create it
      let newUser = User(
        username: user.username,
        email: user.email,
        fullName: user.fullName,
        gender: .other
      )
      try await createNewUserDocument(userId: userId, user: newUser)
      self.user = newUser
      return
    }

    print("[DEBUG] Raw user data from Firebase: \(data)")

    // Handle nested ageRange structure
    if let ageRange = data["ageRange"] as? [String: Any] {
      data["ageRange.min"] = ageRange["min"] as? Int ?? 18
      data["ageRange.max"] = ageRange["max"] as? Int ?? 100
      data.removeValue(forKey: "ageRange")
    }

    // Ensure boolean fields are properly handled
    for field in ["isDatingEnabled", "isPrivate"] {
      print("[DEBUG] loadUser - Processing field: \(field)")
      if let value = data[field] {
        print("[DEBUG] loadUser - Value for \(field): \(value)")
        if let boolValue = value as? Bool {
          data[field] = boolValue
        } else if let intValue = value as? Int {
          data[field] = (intValue != 0)
        }
      }
    }
    print("[DEBUG] loadUser - After processing fields: \(data)")
    print("[DEBUG] loadUser - Dating images: \(data["datingImages"] as? [String] ?? [])")
    // Handle arrays - leave interestedIn as strings for decoding
    if let datingImages = data["datingImages"] as? [String] {
      data["datingImages"] = datingImages
    } else {
      data["datingImages"] = [String]()
    }
    print("[DEBUG] loadUser - After handling dating images: \(data)")
    print("[DEBUG] loadUser - About to handle timestamps")
    // Handle timestamps
    if let timestamp = data["createdAt"] as? Timestamp {
      data["createdAt"] = timestamp.dateValue()
    }
    print("[DEBUG] loadUser - After handling timestamps: \(data)")
    print("[DEBUG] Final processed data before decoding: \(data)")

    print("[DEBUG] loadUser - Final data before decoding: \(data)")
    // Create decoder with document reference
    let decoder = Firestore.Decoder()
    decoder.keyDecodingStrategy = .useDefaultKeys

    do {
      let decodedUser = try decoder.decode(User.self, from: data)
      print("[DEBUG] Successfully decoded user: \(decodedUser)")
      self.user = decodedUser
      print("[DEBUG] Successfully loaded user with ID: \(userId)")
      print(
        "[DEBUG] User data: username=\(decodedUser.username), isDatingEnabled=\(decodedUser.isDatingEnabled), interestedIn=\(decodedUser.interestedIn)"
      )
    } catch {
      print("[ERROR] Failed to decode user data: \(error)\nData: \(data)")
      throw error
    }
  }

  private func createNewUserDocument(userId: String, user: User) async throws {
    let docRef = db.collection("users").document(userId)
    let initialData: [String: Any] = [
      "username": user.username,
      "email": user.email,
      "fullName": user.fullName,
      "gender": user.gender.rawValue,
      "isDatingEnabled": false,
      "isPrivate": false,
      "interestedIn": [],
      "maxDistance": 50,
      "followersCount": 0,
      "followingCount": 0,
      "datingImages": [],
      "ageRange": [
        "min": 18,
        "max": 100,
      ],
      "createdAt": Timestamp(date: Date()),
    ]

    try await docRef.setData(initialData)
  }

  // Test function to verify basic write permissions
  private func testBasicUpdate() async throws {
    guard let userId = Auth.auth().currentUser?.uid else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
      )
    }

    // First check if document exists
    let docRef = db.collection("users").document(userId)
    let docSnapshot = try await docRef.getDocument()

    print("[DEBUG] Document exists: \(docSnapshot.exists)")
    if docSnapshot.exists {
      print("[DEBUG] Current document data: \(String(describing: docSnapshot.data()))")
    }

    // Try to create the document if it doesn't exist
    if !docSnapshot.exists {
      print("[DEBUG] Document doesn't exist, creating it...")
      let initialData: [String: Any] = [
        "username": user.username,
        "email": user.email,
        "fullName": user.fullName,
        "createdAt": Timestamp(date: Date()),
      ]
      try await docRef.setData(initialData)
      print("[DEBUG] Created initial document")
    }

    // Now try to update it
    let testData: [String: Any] = [
      "isDatingEnabled": true
    ]

    print("[DEBUG] Testing basic update with data: \(testData)")
    try await docRef.updateData(testData)
    print("[DEBUG] Basic update succeeded!")
  }

  func updateUser() async throws {
    // Verify auth state
    let auth = Auth.auth()
    print("[DEBUG] Auth instance: \(auth)")
    print("[DEBUG] Current auth user: \(String(describing: auth.currentUser))")
    print("[DEBUG] Auth user email: \(String(describing: auth.currentUser?.email))")
    print(
      "[DEBUG] Auth user is anonymous: \(String(describing: auth.currentUser?.isAnonymous))")

    guard let currentUser = auth.currentUser else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
      )
    }

    let userId = currentUser.uid
    print("[DEBUG] Updating user with ID: \(userId)")

    // First get the existing document
    let docRef = db.collection("users").document(userId)
    let docSnapshot = try await docRef.getDocument()

    // Create isolated copies of all mutable data
    let localUser = user
    let datingImages = Array(localUser.datingImages)
    let interestedIn = localUser.interestedIn.map { $0.rawValue }

    // Get existing data as immutable dictionary
    let existingData = docSnapshot.exists ? (docSnapshot.data() ?? [:]) : [:]
    let existingCreatedAt =
      existingData["createdAt"] as? Timestamp ?? Timestamp(date: localUser.createdAt)

    // Create an isolated dictionary with all fields
    let isolatedData: [String: Any] = [
      "username": localUser.username,
      "email": localUser.email,
      "fullName": localUser.fullName,
      "isPrivate": localUser.isPrivate,
      "isDatingEnabled": localUser.isDatingEnabled,
      "gender": localUser.gender.rawValue,
      "interestedIn": interestedIn,
      "maxDistance": localUser.maxDistance,
      "followersCount": localUser.followersCount,
      "followingCount": localUser.followingCount,
      "datingImages": datingImages,
      "ageRange": [
        "min": localUser.ageRangeMin,
        "max": localUser.ageRangeMax,
      ],
      "bio": localUser.bio as Any,
      "profileImageURL": localUser.profileImageURL as Any,
      "location": localUser.location as Any,
      "createdAt": existingCreatedAt,
    ]

    print("[DEBUG] User data to update: \(isolatedData)")
    print("[DEBUG] About to write to path: /users/\(userId)")

    // Try basic update first
    try await testBasicUpdate()
    print("[DEBUG] Basic update worked, now trying full update")

    // Use the isolated data for the update
    try await docRef.setData(isolatedData, merge: true)
  }

  func uploadDatingPhoto(imageData: Data) async throws -> String {
    guard let userId = Auth.auth().currentUser?.uid else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not signed in"])
    }

    // Get image dimensions
    guard let image = UIImage(data: imageData) else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
    }

    let fileName = "users/\(userId)/dating/\(UUID().uuidString).jpg"
    let ref = storage.reference().child(fileName)

    // Create metadata with dimensions
    let metadata = StorageMetadata()
    metadata.contentType = "image/jpeg"
    metadata.customMetadata = [
      "width": String(Int(image.size.width * image.scale)),
      "height": String(Int(image.size.height * image.scale)),
    ]

    _ = try await ref.putDataAsync(imageData, metadata: metadata)
    let url = try await ref.downloadURL()
    return url.absoluteString
  }

  func signOut() async {
    // Reset local user state
    self.user = User(
      username: "",
      email: "",
      fullName: "",
      gender: .other
    )
  }

  func deactivateDating() async {
    // Store old values in case of error
    let oldDatingEnabled = user.isDatingEnabled
    let oldDatingImages = user.datingImages

    // Update local state
    user.isDatingEnabled = false
    user.datingImages = []

    do {
      // Update in Firestore
      try await updateUser()

      // Delete dating images from storage
      for imageURL in oldDatingImages {
        if let url = URL(string: imageURL),
          let imagePath = url.path.components(separatedBy: "/o/").last?
            .removingPercentEncoding
        {
          let storageRef = storage.reference().child(imagePath)
          try? await storageRef.delete()
        }
      }
    } catch {
      // Restore old values if update fails
      user.isDatingEnabled = oldDatingEnabled
      user.datingImages = oldDatingImages
      print("Error deactivating dating: \(error)")
    }
  }
}
