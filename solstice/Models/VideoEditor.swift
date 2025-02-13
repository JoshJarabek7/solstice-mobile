@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

actor VideoEditor: @unchecked Sendable {
  private var asset: AVURLAsset?
  private var startTime: Double = 0
  private var endTime: Double = 0

  init() {}

  init(url: URL) async throws {
    self.asset = AVURLAsset(url: url)
    _ = try await asset?.load(.tracks)
  }

  func setTrimPoints(start: Double, end: Double) {
    self.startTime = start
    self.endTime = end
  }

  func processVideo(url: URL, startTime: Double, endTime: Double, quality: VideoQuality)
    async throws -> URL
  {
    // Create asset from video URL
    let asset = AVURLAsset(url: url)

    // Set up export parameters
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")

    let timeRange = CMTimeRange(
      start: CMTime(seconds: startTime, preferredTimescale: 600),
      end: CMTime(seconds: endTime, preferredTimescale: 600)
    )

    // Create new composition
    let composition = AVMutableComposition()

    // Add video track
    guard
      let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw VideoError.exportFailed("Failed to create video composition track")
    }

    // Get video track
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
      throw VideoError.exportFailed("No video track found")
    }

    // Add video segment to composition
    try compositionVideoTrack.insertTimeRange(
      timeRange,
      of: videoTrack,
      at: .zero
    )

    // Handle audio track if present
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    if let audioTrack = audioTracks.first,
      let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    {
      // Add audio segment to composition
      try compositionAudioTrack.insertTimeRange(
        timeRange,
        of: audioTrack,
        at: .zero
      )
    }

    // Create export session with HEVC preset
    guard
      let exportSession = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetHEVCHighestQuality
      )
    else {
      throw VideoError.exportFailed("Failed to create export session")
    }

    // Configure export session
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true

    // Export using new iOS 18 API
    if #available(iOS 18.0, *) {
      do {
        try await exportSession.export(to: outputURL, as: .mp4)
        return outputURL
      } catch {
        throw VideoError.exportFailed(error.localizedDescription)
      }
    } else {
      // For iOS 17 and earlier
      exportSession.timeRange = timeRange

      // Monitor export progress
      for try await state in exportSession.states(updateInterval: 0.5) {
        if case .exporting(let progress) = state {
          print("Export progress: \(Int(progress.fractionCompleted * 100))%")
        }
      }

      // Check if file exists at output URL
      guard FileManager.default.fileExists(atPath: outputURL.path) else {
        throw VideoError.exportFailed("Export failed - no output file found")
      }

      return outputURL
    }
  }

  private func getPresetName(for quality: VideoQuality) -> String {
    // Always use highest quality HEVC
    return AVAssetExportPresetHEVCHighestQuality
  }
}

enum VideoError: LocalizedError {
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .exportFailed(let message):
      return "Failed to export video: \(message)"
    }
  }
}
