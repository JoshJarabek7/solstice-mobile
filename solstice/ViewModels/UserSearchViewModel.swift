import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseStorage
import Foundation
import SwiftUI

@Observable
final class UserSearchViewModel {
  var searchResults: [User] = []
  var isLoading = false
  var error: Error?

  private let db = Firestore.firestore()
  private let currentUserId: String
  private var searchTask: Task<Void, Never>?

  init() {
    self.currentUserId = Auth.auth().currentUser?.uid ?? ""
  }

  private func processDocument(_ document: DocumentSnapshot) -> User? {
    var data = document.data() ?? [:]

    // Set the document ID in the data before decoding
    data["id"] = document.documentID

    // Handle nested ageRange structure
    if let ageRange = data["ageRange"] as? [String: Any] {
      data["ageRange.min"] = ageRange["min"] as? Int ?? 18
      data["ageRange.max"] = ageRange["max"] as? Int ?? 100
      data.removeValue(forKey: "ageRange")
    }

    // Handle boolean fields
    for field in ["isDatingEnabled", "isPrivate"] {
      if let value = data[field] {
        if let boolValue = value as? Bool {
          data[field] = boolValue
        } else if let intValue = value as? Int {
          data[field] = (intValue != 0)
        }
      }
    }

    // Handle timestamps
    if let timestamp = data["createdAt"] as? Timestamp {
      data["createdAt"] = timestamp.dateValue()
    }

    let decoder = Firestore.Decoder()
    do {
      var user = try decoder.decode(User.self, from: data)
      // Double ensure the ID is set
      if user.id == nil {
        user.id = document.documentID
      }
      print("[DEBUG] Processed user with ID: \(user.id ?? "nil"), username: \(user.username)")
      return user
    } catch {
      print("[DEBUG] Failed to decode document: \(document.documentID)")
      print("[DEBUG] Decoding error: \(error)")
      print("[DEBUG] Data being decoded: \(data)")
      return nil
    }
  }

  @MainActor
  func searchUsers(_ query: String) async {
    print("[DEBUG] -------- Search Start --------")
    print("[DEBUG] Starting search with query: '\(query)'")
    print("[DEBUG] Current user ID: \(Auth.auth().currentUser?.uid ?? "nil")")
    print("[DEBUG] Is user signed in: \(Auth.auth().currentUser != nil)")

    guard !query.isEmpty else {
      print("[DEBUG] Empty query, clearing results")
      searchResults = []
      return
    }

    // Cancel any existing search
    searchTask?.cancel()

    // Create new search task
    searchTask = Task {
      isLoading = true
      defer { 
        isLoading = false
        print("[DEBUG] -------- Search End --------")
      }

      do {
        // Start with a simple query to test permissions
        print("[DEBUG] Attempting simple query first")
        let testQuery = try await db.collection("users")
          .limit(to: 1)
          .getDocuments()
        
        print("[DEBUG] Simple query successful, got \(testQuery.documents.count) documents")
        
        var results = Set<User>()
        let lowercaseQuery = query.lowercased()

        print("[DEBUG] Attempting username search with lowercase query: '\(lowercaseQuery)'")
        // Search by username
        let usernameSnapshot = try await db.collection("users")
          .whereField("username_lowercase", isGreaterThanOrEqualTo: lowercaseQuery)
          .whereField("username_lowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
          .limit(to: 10)
          .getDocuments()

        print("[DEBUG] Username search successful, returned \(usernameSnapshot.documents.count) results")

        // Process username results
        for document in usernameSnapshot.documents {
          print("[DEBUG] Processing username document: \(document.documentID)")
          if let user = processDocument(document), user.id != currentUserId {
            print("[DEBUG] Successfully processed user: \(user.username)")
            results.insert(user)
          }
        }

        if !Task.isCancelled {
          print("[DEBUG] Setting final search results count: \(results.count)")
          self.searchResults = Array(results)
        }
      } catch {
        print("[ERROR] Search failed with error: \(error)")
        print("[ERROR] Error description: \(error.localizedDescription)")
        if let firestoreError = error as NSError? {
          print("[ERROR] Firestore error code: \(firestoreError.code)")
          print("[ERROR] Firestore error domain: \(firestoreError.domain)")
          print("[ERROR] Firestore error userInfo: \(firestoreError.userInfo)")
        }
        
        if !Task.isCancelled {
          self.error = error
          self.searchResults = []
        }
      }
    }
  }
}
