import SwiftUI

struct VideoTrimmer: View {
  let duration: Double
  @Binding var startTime: Double
  @Binding var endTime: Double

  private let handleWidth: CGFloat = 20
  private let minimumDuration: Double = 3.0

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background
        Rectangle()
          .fill(Color.gray.opacity(0.3))

        // Selected range
        Rectangle()
          .fill(Color.blue.opacity(0.3))
          .frame(
            width: width(for: endTime - startTime, in: geometry),
            height: geometry.size.height
          )
          .offset(x: position(for: startTime, in: geometry))

        // Start handle
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.white)
          .frame(width: handleWidth, height: geometry.size.height)
          .offset(x: position(for: startTime, in: geometry))
          .gesture(
            DragGesture()
              .onChanged { value in
                let newStart = time(for: value.location.x, in: geometry)
                if newStart >= 0 && newStart <= endTime - minimumDuration {
                  startTime = newStart
                }
              }
          )

        // End handle
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.white)
          .frame(width: handleWidth, height: geometry.size.height)
          .offset(x: position(for: endTime, in: geometry))
          .gesture(
            DragGesture()
              .onChanged { value in
                let newEnd = time(for: value.location.x, in: geometry)
                if newEnd <= duration && newEnd >= startTime + minimumDuration {
                  endTime = newEnd
                }
              }
          )

        // Time indicators
        HStack {
          Text(timeString(from: startTime))
            .font(.caption)
            .foregroundColor(.white)
            .padding(.leading, 4)

          Spacer()

          Text(timeString(from: endTime))
            .font(.caption)
            .foregroundColor(.white)
            .padding(.trailing, 4)
        }
      }
    }
    .frame(height: 44)
    .cornerRadius(8)
  }

  private func position(for time: Double, in geometry: GeometryProxy) -> CGFloat {
    let ratio = time / duration
    return ratio * (geometry.size.width - handleWidth)
  }

  private func width(for duration: Double, in geometry: GeometryProxy) -> CGFloat {
    let ratio = duration / self.duration
    return ratio * geometry.size.width
  }

  private func time(for position: CGFloat, in geometry: GeometryProxy) -> Double {
    let ratio = position / (geometry.size.width - handleWidth)
    return ratio * duration
  }

  private func timeString(from seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let seconds = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

#Preview {
  VideoTrimmer(duration: 60, startTime: .constant(0), endTime: .constant(60))
    .frame(height: 50)
    .padding()
}
