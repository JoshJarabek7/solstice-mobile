import PhotosUI
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ProfileEditView: View {
  @Environment(UserViewModel.self) private var userViewModel
  @State private var selectedItem: PhotosPickerItem?
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var localUser: LocalUserData
  @State private var showBirthdayPicker = false
  @Environment(\.dismiss) private var dismiss

  // Separate struct for local edits to prevent User struct comparison issues
  private struct LocalUserData {
    var fullName: String = ""
    var username: String = ""
    var bio: String = ""
    var profileImageURL: String?
    
    init(from user: User) {
      self.fullName = user.fullName
      self.username = user.username
      self.bio = user.bio ?? ""
      self.profileImageURL = user.profileImageURL
    }
  }

  init() {
    // Initialize with empty data - will be updated in onAppear
    _localUser = State(initialValue: LocalUserData(from: User(username: "", email: "", fullName: "", gender: .other)))
  }

  var body: some View {
    Form {
      ProfilePhotoSection(
        profileImageURL: localUser.profileImageURL,
        selectedItem: $selectedItem,
        onPhotoUpdate: handlePhotoUpdate
      )

      Section("Basic Information") {
        TextField("Full Name", text: $localUser.fullName)
        TextField("Username", text: $localUser.username)
        TextField("Bio", text: $localUser.bio)

        if let birthday = userViewModel.user.birthday {
          HStack {
            Text("Birthday")
            Spacer()
            Text(birthday, style: .date)
              .foregroundColor(.gray)
          }
        } else {
          Button(action: {
            if let userId = Auth.auth().currentUser?.uid {
              print("[DEBUG] Opening birthday picker with userId: \(userId)")
              showBirthdayPicker = true
            } else {
              print("[ERROR] No auth user ID available")
              errorMessage = "Please sign in again to set your birthday."
              showError = true
            }
          }) {
            HStack {
              Text("Set Birthday")
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundColor(.gray)
            }
          }
          .foregroundColor(.blue)
        }
      }
    }
    .navigationTitle("Edit Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Save") {
          saveProfile()
        }
      }
    }
    .onAppear {
      localUser = LocalUserData(from: userViewModel.user)
    }
    .sheet(isPresented: $showBirthdayPicker) {
      if let userId = Auth.auth().currentUser?.uid {
        NavigationStack {
          BirthdaySettingView(userId: userId, onSave: { date in
            Task {
              print("[DEBUG] Birthday saved, updating user model")
              var updatedUser = userViewModel.user
              updatedUser.birthday = date
              userViewModel.user = updatedUser
              do {
                try await userViewModel.updateUser()
                print("[DEBUG] User model updated successfully")
              } catch {
                print("[ERROR] Failed to update user model: \(error)")
                errorMessage = "Birthday saved but profile update failed. Please try again."
                showError = true
              }
            }
          })
        }
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func handlePhotoUpdate(_ data: Data) {
    Task {
      do {
        let url = try await userViewModel.uploadDatingPhoto(imageData: data)
        await MainActor.run {
          localUser.profileImageURL = url
        }
      } catch {
        await MainActor.run {
          errorMessage = "Error updating profile photo: \(error.localizedDescription)"
          showError = true
        }
      }
    }
  }

  private func saveProfile() {
    Task {
      do {
        // Update only the editable fields
        var updatedUser = userViewModel.user
        updatedUser.fullName = localUser.fullName
        updatedUser.username = localUser.username
        updatedUser.bio = localUser.bio.isEmpty ? nil : localUser.bio
        updatedUser.profileImageURL = localUser.profileImageURL
        
        // Update the UserViewModel
        userViewModel.user = updatedUser
        try await userViewModel.updateUser()
        dismiss()
      } catch {
        errorMessage = "Error saving profile: \(error.localizedDescription)"
        showError = true
      }
    }
  }
}

private struct BirthdaySettingView: View {
  @Environment(\.dismiss) private var dismiss
  let userId: String
  let onSave: (Date) -> Void
  
  @State private var selectedDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var isSaving = false
  
  var body: some View {
    VStack(spacing: 20) {
      DatePicker(
        "Birthday",
        selection: $selectedDate,
        in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
        displayedComponents: .date
      )
      .datePickerStyle(.wheel)
      .padding()
      
      if isSaving {
        ProgressView()
          .padding()
      }
      
      Button(action: saveDate) {
        Text("Save")
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(10)
      }
      .disabled(isSaving)
      .padding(.horizontal)
      
      Spacer()
    }
    .navigationTitle("Set Birthday")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }
  
  private func saveDate() {
    guard !isSaving else { return }
    guard !userId.isEmpty else {
      errorMessage = "Unable to save birthday. Please try again."
      showError = true
      return
    }
    
    isSaving = true
    
    Task {
      do {
        let data: [String: Any] = [
          "birthday": Timestamp(date: selectedDate)
        ]
        
        try await Firestore.firestore()
          .collection("users")
          .document(userId)
          .updateData(data)
        
        await MainActor.run {
          onSave(selectedDate)
          dismiss()
        }
      } catch {
        print("[ERROR] BirthdaySettingView - Save failed: \(error)")
        await MainActor.run {
          isSaving = false
          errorMessage = "Failed to save birthday: \(error.localizedDescription)"
          showError = true
        }
      }
    }
  }
}

private struct ProfilePhotoSection: View {
  let profileImageURL: String?
  @Binding var selectedItem: PhotosPickerItem?
  let onPhotoUpdate: (Data) -> Void

  var body: some View {
    Section("Profile Photo") {
      HStack {
        if let profileImageURL = profileImageURL {
          AsyncImage(url: URL(string: profileImageURL)) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            ProgressView()
          }
          .frame(width: 80, height: 80)
          .clipShape(Circle())
        } else {
          Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 80, height: 80)
            .foregroundColor(.gray)
        }

        PhotosPicker(
          selection: $selectedItem,
          matching: .images
        ) {
          Text("Change Photo")
            .foregroundColor(.blue)
        }
        .onChange(of: selectedItem) { _, newValue in
          guard let item = newValue else { return }
          Task {
            if let data = try await item.loadTransferable(type: Data.self) {
              onPhotoUpdate(data)
            }
          }
          selectedItem = nil
        }
      }
    }
  }
}

#Preview {
  NavigationView {
    ProfileEditView()
      .environment(UserViewModel())
  }
}
