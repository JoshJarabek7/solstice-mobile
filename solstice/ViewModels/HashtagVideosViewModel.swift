import FirebaseFirestore
import SwiftUI

@MainActor
final class HashtagVideosViewModel: ObservableObject {
  @Published var videos: [Video] = []
  @Published var isLoading = false
  @Published var errorMessage: String?

  private let db = Firestore.firestore()
  private var lastDocument: DocumentSnapshot?

  func fetchVideos(forHashtag hashtag: String) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      var query = db.collection("videos")
        .whereField("hashtags", arrayContains: hashtag)
        .order(by: "timestamp", descending: true)
        .limit(to: 20)

      if let lastDoc = lastDocument {
        query = query.start(afterDocument: lastDoc)
      }

      let snapshot = try await query.getDocuments()
      let newVideos = try snapshot.documents.compactMap { doc -> Video? in
        try doc.data(as: Video.self)
      }

      if snapshot.documents.isEmpty {
        return
      }

      lastDocument = snapshot.documents.last
      videos.append(contentsOf: newVideos)
    } catch {
      errorMessage = "Failed to load videos: \(error.localizedDescription)"
    }
  }

  func loadMoreIfNeeded(currentVideo: Video) {
    guard let lastVideo = videos.last,
      lastVideo.id == currentVideo.id
    else { return }

    Task {
      await fetchVideos(forHashtag: currentVideo.hashtags.first ?? "")
    }
  }
}

#Preview {
  Text("HashtagVideosViewModel Preview")
}
