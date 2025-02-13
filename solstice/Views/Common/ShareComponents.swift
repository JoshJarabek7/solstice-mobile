import SwiftUI

/// A reusable button component for sharing actions
struct ShareButton: View {
  let title: String
  let image: String?
  let systemImage: String?
  let action: () -> Void
  let foregroundColor: Color

  init(title: String, action: @escaping () -> Void) {
    self.title = title
    self.image = nil
    self.systemImage = nil
    self.foregroundColor = .primary
    self.action = action
  }

  init(
    title: String, image: String, foregroundColor: Color = .primary, action: @escaping () -> Void
  ) {
    self.title = title
    self.image = image
    self.systemImage = nil
    self.foregroundColor = foregroundColor
    self.action = action
  }

  init(
    title: String, systemImage: String, foregroundColor: Color = .primary,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.image = nil
    self.systemImage = systemImage
    self.foregroundColor = foregroundColor
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      VStack {
        if let systemImage = systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 24))
            .foregroundColor(foregroundColor)
        } else if let image = image {
          Image(image)
            .resizable()
            .frame(width: 30, height: 30)
            .foregroundColor(foregroundColor)
        }
        Text(title)
          .font(.caption)
          .foregroundColor(foregroundColor)
      }
    }
  }
}

/// A reusable row component for share options
struct ShareOptionRow: View {
  let icon: String
  let title: String
  let isSystemImage: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        if isSystemImage {
          Image(systemName: icon)
            .font(.title2)
            .foregroundColor(.blue)
        } else {
          Image(icon)
            .resizable()
            .frame(width: 24, height: 24)
        }
        Text(title)
          .foregroundColor(.primary)
        Spacer()
      }
      .padding(.vertical, 8)
      .padding(.horizontal)
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    ShareButton(title: "Share", systemImage: "square.and.arrow.up") {}
    ShareButton(title: "Message", image: "message", foregroundColor: .blue) {}
    ShareOptionRow(icon: "square.and.arrow.up", title: "Share", isSystemImage: true) {}
  }
  .padding()
}
