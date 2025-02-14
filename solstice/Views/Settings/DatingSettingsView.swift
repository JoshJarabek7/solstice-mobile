/// DatingSettingsView.swift

import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

extension UTType {
  static let photoIndex = UTType(exportedAs: "com.solstice.photoindex")
}

/// Transferable object for drag-and-drop reordering of photos.
struct DragPhotoItem: Transferable, Codable {
  let index: Int
  let url: String
  
  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .photoIndex)
  }
}

struct DatingSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserViewModel.self) private var userViewModel
  let userId: String
  
  @State private var showDeactivateConfirmation = false
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var showAlert = false
  @State private var alertType: DatingAlertType = .error("")
  @State private var isSaving = false
  @State private var selectedPhotoIndex: Int? = nil
  @State private var showPhotoOptions = false
  
  private enum DatingAlertType {
    case error(String)
    case deactivateConfirmation
    
    var title: String {
      switch self {
      case .error:
        return "Error"
      case .deactivateConfirmation:
        return "Deactivate Dating?"
      }
    }
    
    var message: String {
      switch self {
      case .error(let message):
        return message
      case .deactivateConfirmation:
        return "This will hide your dating profile and delete all your dating matches. This action cannot be undone."
      }
    }
  }
  
  var body: some View {
    Form {
      // Dating Active toggle
      Section("Dating Profile") {
        Toggle("Dating Active", isOn: Binding(
          get: { userViewModel.user.isDatingEnabled },
          set: { newValue in
            if !newValue {
              alertType = .deactivateConfirmation
              showAlert = true
            } else {
              updateDatingStatus(true)
            }
          }
        ))
      }
      
      // Only show these sections if user is dating-enabled
      if userViewModel.user.isDatingEnabled {
        Section("Photos") {
          photosSection
        }
        
        Section("Basic Information") {
          Picker("Gender", selection: Binding(
            get: { userViewModel.user.gender },
            set: { newValue in
              updateUserField(\.gender, newValue)
            }
          )) {
            ForEach(User.Gender.allCases) { gender in
              Text(gender.rawValue.capitalized).tag(gender)
            }
          }
          
          TextField(
            "Bio",
            text: Binding(
              get: { userViewModel.user.bio ?? "" },
              set: { newValue in
                let oldValue = userViewModel.user.bio
                userViewModel.user.bio = newValue.isEmpty ? nil : newValue
                Task {
                  do {
                    try await userViewModel.updateUser()
                  } catch {
                    print("Error updating bio: \(error)")
                    userViewModel.user.bio = oldValue
                  }
                }
              }
            ),
            axis: .vertical
          )
          .lineLimit(3...6)
          .textFieldStyle(.roundedBorder)
        }
      }
    }
    .navigationTitle("Dating Profile")
    .navigationBarTitleDisplayMode(.inline)
    .alert(alertType.title, isPresented: $showAlert) {
      switch alertType {
      case .error:
        Button("OK", role: .cancel) {}
      case .deactivateConfirmation:
        Button("Cancel", role: .cancel) {
          // Revert toggle if user cancels
          userViewModel.user.isDatingEnabled = true
        }
        Button("Deactivate", role: .destructive) {
          Task {
            await deactivateDating()
          }
        }
      }
    } message: {
      Text(alertType.message)
    }
  }
  
  // MARK: - Photos Section

  private var photosSection: some View {
    ScrollView {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(userViewModel.user.datingImages.enumerated()), id: \.offset) { index, photoURL in
                GeometryReader { geometry in
                    AsyncImage(url: URL(string: photoURL)) { phase in
                        if let image = phase.image {
                            Button {
                                selectedPhotoIndex = index
                                showPhotoOptions = true
                            } label: {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.width * 1.3)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedPhotoIndex == index ? Color.blue : Color.gray.opacity(0.3), lineWidth: selectedPhotoIndex == index ? 2 : 1)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id("photo_\(photoURL)")
                            .transition(.opacity.combined(with: .scale))
                            .animation(.spring(duration: 0.3), value: index)
                            .confirmationDialog("Photo Options", isPresented: $showPhotoOptions, presenting: selectedPhotoIndex) { index in
                                if index > 0 {
                                    Button("Move Left") {
                                        movePhoto(from: index, to: index - 1)
                                    }
                                }
                                
                                if index < userViewModel.user.datingImages.count - 1 {
                                    Button("Move Right") {
                                        movePhoto(from: index, to: index + 1)
                                    }
                                }
                                
                                Button("Delete", role: .destructive) {
                                    deletePhoto(at: index)
                                    selectedPhotoIndex = nil
                                }
                                
                                Button("Cancel", role: .cancel) {
                                    selectedPhotoIndex = nil
                                }
                            } message: { _ in
                                Text("What would you like to do with this photo?")
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.3)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    if phase.error != nil {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.gray)
                                    } else {
                                        ProgressView()
                                    }
                                }
                        }
                    }
                }
                .aspectRatio(1/1.3, contentMode: .fit)
            }
            
            if userViewModel.user.datingImages.count < 5 {
                GeometryReader { geometry in
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 5 - userViewModel.user.datingImages.count,
                        matching: .images
                    ) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.blue)
                            Text("Add Photo")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.width * 1.3)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .aspectRatio(1/1.3, contentMode: .fit)
                .transition(.opacity.combined(with: .scale))
                .onChange(of: selectedPhotos) { _, newItems in
                    Task {
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               !data.isEmpty {
                                do {
                                    let url = try await userViewModel.uploadDatingPhoto(imageData: data)
                                    withAnimation(.spring(duration: 0.3)) {
                                        userViewModel.user.datingImages.append(url)
                                    }
                                    try await userViewModel.updateUser()
                                } catch {
                                    print("Error uploading new photo: \(error)")
                                    showError("Could not upload photo. Please try again.")
                                }
                            }
                        }
                        selectedPhotos.removeAll()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
  }
  
  // MARK: - Helper Functions

  private func movePhoto(from: Int, to: Int) {
    guard from != to,
          from >= 0, to >= 0,
          from < userViewModel.user.datingImages.count,
          to < userViewModel.user.datingImages.count else { return }
    
    let oldImages = userViewModel.user.datingImages
    var updated = oldImages
    let movedItem = updated.remove(at: from)
    
    withAnimation(.spring(duration: 0.3)) {
        updated.insert(movedItem, at: to)
        userViewModel.user.datingImages = updated
        selectedPhotoIndex = to // Update selection to follow the moved photo
    }
    
    Task {
      do {
        try await userViewModel.updateUser()
      } catch {
        withAnimation(.spring(duration: 0.3)) {
            userViewModel.user.datingImages = oldImages
            selectedPhotoIndex = from // Restore selection on error
        }
        print("Error moving photo: \(error)")
      }
    }
  }

  private func deletePhoto(at index: Int) {
    guard index < userViewModel.user.datingImages.count else { return }
    let oldImages = userViewModel.user.datingImages
    var updated = oldImages
    
    withAnimation(.spring(duration: 0.3)) {
        updated.remove(at: index)
        userViewModel.user.datingImages = updated
    }
    
    Task {
      do {
        try await userViewModel.updateUser()
      } catch {
        withAnimation(.spring(duration: 0.3)) {
            userViewModel.user.datingImages = oldImages
        }
        print("Error deleting photo: \(error)")
      }
    }
  }

  private func updateUserField<T>(_ keyPath: WritableKeyPath<User, T>, _ value: T) {
    var updatedUser = userViewModel.user
    updatedUser[keyPath: keyPath] = value
    userViewModel.user = updatedUser
    
    Task {
      do {
        try await userViewModel.updateUser()
      } catch {
        print("[ERROR] Failed to update user field: \(error)")
        showError("Failed to save changes. Please try again.")
      }
    }
  }

  private func deactivateDating() async {
    do {
      var updatedUser = userViewModel.user
      updatedUser.isDatingEnabled = false
      userViewModel.user = updatedUser
      try await userViewModel.updateUser()
      dismiss()
    } catch {
      print("[ERROR] Failed to deactivate dating: \(error)")
      await MainActor.run {
        showError("Failed to deactivate dating. Please try again.")
      }
    }
  }

  private func updateDatingStatus(_ isEnabled: Bool) {
    Task {
      do {
        var updatedUser = userViewModel.user
        updatedUser.isDatingEnabled = isEnabled
        userViewModel.user = updatedUser
        try await userViewModel.updateUser()
      } catch {
        print("[ERROR] Failed to update dating status: \(error)")
        showError("Failed to update dating status. Please try again.")
      }
    }
  }
  
  private func showError(_ message: String) {
    alertType = .error(message)
    showAlert = true
  }
}

// MARK: - Preview
#Preview {
  NavigationView {
    DatingSettingsView(userId: "")
      .environment(UserViewModel())
  }
}