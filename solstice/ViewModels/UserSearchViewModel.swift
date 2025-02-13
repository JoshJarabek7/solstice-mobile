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
    print("[DEBUG] Starting search with query: '\(query)'")

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
      defer { isLoading = false }

      do {
        var results = Set<User>()

        // Search by username
        let usernameSnapshot = try await db.collection("users")
          .whereField("username", isGreaterThanOrEqualTo: query)
          .whereField("username", isLessThan: query + "\u{f8ff}")
          .limit(to: 10)
          .getDocuments()

        print("[DEBUG] Username search returned \(usernameSnapshot.documents.count) results")

        // Search by full name
        let fullNameSnapshot = try await db.collection("users")
          .whereField("fullName", isGreaterThanOrEqualTo: query)
          .whereField("fullName", isLessThan: query + "\u{f8ff}")
          .limit(to: 10)
          .getDocuments()

        print("[DEBUG] Full name search returned \(fullNameSnapshot.documents.count) results")

        // Process username results
        for document in usernameSnapshot.documents {
          print("[DEBUG] Processing username document: \(document.documentID)")
          if let user = processDocument(document), user.id != currentUserId {
            print("[DEBUG] Adding user by username: \(user.username) with ID: \(user.id ?? "nil")")
            results.insert(user)
          }
        }

        // Process full name results
        for document in fullNameSnapshot.documents {
          print("[DEBUG] Processing fullname document: \(document.documentID)")
          if let user = processDocument(document), user.id != currentUserId {
            print("[DEBUG] Adding user by full name: \(user.fullName) with ID: \(user.id ?? "nil")")
            results.insert(user)
          }
        }

        // Sort results by relevance
        let sortedResults = Array(results).sorted { user1, user2 in
          // Prioritize exact matches
          let username1MatchesExactly = user1.username == query
          let username2MatchesExactly = user2.username == query
          let fullName1MatchesExactly = user1.fullName == query
          let fullName2MatchesExactly = user2.fullName == query

          if username1MatchesExactly != username2MatchesExactly {
            return username1MatchesExactly
          }

          if fullName1MatchesExactly != fullName2MatchesExactly {
            return fullName1MatchesExactly
          }

          // Then prioritize starts with
          let username1StartsWith = user1.username.hasPrefix(query)
          let username2StartsWith = user2.username.hasPrefix(query)

          if username1StartsWith != username2StartsWith {
            return username1StartsWith
          }

          let fullName1StartsWith = user1.fullName.hasPrefix(query)
          let fullName2StartsWith = user2.fullName.hasPrefix(query)

          if fullName1StartsWith != fullName2StartsWith {
            return fullName1StartsWith
          }

          // Finally sort by follower count
          return user1.followersCount > user2.followersCount
        }

        if !Task.isCancelled {
          print("[DEBUG] Setting final search results count: \(sortedResults.count)")
          self.searchResults = sortedResults
        }
      } catch {
        print("[ERROR] Search failed: \(error.localizedDescription)")
        if !Task.isCancelled {
          self.error = error
          self.searchResults = []
        }
      }
    }
  }
}
