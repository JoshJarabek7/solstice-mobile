import SwiftUI
import FirebaseStorage
import AVFoundation

struct VideoShareSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var showNewMessageSheet = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    
    var body: some View {
        NavigationView {
            List {
                // Direct Message Option
                Button {
                    showNewMessageSheet = true
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("Send in Direct Message")
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 8)
                }
                
                // Download Video Option
                Button {
                    downloadVideo()
                } label: {
                    HStack {
                        if isDownloading {
                            ProgressView(value: downloadProgress)
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        Text("Download Video")
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 8)
                }
                .disabled(isDownloading)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showNewMessageSheet) {
            NewMessageView(videoToShare: video)
        }
    }
    
    private func downloadVideo() {
        guard let videoURL = video.videoURL else { return }
        
        isDownloading = true
        
        // Create a reference to the video in Firebase Storage
        let storage = Storage.storage()
        let videoRef = storage.reference(forURL: videoURL)
        
        // Create a temporary local URL for the downloaded video
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationUrl = documentsPath.appendingPathComponent("\(UUID().uuidString).mp4")
        
        // Download the video with progress tracking
        let downloadTask = videoRef.write(toFile: destinationUrl) { url, error in
            isDownloading = false
            
            if let error = error {
                print("Error downloading video: \(error.localizedDescription)")
                return
            }
            
            guard let localUrl = url else { return }
            
            // Save video to camera roll
            UISaveVideoAtPathToSavedPhotosAlbum(
                localUrl.path,
                nil,
                nil,
                nil
            )
            
            // Clean up the temporary file
            try? FileManager.default.removeItem(at: localUrl)
            
            dismiss()
        }
        
        // Track download progress
        downloadTask.observe(.progress) { snapshot in
            if let progress = snapshot.progress {
                downloadProgress = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
            }
        }
    }
}

#Preview {
    VideoShareSheet(video: Video(
        id: "preview",
        creatorId: "user1",
        caption: "Test video",
        videoURL: "https://example.com/video.mp4",
        thumbnailURL: "https://example.com/thumbnail.jpg",
        duration: 30,
        hashtags: ["test"]
    ))
} 