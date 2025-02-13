import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MovieTransferable: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(contentType: .movie) { movie in
      SentTransferredFile(movie.url)
    } importing: { received in
      let copy = URL.documentsDirectory.appending(path: "\(UUID().uuidString).mov")

      if FileManager.default.fileExists(atPath: copy.path()) {
        try FileManager.default.removeItem(at: copy)
      }

      try FileManager.default.copyItem(at: received.file, to: copy)
      return Self.init(url: copy)
    }
  }
}

enum VideoQuality: String, CaseIterable {
  case high = "High"
  case medium = "Medium"
  case low = "Low"
}

@available(iOS 18.0, *)
extension VideoQuality: @unchecked Sendable {}
