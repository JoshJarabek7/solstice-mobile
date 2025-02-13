import SwiftUI

struct SearchBar: View {
  @Binding var text: String
  var placeholder: String = "Search"
  var onSubmit: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.gray)
        .frame(width: 20, height: 20)

      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.search)
        .onSubmit {
          onSubmit?()
        }

      if !text.isEmpty {
        Button(action: {
          withAnimation {
            text = ""
          }
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.gray)
            .frame(width: 20, height: 20)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background {
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(.systemGray6))
    }
  }
}

#Preview("Search Bar") {
  struct PreviewWrapper: View {
    @State private var searchText = ""

    var body: some View {
      SearchBar(text: $searchText, placeholder: "Search users")
    }
  }

  return PreviewWrapper()
}
