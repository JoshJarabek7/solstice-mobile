import AVFoundation
import Photos

enum VideoDownloader {
  enum DownloadError: Error {
    case invalidURL
    case downloadFailed(Error)
    case saveFailed(Error)
    case permissionDenied
    case unknown
  }

  static func downloadVideo(from urlString: String) async throws {
    guard let url = URL(string: urlString) else {
      throw DownloadError.invalidURL
    }

    // Check permissions first
    let status = await checkPhotoLibraryPermission()
    guard status == .authorized else {
      throw DownloadError.permissionDenied
    }

    do {
      // Download video
      let (localURL, _) = try await URLSession.shared.download(from: url)

      // Save to photos
      try await saveVideoToPhotos(at: localURL)

      // Cleanup temporary file
      try? FileManager.default.removeItem(at: localURL)

      // Success haptic feedback
      await HapticManager.success()
    } catch {
      await HapticManager.error()
      throw DownloadError.downloadFailed(error)
    }
  }

  private static func checkPhotoLibraryPermission() async -> PHAuthorizationStatus {
    await withCheckedContinuation { continuation in
      PHPhotoLibrary.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  private static func saveVideoToPhotos(at url: URL) async throws {
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      request.addResource(with: .video, fileURL: url, options: nil)
    }
  }

  static func compressVideoIfNeeded(url: URL, maxSize: Int64 = 50_000_000) async throws -> URL {
    let asset = AVURLAsset(url: url)

    // Check file size
    let resources = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let fileSize = resources.fileSize,
      fileSize > maxSize
    else {
      return url
    }

    // Calculate compression settings
    let compressionPresets: [String] = [
      AVAssetExportPresetHighestQuality,
      AVAssetExportPresetMediumQuality,
      AVAssetExportPresetLowQuality,
    ]

    for preset in compressionPresets {
      if let compressedURL = try await compressVideo(
        asset: asset,
        outputURL: getTemporaryURL(),
        preset: preset),
        let compressedSize = try? compressedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        compressedSize <= maxSize
      {
        return compressedURL
      }
    }

    throw DownloadError.unknown
  }

  private static func compressVideo(
    asset: AVAsset,
    outputURL: URL,
    preset: String
  ) async throws -> URL? {
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
      return nil
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    for try await state in exportSession.states(updateInterval: 0.1) {
      switch state {
      case .pending, .waiting:
        continue
      case .exporting:
        // You might want to do something with the progress here
        continue
      @unknown default:
        continue
      }
    }

    // After the loop completes, check if export was successful
    if let outputURL = exportSession.outputURL {
      return outputURL
    }
    return nil
  }

  private static func getTemporaryURL() -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    return temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(
      "mp4")
  }
}
