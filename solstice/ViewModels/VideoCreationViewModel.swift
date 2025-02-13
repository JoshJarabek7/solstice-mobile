@preconcurrency import AVKit
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseStorage
import PhotosUI
@preconcurrency import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

@MainActor
final class VideoCreationViewModel: ObservableObject {
  // MARK: - Nonisolated Metadata Helpers
  nonisolated private func createVideoMetadata() -> StorageMetadata {
    let meta = StorageMetadata()
    meta.contentType = "video/mp4"
    return meta
  }

  nonisolated private func createThumbnailMetadata() -> StorageMetadata {
    let meta = StorageMetadata()
    meta.contentType = "image/jpeg"
    return meta
  }

  // Add aspect ratio detection
  private func detectVideoAspectRatio(from asset: AVAsset) async throws -> VideoAspectRatio {
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
    }
    
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    
    // Apply the transform to get the correct orientation
    let transformedSize = size.applying(transform)
    let width = abs(transformedSize.width)
    let height = abs(transformedSize.height)
    
    // Calculate aspect ratio
    let ratio = width / height
    
    // Determine orientation with some tolerance for common aspect ratios
    if abs(ratio - 1) < 0.1 {
      return .square
    } else if ratio > 1 {
      return .landscape
    } else {
      return .portrait
    }
  }

  // MARK: - Published Properties
  @Published private(set) var selectedVideoURL: URL?
  @Published var selectedItem: PhotosPickerItem? {
    didSet { handleSelectedVideo() }
  }
  @Published var caption: String = ""
  @Published var hashtagsText: String = ""
  @Published var player: AVPlayer?
  @Published var startTime: Double = 0
  @Published var endTime: Double = 0
  @Published var duration: Double = 0
  @Published private(set) var uploadProgress: Double = 0
  @Published private(set) var processingStatus: String = ""
  @Published var isUploading = false
  @Published var showError = false
  @Published var showSuccess = false
  @Published var errorMessage = ""

  private nonisolated let videoEditor: VideoEditor
  private var playerItem: AVPlayerItem?
  private var tempURLs: Set<URL> = []

  init() {
    self.videoEditor = VideoEditor()
  }

  // MARK: - Private Properties
  private nonisolated var tempDirectoryURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private var hashtags: [String] {
    hashtagsText.components(separatedBy: " ")
      .filter { $0.starts(with: "#") }
  }

  // MARK: - Video Selection
  func handleSelectedVideo() {
    guard let selectedItem = selectedItem else { return }
    
    Task {
      do {
        guard let videoData = try await selectedItem.loadTransferable(type: Data.self) else {
          throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
        }
        
        // Create a unique directory for this upload session
        let sessionDirectory = FileManager.default.temporaryDirectory
          .appendingPathComponent("VideoUpload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        
        // Save video to session directory
        let videoURL = sessionDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension("mov")
        try videoData.write(to: videoURL)
        tempURLs.insert(videoURL)
        selectedVideoURL = videoURL
        
        // Verify file exists and is readable
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
          throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file is not readable"])
        }
        
        // Create player item and get duration
        let asset = AVURLAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.playerItem = playerItem
        
        // Get video duration
        let duration = try await asset.load(.duration).seconds
        self.duration = duration
        self.endTime = duration
        
        // Create and set up player
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        
        // Loop playback
        NotificationCenter.default.addObserver(
          forName: .AVPlayerItemDidPlayToEndTime,
          object: playerItem,
          queue: .main
        ) { [weak player] _ in
          player?.seek(to: .zero)
          player?.play()
        }
        
        player.play()
      } catch {
        errorMessage = error.localizedDescription
        showError = true
      }
    }
  }

  // MARK: - Video Upload
  func uploadVideo() async throws {
    guard let videoURL = selectedVideoURL else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video selected"])
    }
    
    guard let currentUser = Auth.auth().currentUser else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User must be logged in to upload videos"])
    }
    
    // Verify file exists
    guard FileManager.default.fileExists(atPath: videoURL.path) else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file not found at path: \(videoURL.path)"])
    }
    
    isUploading = true
    showSuccess = false
    processingStatus = "Preparing video..."
    
    do {
      // Create a unique directory for processed video that won't be cleaned up
      let processedDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProcessedVideo-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
      
      // Process video with HEVC encoding
      let processedVideoURL = try await videoEditor.processVideo(
        url: videoURL,
        startTime: startTime,
        endTime: endTime > 0 ? endTime : duration,
        quality: .high
      )
      
      // Copy processed video to our managed directory
      let finalVideoURL = processedDirectory.appendingPathComponent("final.mp4")
      try FileManager.default.copyItem(at: processedVideoURL, to: finalVideoURL)
      tempURLs.insert(finalVideoURL)
      
      // Clean up the intermediate processed file
      try? FileManager.default.removeItem(at: processedVideoURL)
      
      // Verify final file exists and is readable
      guard FileManager.default.isReadableFile(atPath: finalVideoURL.path) else {
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Final processed video is not readable"])
      }
      
      // Get file size for logging
      let fileSize = try FileManager.default.attributesOfItem(atPath: finalVideoURL.path)[.size] as? Int64 ?? 0
      print("Final video size: \(fileSize) bytes")
      
      // Verify file size is not zero
      guard fileSize > 0 else {
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Processed video file is empty"])
      }
      
      // Detect aspect ratio
      let asset = AVURLAsset(url: finalVideoURL)
      let aspectRatio = try await detectVideoAspectRatio(from: asset)
      
      processingStatus = "Generating thumbnail..."
      
      // Generate thumbnail
      let thumbnailURL = try await generateThumbnail(from: finalVideoURL)
      tempURLs.insert(thumbnailURL)
      
      processingStatus = "Starting upload..."
      
      // Generate a new UUID for the video
      let videoId = UUID().uuidString
      let videoFilename = "\(videoId).mp4"
      let thumbnailFilename = "\(videoId).jpg"  // Simplified thumbnail filename
      
      // Create storage references
      let storageRef = Storage.storage().reference()
      let videosRef = storageRef.child("videos")
      let videoRef = videosRef.child(videoId).child(videoFilename)
      let thumbnailRef = videosRef.child(videoId).child(thumbnailFilename)
      
      // Upload video first to create the parent directory
      processingStatus = "Uploading video..."
      
      // Create metadata for video with additional info
      let metadata = createVideoMetadata()
      metadata.customMetadata = [
        "originalFileName": videoURL.lastPathComponent,
        "processedFileName": finalVideoURL.lastPathComponent,
        "fileSize": "\(fileSize)",
        "duration": "\(duration)",
        "aspectRatio": aspectRatio.rawValue
      ]
      
      // Upload video using putDataAsync instead of putFile
      do {
        let videoData = try Data(contentsOf: finalVideoURL)
        _ = try await videoRef.putDataAsync(videoData, metadata: metadata)
        let videoDownloadURL = try await videoRef.downloadURL()
        
        // Now upload thumbnail
        processingStatus = "Uploading thumbnail..."
        
        // Create metadata for thumbnail
        let thumbnailMetadata = createThumbnailMetadata()
        
        // Ensure thumbnail data exists and load it
        guard FileManager.default.fileExists(atPath: thumbnailURL.path),
              let thumbnailData = try? Data(contentsOf: thumbnailURL) else {
          throw NSError(domain: "", code: -1, 
            userInfo: [NSLocalizedDescriptionKey: "Thumbnail file not found or unreadable"])
        }
        
        print("[DEBUG] Uploading thumbnail from path: \(thumbnailURL.path)")
        print("[DEBUG] To storage path: \(thumbnailRef.fullPath)")
        
        // Upload thumbnail using putDataAsync
        _ = try await thumbnailRef.putDataAsync(thumbnailData, metadata: thumbnailMetadata)
        let thumbnailDownloadURL = try await thumbnailRef.downloadURL()
        
        print("[DEBUG] Thumbnail upload successful. URL: \(thumbnailDownloadURL.absoluteString)")
        
        // Save to Firestore
        processingStatus = "Saving post..."
        let db = Firestore.firestore()
        let videoDocument: [String: Any] = [
          "id": videoId,
          "creatorId": currentUser.uid,
          "videoURL": videoDownloadURL.absoluteString,
          "thumbnailURL": thumbnailDownloadURL.absoluteString,
          "caption": caption,
          "createdAt": FieldValue.serverTimestamp(),
          "likes": 0,
          "comments": 0,
          "shares": 0,
          "viewCount": 0,
          "hashtags": hashtags,
          "duration": duration,
          "fileSize": fileSize,
          "completionRate": 0.0,
          "engagementScore": 0.0,
          "aspectRatio": aspectRatio.rawValue
        ]
        
        print("[DEBUG] Creating video document with ID: \(videoId)")
        print("[DEBUG] Video document data: \(videoDocument)")
        
        try await db.collection("videos").document(videoId).setData(videoDocument)
        print("[DEBUG] Successfully created video document")
        
        // Reset state after successful upload
        await MainActor.run {
          self.isUploading = false
          self.processingStatus = ""
          self.showSuccess = true
          self.reset()
        }
      } catch {
        await MainActor.run {
          self.isUploading = false
          self.processingStatus = ""
          self.showSuccess = false
          
          // Provide more detailed error message
          if let storageError = error as? StorageError {
            switch storageError {
            case .unauthorized:
              self.errorMessage = "Permission denied: Please check your Firebase Storage rules"
            case .retryLimitExceeded:
              self.errorMessage = "Upload failed: Please check your internet connection and try again"
            case .quotaExceeded:
              self.errorMessage = "Storage quota exceeded"
            case .objectNotFound:
              self.errorMessage = "Storage path not found. Please try again."
            default:
              self.errorMessage = "Upload failed: \(error.localizedDescription)"
            }
          } else {
            self.errorMessage = "Upload failed: \(error.localizedDescription)"
          }
          
          self.showError = true
          print("Upload error: \(error)")
        }
        throw error
      }
    } catch {
      await MainActor.run {
        self.isUploading = false
        self.processingStatus = ""
        self.showSuccess = false
        
        // Provide more detailed error message
        if let storageError = error as? StorageError {
          switch storageError {
          case .unauthorized:
            self.errorMessage = "Permission denied: Please check your Firebase Storage rules"
          case .retryLimitExceeded:
            self.errorMessage = "Upload failed: Please check your internet connection and try again"
          case .quotaExceeded:
            self.errorMessage = "Storage quota exceeded"
          case .objectNotFound:
            self.errorMessage = "Storage path not found. Please try again."
          default:
            self.errorMessage = "Upload failed: \(error.localizedDescription)"
          }
        } else {
          self.errorMessage = "Upload failed: \(error.localizedDescription)"
        }
        
        self.showError = true
        print("Upload error: \(error)")
      }
      throw error
    }
  }
  
  private func trimVideoIfNeeded(_ videoURL: URL) async throws -> URL {
    guard startTime > 0 || endTime < duration else {
      return videoURL
    }
    
    let asset = AVURLAsset(url: videoURL)
    let composition = AVMutableComposition()
    
    guard let compositionTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
    }
    
    // Load video tracks
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let assetTrack = tracks.first else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
    }
    
    let timeRange = CMTimeRange(
      start: CMTime(seconds: startTime, preferredTimescale: 600),
      end: CMTime(seconds: endTime, preferredTimescale: 600)
    )
    
    try compositionTrack.insertTimeRange(
      timeRange,
      of: assetTrack,
      at: .zero
    )
    
    let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    )
    
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    
    exportSession?.outputURL = outputURL
    exportSession?.outputFileType = .mp4
    
    // Use the new states API for export progress
    if let exportSession = exportSession {
      for try await state in exportSession.states(updateInterval: 0.5) {
        if case .exporting(let progress) = state {
          processingStatus = "Processing video... \(Int(progress.fractionCompleted * 100))%"
          if progress.fractionCompleted >= 1.0 {
            processingStatus = ""
            return outputURL
          }
        }
      }
    }
    
    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed: Could not create export session"])
  }

  @MainActor private func generateThumbnail(from url: URL) async throws -> URL {
    let asset = AVURLAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    
    // Set maximum size for thumbnail
    imageGenerator.maximumSize = CGSize(width: 1280, height: 1280)
    
    // Create a unique directory for this thumbnail
    let thumbnailDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Thumbnail-\(UUID().uuidString)", isDirectory: true)
    
    // Create the directory
    try FileManager.default.createDirectory(at: thumbnailDirectory, 
        withIntermediateDirectories: true)

    // Generate unique filename for thumbnail
    let thumbnailURL = thumbnailDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")

    // Generate thumbnail from first frame
    let time = CMTime(seconds: 0, preferredTimescale: 600)
    
    do {
        let image = try await imageGenerator.image(at: time)
        let uiImage = UIImage(cgImage: image.image)
        
        guard let imageData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to create thumbnail data"])
        }

        // Write the file
        try imageData.write(to: thumbnailURL)

        // Verify the file exists and is readable
        guard FileManager.default.isReadableFile(atPath: thumbnailURL.path) else {
            throw NSError(domain: "", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Generated thumbnail is not readable"])
        }
        
        // Add URL to tempURLs for cleanup
        tempURLs.insert(thumbnailURL)
        
        return thumbnailURL
    } catch {
        print("Thumbnail generation error: \(error)")
        throw error
    }
  }

  @MainActor func cleanup() {
    // Stop and cleanup player
    if let player = player {
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
    player = nil
    playerItem = nil
    
    // Remove notification observer
    if let playerItem = playerItem {
      NotificationCenter.default.removeObserver(self, 
        name: .AVPlayerItemDidPlayToEndTime, 
        object: playerItem)
    }
    
    // Clean up temporary files
    for url in tempURLs {
      try? FileManager.default.removeItem(at: url)
    }
    tempURLs.removeAll()
  }

  func reset() {
    selectedItem = nil
    cleanup() // Call cleanup instead of just setting player to nil
    selectedVideoURL = nil
    caption = ""
    duration = 0
    startTime = 0
    endTime = 0
    isUploading = false
    uploadProgress = 0
    processingStatus = ""
  }

  deinit {
    // Since we can't use async/await in deinit, we'll do minimal cleanup
    NotificationCenter.default.removeObserver(self)
  }
}

struct VideoTransferable: Transferable {
  let videoData: Data
  
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .video) { data in
      VideoTransferable(videoData: data)
    }
  }
}

#Preview {
  VideoCreationView()
    .environmentObject(VideoCreationViewModel())
}
