import AVKit
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct VideoCreationView: View {
  @StateObject private var viewModel = VideoCreationViewModel()
  @FocusState private var isCaptionFocused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground)
          .ignoresSafeArea()

        if let player = viewModel.player {
          ScrollView {
            VStack(spacing: 16) {
              // Video Preview
              AVKit.VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.height * 0.5)
                .cornerRadius(12)
                .shadow(radius: 8)

              // Video Trimmer
              if viewModel.duration > 0 {
                VideoTrimmer(
                  duration: viewModel.duration,
                  startTime: $viewModel.startTime,
                  endTime: $viewModel.endTime
                )
                .padding(.horizontal)

                Text("Trim your video")
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }

              // Caption
              TextField("Write a caption...", text: $viewModel.caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(height: 80)
                .padding(.horizontal)
                .focused($isCaptionFocused)

              Spacer()

              // Upload Progress
              if viewModel.isUploading {
                VStack(spacing: 8) {
                  ProgressView(value: viewModel.uploadProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal)

                  Text(viewModel.processingStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
              }

              // Post Button
              Button {
                Task {
                  do {
                    try await viewModel.uploadVideo()
                  } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                  }
                }
              } label: {
                Text(viewModel.isUploading ? "Uploading..." : "Post")
                  .font(.headline)
                  .foregroundColor(.white)
                  .frame(maxWidth: .infinity)
                  .frame(height: 50)
                  .background(viewModel.isUploading ? Color.gray : Color.blue)
                  .cornerRadius(25)
                  .padding(.horizontal)
              }
              .disabled(viewModel.isUploading)
              .padding(.bottom, 30)
            }
          }
          .scrollDismissesKeyboard(.immediately)
          .onTapGesture {
            isCaptionFocused = false
          }

        } else {
          // Video Selection
          PhotosPicker(
            selection: $viewModel.selectedItem,
            matching: .videos,
            photoLibrary: .shared()
          ) {
            VStack(spacing: 12) {
              Image(systemName: "video.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.blue)

              Text("Select a video to share")
                .font(.headline)

              Text("Videos can be up to 2 minutes long")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("New Video")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .keyboard) {
          Button("Done") {
            isCaptionFocused = false
          }
        }
      }
      .alert("Error", isPresented: $viewModel.showError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(viewModel.errorMessage)
      }
      .alert("Success", isPresented: $viewModel.showSuccess) {
        Button("OK") {
          dismiss()
        }
      } message: {
        Text("Your video has been posted!")
      }
      .onDisappear {
        viewModel.cleanup()
      }
    }
  }
}

#Preview {
  VideoCreationView()
}
