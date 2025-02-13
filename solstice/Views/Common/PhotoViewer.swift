import SwiftUI

struct PhotoViewer: View {
  let imageURL: String
  @Binding var isPresented: Bool
  @State private var scale: CGFloat = 1.0
  @State private var offset = CGSize.zero
  @State private var lastScale: CGFloat = 1.0
  @GestureState private var dragState = CGSize.zero
  
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Background
        Color.black
          .ignoresSafeArea()
          .opacity(1.0 - Double(abs(offset.height)) / 500.0)
        
        // Image
        AsyncImage(url: URL(string: imageURL)) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(x: offset.width + dragState.width, y: offset.height + dragState.height)
        } placeholder: {
          ProgressView()
            .tint(.white)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Pinch to zoom
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            let delta = value / lastScale
            lastScale = value
            scale = min(max(scale * delta, 1), 4)
          }
          .onEnded { _ in
            lastScale = 1.0
            if scale < 1 {
              withAnimation {
                scale = 1
              }
            } else if scale > 4 {
              withAnimation {
                scale = 4
              }
            }
          }
      )
      // Drag to dismiss
      .simultaneousGesture(
        DragGesture()
          .updating($dragState) { value, state, _ in
            state = value.translation
          }
          .onEnded { value in
            offset = CGSize(
              width: offset.width + value.translation.width,
              height: offset.height + value.translation.height
            )
            
            let dismissThreshold = geometry.size.height * 0.2
            if abs(offset.height) > dismissThreshold {
              isPresented = false
              offset = .zero
              scale = 1.0
            } else {
              withAnimation(.spring()) {
                offset = .zero
              }
            }
          }
      )
      // Double tap to zoom
      .gesture(
        TapGesture(count: 2)
          .onEnded {
            withAnimation {
              if scale > 1 {
                scale = 1
              } else {
                scale = 2
              }
            }
          }
      )
      // Single tap to dismiss
      .gesture(
        TapGesture()
          .onEnded {
            isPresented = false
            offset = .zero
            scale = 1.0
          }
      )
      .onDisappear {
        offset = .zero
        scale = 1.0
      }
    }
  }
}

struct PhotoCarouselViewer: View {
  let images: [String]
  let initialIndex: Int
  @Binding var isPresented: Bool
  @State private var currentIndex: Int
  
  init(images: [String], initialIndex: Int = 0, isPresented: Binding<Bool>) {
    self.images = images
    self.initialIndex = initialIndex
    self._isPresented = isPresented
    self._currentIndex = State(initialValue: initialIndex)
  }
  
  var body: some View {
    TabView(selection: $currentIndex) {
      ForEach(images.indices, id: \.self) { index in
        PhotoViewer(imageURL: images[index], isPresented: $isPresented)
          .tag(index)
      }
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .background(Color.black)
  }
}

#Preview {
  PhotoCarouselViewer(
    images: [
      "https://example.com/photo1.jpg",
      "https://example.com/photo2.jpg"
    ],
    isPresented: .constant(true)
  )
} 