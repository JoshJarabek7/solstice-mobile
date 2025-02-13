import PhotosUI
import SwiftUI

struct ProfileEditView: View {
  @Bindable var userViewModel: UserViewModel
  @State private var selectedItem: PhotosPickerItem?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section("Profile Photo") {
        HStack {
          if let profileImageURL = userViewModel.user.profileImageURL {
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
        }
      }

      Section("Basic Information") {
        TextField("Full Name", text: $userViewModel.user.fullName)
        TextField("Username", text: $userViewModel.user.username)
        TextField(
          "Bio",
          text: Binding(
            get: { userViewModel.user.bio ?? "" },
            set: { userViewModel.user.bio = $0.isEmpty ? nil : $0 }
          ))
      }
    }
    .navigationTitle("Edit Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Save") {
          Task {
            do {
              try await userViewModel.updateUser()
              dismiss()
            } catch {
              print("Error saving profile: \(error)")
            }
          }
        }
      }
    }
    .onChange(of: selectedItem) { oldValue, newValue in
      guard let item = newValue else { return }
      Task {
        do {
          if let data = try await item.loadTransferable(type: Data.self) {
            let url = try await userViewModel.uploadDatingPhoto(imageData: data)
            userViewModel.user.profileImageURL = url
            try await userViewModel.updateUser()
          }
        } catch {
          print("Error updating profile photo: \(error)")
        }
        selectedItem = nil
      }
    }
  }
}

#Preview {
  NavigationView {
    ProfileEditView(userViewModel: UserViewModel())
  }
}
