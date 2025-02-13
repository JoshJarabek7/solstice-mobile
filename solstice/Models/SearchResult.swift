import FirebaseFirestore
import Foundation

enum SearchResult: Identifiable {
  case user(User)
  case hashtag(String)

  var id: String {
    switch self {
    case .user(let user):
      return "user_\(user.id ?? "")"
    case .hashtag(let tag):
      return "hashtag_\(tag)"
    }
  }
}

// Helper extension for search queries
extension Query {
  func searchUsers(matching query: String, limit: Int = 20) async throws -> [User] {
    let snapshot =
      try await self
      .whereField("username", isGreaterThanOrEqualTo: query)
      .whereField("username", isLessThan: query + "\u{f8ff}")
      .limit(to: limit)
      .getDocuments()

    return try snapshot.documents.compactMap { document in
      try document.data(as: User.self)
    }
  }
}
