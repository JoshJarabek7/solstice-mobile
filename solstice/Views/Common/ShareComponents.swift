import SwiftUI

struct ShareButton: View {
  let title: String
  var image: String? = nil
  var systemImage: String? = nil
  let action: () -> Void
  
  var body: some View {
    Button(action: action) {
      VStack {
        if let systemImage = systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 24))
        } else if let image = image {
          Image(image)
            .resizable()
            .frame(width: 30, height: 30)
        }
        Text(title)
          .font(.caption)
      }
    }
  }
}

#Preview {
  ShareButton(title: "Share", systemImage: "square.and.arrow.up") {}
} 