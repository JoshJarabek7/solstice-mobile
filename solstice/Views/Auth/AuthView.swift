import SwiftUI

struct AuthView: View {
  @State private var isLogin = true
  @EnvironmentObject var authViewModel: AuthViewModel

  var body: some View {
    NavigationView {
      ScrollView {
        VStack {
          // Logo and app name
          VStack(spacing: 20) {
            Image(systemName: "sparkles")
              .font(.system(size: 80))
              .foregroundColor(.purple)

            Text("Solstice")
              .font(.largeTitle)
              .fontWeight(.bold)
          }
          .padding(.vertical, 40)

          // Auth form
          if isLogin {
            LoginView()
          } else {
            SignUpView()
          }

          // Toggle between login and signup
          Button(action: {
            withAnimation {
              isLogin.toggle()
            }
          }) {
            Text(isLogin ? "New to Solstice? Sign Up" : "Already have an account? Sign In")
              .foregroundColor(.purple)
          }
          .padding()
        }
        .padding()
      }
      .scrollDismissesKeyboard(.immediately)
    }
  }
}

struct LoginView: View {
  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage = ""
  @EnvironmentObject var authViewModel: AuthViewModel

  var body: some View {
    VStack(spacing: 20) {
      TextField("Email", text: $email)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .textInputAutocapitalization(.never)

      SecureField("Password", text: $password)
        .textFieldStyle(RoundedBorderTextFieldStyle())

      if !errorMessage.isEmpty {
        Text(errorMessage)
          .foregroundColor(.red)
          .font(.caption)
      }

      Button(action: {
        Task {
          do {
            try await authViewModel.signIn(withEmail: email, password: password)
          } catch {
            errorMessage = error.localizedDescription
          }
        }
      }) {
        Text("Sign In")
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.purple)
          .cornerRadius(10)
      }
    }
  }
}

struct SignUpView: View {
  @State private var email = ""
  @State private var password = ""
  @State private var username = ""
  @State private var fullName = ""
  @State private var errorMessage = ""
  @State private var showError = false
  @EnvironmentObject var authViewModel: AuthViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 20) {
      TextField("Email", text: $email)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled()
        .disabled(authViewModel.isLoading)

      TextField("Username", text: $username)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(authViewModel.isLoading)

      TextField("Full Name", text: $fullName)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .disabled(authViewModel.isLoading)

      SecureField("Password", text: $password)
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .disabled(authViewModel.isLoading)

      if !errorMessage.isEmpty {
        Text(errorMessage)
          .foregroundColor(.red)
          .font(.caption)
          .multilineTextAlignment(.center)
      }

      Button(action: {
        Task {
          do {
            try await authViewModel.createUser(
              email: email.trimmingCharacters(in: .whitespacesAndNewlines),
              password: password,
              username: username.trimmingCharacters(in: .whitespacesAndNewlines),
              fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
          } catch {
            errorMessage = error.localizedDescription
            showError = true
          }
        }
      }) {
        if authViewModel.isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
        } else {
          Text("Sign Up")
        }
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color.purple)
      .cornerRadius(10)
      .disabled(authViewModel.isLoading)
      .opacity(authViewModel.isLoading ? 0.7 : 1)

      if authViewModel.isLoading {
        Text("Creating your account...")
          .foregroundColor(.secondary)
          .font(.caption)
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {
        errorMessage = ""
      }
    } message: {
      Text(errorMessage)
    }
  }
}
