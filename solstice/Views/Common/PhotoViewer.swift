// PhotosViewer.swift
import SwiftUI

struct PhotoViewer: View {
  let imageURL: String
  @Binding var isPresented: Bool

  @State private var scale: CGFloat = 1.0
  @State private var offset = CGSize.zero
  @State private var lastScale: CGFloat = 1.0

  // Tracks the drag as it moves, without committing changes to 'offset' until onEnded
  @GestureState private var dragState = CGSize.zero

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Dim background based on vertical drag
        Color.black
          .ignoresSafeArea()
          .opacity(1.0 - Double(abs(offset.height)) / 500.0)

        // Actual image loading/placeholder
        AsyncImage(url: URL(string: imageURL)) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(
              x: offset.width + dragState.width,
              y: offset.height + dragState.height)
        } placeholder: {
          ProgressView()
            .tint(.white)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Allow pinch-zoom
      .simultaneousGesture(
        MagnificationGesture()
          .onChanged { value in
            let delta = value / lastScale
            lastScale = value
            // Constrain scale between 1 and 4
            scale = min(max(scale * delta, 1), 4)
          }
          .onEnded { _ in
            lastScale = 1.0
            withAnimation {
              if scale < 1 { scale = 1 } else if scale > 4 { scale = 4 }
            }
          }
      )
      // Drag image vertically to dismiss
      .simultaneousGesture(
        DragGesture()
          .updating($dragState) { value, state, _ in
            state = value.translation
          }
          .onEnded { value in
            offset = CGSize(
              width: offset.width + value.translation.width,
              height: offset.height + value.translation.height)

            let dismissThreshold = geometry.size.height * 0.2
            if abs(offset.height) > dismissThreshold {
              // Dismiss if pulled far enough vertically
              isPresented = false
              offset = .zero
              scale = 1.0
            } else {
              // Snap back if not past threshold
              withAnimation(.spring()) {
                offset = .zero
              }
            }
          }
      )
      // Give double-tap zoom higher priority than single-tap
      .highPriorityGesture(
        TapGesture(count: 2)
          .onEnded {
            withAnimation {
              scale = (scale > 1) ? 1 : 2
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
      // Reset when this view disappears (e.g. when swiping between carousel pages)
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
    // Initialize the internal index from the tapped image.
    self._currentIndex = State(initialValue: initialIndex)
  }

  var body: some View {
    TabView(selection: $currentIndex) {
      ForEach(Array(images.enumerated()), id: \.offset) { index, imageURL in
        PhotoViewer(imageURL: imageURL, isPresented: $isPresented)
          .tag(index)
      }
    }
    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .background(Color.black)
    // Force the TabView to respect the initial index on appearance
    .onAppear {
      currentIndex = initialIndex
    }
  }
}

// Quick preview – change the initialIndex to simulate tapping on different images.
#Preview {
  PhotoCarouselViewer(
    images: [
      "https://example.com/photo1.jpg",
      "https://example.com/photo2.jpg",
    ],
    initialIndex: 1,
    isPresented: .constant(true)
  )
}
