import CoreLocation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseStorage
@preconcurrency import Foundation

@MainActor
class DatingProfileViewModel: ObservableObject {
  @Published var datingProfile: DatingProfile?
  private let db = Firestore.firestore()
  private let storage = Storage.storage()

  func fetchDatingProfile(for userId: String) async throws {
    let docRef = db.collection("datingProfiles").document(userId)
    let snapshot = try await docRef.getDocument()
    datingProfile = try snapshot.data(as: DatingProfile.self)
  }

  func updateDatingProfile(_ profile: DatingProfile) async throws {
    print("[DEBUG] updateDatingProfile - Starting")
    guard let id = profile.id else {
      print("[ERROR] updateDatingProfile - Missing profile ID")
      throw NSError(
        domain: "DatingProfileError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Profile ID is missing"])
    }
    print("[DEBUG] updateDatingProfile - id: \(id)")

    let docRef = db.collection("datingProfiles").document(id)
    try docRef.setData(from: profile, merge: true)
  }

  func uploadPhoto(imageData: Data) async throws -> String {
    guard let profile = datingProfile else {
      throw NSError(
        domain: "DatingProfileError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No dating profile available"])
    }

    let userId = profile.id ?? UUID().uuidString
    let filename = "\(UUID().uuidString).jpg"
    let storageRef = storage.reference().child("datingPhotos/\(userId)/\(filename)")

    let metadata = StorageMetadata()
    metadata.contentType = "image/jpeg"

    do {
      _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
      let downloadURL = try await storageRef.downloadURL()
      return downloadURL.absoluteString
    } catch {
      throw error
    }
  }

  func deletePhoto(url: String) async throws {
    guard var profile = datingProfile else {
      throw NSError(
        domain: "DatingProfileError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No dating profile available"])
    }

    let storageRef = storage.reference(forURL: url)
    try await storageRef.delete()

    profile.photos.removeAll { $0 == url }
    try await updateDatingProfile(profile)
  }

  func updateLocation(_ location: CLLocation) async throws {
    guard var profile = datingProfile else {
      throw NSError(
        domain: "DatingProfileError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No dating profile available"])
    }

    profile.location = FirebaseFirestore.GeoPoint(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
    try await updateDatingProfile(profile)
  }
}
