import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

struct DatingSettingsView: View {
  @Environment(UserViewModel.self) private var viewModel
  @State private var showDeactivateConfirmation = false
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var showBirthdayPicker = false
  @State private var selectedDate = Date()
  @State private var showError = false
  @State private var errorMessage = ""

  var body: some View {
    List {
      enableDatingToggleSection

      if viewModel.user.isDatingEnabled {
        basicInformationSection
        datingPhotosSection
      }
    }
    .navigationTitle("Dating Profile")
    .onChange(of: selectedPhotos) { oldValue, newValue in
      handlePhotoSelection(newValue)
    }
    .alert("Deactivate Dating?", isPresented: $showDeactivateConfirmation) {
      Button("Cancel", role: .cancel) {
        viewModel.user.isDatingEnabled = true
      }

      Button("Deactivate", role: .destructive) {
        Task {
          await viewModel.deactivateDating()
        }
      }
    } message: {
      Text(
        "This will hide your dating profile and delete all your dating matches. This action cannot be undone."
      )
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
    .sheet(isPresented: $showBirthdayPicker) {
      NavigationStack {
        birthdayPickerView
      }
      .presentationDetents([.medium])
    }
  }

  private var enableDatingToggleSection: some View {
    Section {
      Toggle("Dating Active", isOn: Binding(
        get: { viewModel.user.isDatingEnabled },
        set: { newValue in
          viewModel.user.isDatingEnabled = newValue
          if newValue {
            // Check if birthday is set
            if viewModel.user.birthday == nil {
              // Show birthday picker
              showBirthdayPicker = true
              // Revert toggle until birthday is set
              viewModel.user.isDatingEnabled = false
            }
          } else {
            showDeactivateConfirmation = true
          }
        }
      ))
    } footer: {
      if viewModel.user.birthday == nil {
        Text("You must set your birthday to enable dating.")
      } else {
        Text(
          "When dating is deactivated, your profile will be hidden from other users and all your dating matches will be deleted."
        )
      }
    }
  }

  private var birthdayPickerView: some View {
    VStack {
      DatePicker(
        "Birthday",
        selection: $selectedDate,
        in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
        displayedComponents: .date
      )
      .datePickerStyle(.wheel)
      .padding()

      Button("Set Birthday") {
        Task {
          do {
            viewModel.user.birthday = selectedDate
            try await viewModel.updateUser()
            showBirthdayPicker = false
            // Now enable dating
            viewModel.user.isDatingEnabled = true
            try await viewModel.updateUser()
          } catch {
            errorMessage = error.localizedDescription
            showError = true
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .padding()
    }
    .navigationTitle("Set Birthday")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Button("Cancel") {
          showBirthdayPicker = false
        }
      }
    }
  }

  private var basicInformationSection: some View {
    Section("Basic Information") {
      if let birthday = viewModel.user.birthday {
        HStack {
          Label("Birthday", systemImage: "calendar")
          Spacer()
          Text(birthday, style: .date)
            .foregroundColor(.gray)
        }
      }
      
      Picker("Gender", selection: Binding(
        get: { viewModel.user.gender },
        set: { newValue in
          let oldValue = viewModel.user.gender
          viewModel.user.gender = newValue
          Task {
            do {
              try await viewModel.updateUser()
            } catch {
              print("Error updating gender: \(error)")
              viewModel.user.gender = oldValue
            }
          }
        }
      )) {
        ForEach(User.Gender.allCases, id: \.self) { gender in
          Text(gender.rawValue.capitalized).tag(gender)
        }
      }
      
      TextField(
        "Bio",
        text: Binding(
          get: { viewModel.user.bio ?? "" },
          set: { newValue in
            let oldValue = viewModel.user.bio
            viewModel.user.bio = newValue.isEmpty ? nil : newValue
            Task {
              do {
                try await viewModel.updateUser()
              } catch {
                print("Error updating bio: \(error)")
                viewModel.user.bio = oldValue
              }
            }
          }
        )
      )
      .textFieldStyle(.roundedBorder)
    }
  }

  private var datingPhotosSection: some View {
    Section("Dating Photos") {
      ScrollView(.horizontal) {
        HStack {
          ForEach(viewModel.user.datingImages, id: \.self) { photoURL in
            datingPhotoView(for: photoURL)
          }
          addPhotoButton
        }
        .padding(.vertical)
      }
    }
  }

  private func datingPhotoView(for photoURL: String) -> some View {
    AsyncImage(url: URL(string: photoURL)) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      ProgressView()
    }
    .frame(width: 100, height: 100)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(alignment: .topTrailing) {
      deletePhotoButton(for: photoURL)
    }
  }

  private func deletePhotoButton(for photoURL: String) -> some View {
    Button {
      if let index = viewModel.user.datingImages.firstIndex(of: photoURL) {
        let oldPhotos = viewModel.user.datingImages
        viewModel.user.datingImages.remove(at: index)
        Task {
          do {
            try await viewModel.updateUser()
          } catch {
            print("Error deleting photo: \(error)")
            viewModel.user.datingImages = oldPhotos
          }
        }
      }
    } label: {
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.white, .black)
        .background(Circle().fill(.white))
    }
    .padding(4)
  }

  private var addPhotoButton: some View {
    Group {
      if viewModel.user.datingImages.count < 5 {
        PhotosPicker(
          selection: $selectedPhotos,
          maxSelectionCount: 5 - viewModel.user.datingImages.count,
          matching: .images
        ) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 30))
            .foregroundColor(.blue)
            .frame(width: 100, height: 100)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
      }
    }
  }

  private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
    Task {
      do {
        for item in items {
          if let data = try await item.loadTransferable(type: Data.self) {
            let url = try await viewModel.uploadDatingPhoto(imageData: data)
            viewModel.user.datingImages.append(url)
            try await viewModel.updateUser()
          }
        }
      } catch {
        print("Error handling photo selection: \(error)")
      }
      selectedPhotos.removeAll()
    }
  }
}

struct MultipleSelectionList<T: Hashable & Identifiable>: View {
  let title: String
  let options: [T]
  let selected: Set<T>
  let onSelectionChanged: (Set<T>) -> Void
  @State private var selectedItems: Set<T>
  @Environment(\.dismiss) private var dismiss

  init(
    title: String, options: [T], selected: Set<T>,
    onSelectionChanged: @escaping (Set<T>) -> Void
  ) {
    self.title = title
    self.options = options
    self.selected = selected
    self.onSelectionChanged = onSelectionChanged
    _selectedItems = State(initialValue: selected)
  }

  var body: some View {
    List(options) { option in
      Button {
        if selectedItems.contains(option) {
          selectedItems.remove(option)
        } else {
          selectedItems.insert(option)
        }
      } label: {
        HStack {
          if let gender = option as? User.Gender {
            Text(gender.rawValue.capitalized)
          }
          Spacer()
          if selectedItems.contains(option) {
            Image(systemName: "checkmark")
              .foregroundColor(.blue)
          }
        }
      }
      .foregroundColor(.primary)
    }
    .navigationTitle(title)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Done") {
          onSelectionChanged(selectedItems)
          dismiss()
        }
      }
    }
  }
}

#Preview {
  NavigationView {
    DatingSettingsView()
      .environment(UserViewModel())
  }
}
