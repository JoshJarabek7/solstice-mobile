import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

struct DatingSettingsView: View {
  @Bindable private var viewModel: UserViewModel
  @State private var showDeactivateConfirmation = false
  @State private var selectedPhotos: [PhotosPickerItem] = []

  init(viewModel: UserViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    List {
      enableDatingToggleSection

      if viewModel.user.isDatingEnabled {
        basicInformationSection
        datingPreferencesSection
        datingPhotosSection
      }
    }
    .navigationTitle("Dating Settings")
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
  }

  private var enableDatingToggleSection: some View {
    Section {
      Toggle("Dating Active", isOn: $viewModel.user.isDatingEnabled)
        .onChange(of: viewModel.user.isDatingEnabled) { _, newValue in
          if !newValue {
            showDeactivateConfirmation = true
          }
        }
    } footer: {
      Text(
        "When dating is deactivated, your profile will be hidden from other users and all your dating matches will be deleted."
      )
    }
  }

  private var basicInformationSection: some View {
    Section("Basic Information") {
      genderPicker
      bioTextField
    }
  }

  private var genderPicker: some View {
    Picker("Gender", selection: $viewModel.user.gender) {
      ForEach(User.Gender.allCases, id: \.self) { gender in
        Text(gender.rawValue.capitalized).tag(gender)
      }
    }
    .onChange(of: viewModel.user.gender) { oldValue, newValue in
      Task {
        do {
          try await viewModel.updateUser()
        } catch {
          print("Error updating gender: \(error)")
          viewModel.user.gender = oldValue
        }
      }
    }
  }

  private var bioTextField: some View {
    Group {
      TextField(
        "Bio",
        text: Binding(
          get: { self.viewModel.user.bio ?? "" },
          set: { self.viewModel.user.bio = $0 }
        )
      )
      .textFieldStyle(.roundedBorder)
      .onChange(of: viewModel.user.bio) { oldValue, newValue in
        Task {
          do {
            try await viewModel.updateUser()
          } catch {
            print("Error updating bio: \(error)")
            viewModel.user.bio = oldValue
          }
        }
      }
    }
  }

  private var datingPreferencesSection: some View {
    Section("Dating Preferences") {
      interestedInLink
      distancePreference
    }
  }

  private var interestedInLink: some View {
    NavigationLink {
      MultipleSelectionList(
        title: "Interested In",
        options: User.Gender.allCases,
        selected: Set(viewModel.user.interestedIn),
        onSelectionChanged: { selected in
          let oldValue = viewModel.user.interestedIn
          viewModel.user.interestedIn = Array(selected)
          Task {
            do {
              try await viewModel.updateUser()
            } catch {
              print("Error updating interested in: \(error)")
              viewModel.user.interestedIn = oldValue
            }
          }
        }
      )
    } label: {
      HStack {
        Text("Interested In")
        Spacer()
        Text(
          viewModel.user.interestedIn.map { $0.rawValue.capitalized }
            .joined(separator: ", ")
        )
        .foregroundColor(.gray)
      }
    }
  }

  private var distancePreference: some View {
    Group {
      HStack {
        Text("Maximum Distance")
        Spacer()
        Text("\(Int(viewModel.user.maxDistance)) miles")
      }

      Slider(
        value: $viewModel.user.maxDistance,
        in: 1...100,
        step: 1
      )
      .onChange(of: viewModel.user.maxDistance) { oldValue, newValue in
        Task {
          do {
            try await viewModel.updateUser()
          } catch {
            print("Error updating max distance: \(error)")
            viewModel.user.maxDistance = oldValue
          }
        }
      }
    }
  }

  private var datingPhotosSection: some View {
    Section("Dating Photos") {
      ScrollView(.horizontal) {
        HStack {
          existingPhotos
          addPhotoButton
        }
        .padding(.vertical)
      }
    }
  }

  private var existingPhotos: some View {
    ForEach(viewModel.user.datingImages, id: \.self) { photoURL in
      datingPhotoView(for: photoURL)
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
  NavigationStack {
    DatingSettingsView(viewModel: UserViewModel())
  }
}
