import FirebaseAuth
import SwiftUI

struct SettingsView: View {
  @Environment(UserViewModel.self) private var userViewModel
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var authViewModel: AuthViewModel
  @State private var showDatingSettings = false
  @State private var showError = false
  @State private var errorMessage = ""

  var body: some View {
    NavigationView {
      List {
        // Profile Section
        Section(header: Text("Profile").textCase(.none)) {
          NavigationLink(destination: ProfileEditView()) {
            Label("Edit Profile", systemImage: "person.circle")
          }

          Toggle(
            isOn: Binding(
              get: { userViewModel.user.isPrivate },
              set: { newValue in
                userViewModel.user.isPrivate = newValue
                Task {
                  do {
                    try await userViewModel.updateUser()
                  } catch {
                    print("Error updating privacy setting: \(error)")
                    userViewModel.user.isPrivate = !newValue
                  }
                }
              }
            )
          ) {
            Label("Private Account", systemImage: "lock")
          }
        }

        // Dating Section
        Section(header: Text("Dating").textCase(.none)) {
          Toggle(
            isOn: Binding(
              get: { userViewModel.user.isDatingEnabled },
              set: { newValue in
                userViewModel.user.isDatingEnabled = newValue
                Task {
                  do {
                    try await userViewModel.updateUser()
                  } catch {
                    print("Error updating dating status: \(error)")
                    userViewModel.user.isDatingEnabled = !newValue
                  }
                }
              }
            )
          ) {
            Label("Enable Dating", systemImage: "heart")
          }

          if userViewModel.user.isDatingEnabled {
            Button(action: {
              if let userId = Auth.auth().currentUser?.uid {
                print("[DEBUG] Opening dating settings with userId: \(userId)")
                showDatingSettings = true
              } else {
                print("[ERROR] No auth user ID available")
                errorMessage = "Please sign in again to access dating settings."
                showError = true
              }
            }) {
              Label("Dating Settings", systemImage: "heart.circle")
            }
          }
        }

        // Account Section
        Section(header: Text("Account").textCase(.none)) {
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
    .sheet(isPresented: $showDatingSettings) {
      if let userId = Auth.auth().currentUser?.uid {
        NavigationStack {
          DatingSettingsView(userId: userId)
        }
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }
}

#Preview {
  SettingsView()
    .environment(UserViewModel())
    .environmentObject(AuthViewModel())
}
