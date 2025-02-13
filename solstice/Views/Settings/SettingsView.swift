import FirebaseAuth
import SwiftUI

struct SettingsView: View {
  @Bindable var userViewModel: UserViewModel
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var authViewModel: AuthViewModel

  var body: some View {
    NavigationView {
      List {
        Section("Profile") {
          NavigationLink(destination: ProfileEditView(userViewModel: userViewModel)) {
            Label("Edit Profile", systemImage: "person.circle")
          }

          Toggle(isOn: $userViewModel.user.isPrivate) {
            Label("Private Account", systemImage: "lock")
          }
          .onChange(of: userViewModel.user.isPrivate) { oldValue, newValue in
            Task {
              do {
                try await userViewModel.updateUser()
              } catch {
                print("Error updating privacy setting: \(error)")
                userViewModel.user.isPrivate = oldValue
              }
            }
          }
        }

        Section("Dating") {
          Toggle(isOn: $userViewModel.user.isDatingEnabled) {
            Label("Enable Dating", systemImage: "heart")
          }
          .onChange(of: userViewModel.user.isDatingEnabled) { oldValue, newValue in
            Task {
              do {
                try await userViewModel.updateUser()
              } catch {
                print("Error updating dating status: \(error)")
                userViewModel.user.isDatingEnabled = oldValue
              }
            }
          }

          if userViewModel.user.isDatingEnabled {
            NavigationLink(
              destination: DatingSettingsView(viewModel: userViewModel)
            ) {
              Label("Dating Settings", systemImage: "heart.circle")
            }
          }
        }

        Section("Account") {
          Button(role: .destructive) {
            Task {
              // Sign out through AuthViewModel first
              try? await authViewModel.signOut()
              // Then clean up UserViewModel
              await userViewModel.signOut()
              // Dismiss the settings view
              dismiss()
            }
          } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              .foregroundColor(.red)
          }
        }
      }
      .navigationTitle("Settings")
    }
    .environmentObject(authViewModel)
  }
}

#Preview {
  SettingsView(userViewModel: UserViewModel())
}
