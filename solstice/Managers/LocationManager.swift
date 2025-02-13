import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Observation
import SwiftUI

@Observable
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  var currentLocation: CLLocation?
  var authorizationStatus: CLAuthorizationStatus

  override init() {
    self.authorizationStatus = .notDetermined
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.requestWhenInUseAuthorization()
  }

  func startUpdatingLocation() {
    manager.startUpdatingLocation()
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.first else { return }

    Task { @MainActor in
      self.currentLocation = location

      // Update user location in Firestore
      guard let userId = Auth.auth().currentUser?.uid else { return }

      do {
        try await Firestore.firestore()
          .collection("users")
          .document(userId)
          .updateData([
            "location": GeoPoint(
              latitude: location.coordinate.latitude,
              longitude: location.coordinate.longitude
            ),
            "lastLocationUpdate": FieldValue.serverTimestamp(),
          ])
      } catch {
        print("Error updating location: \(error.localizedDescription)")
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
  ) {
    Task { @MainActor in
      self.authorizationStatus = status
      if status == .authorizedWhenInUse {
        startUpdatingLocation()
      }
    }
  }
}

@MainActor
private struct LocationManagerKey: @preconcurrency EnvironmentKey {
  static let defaultValue = LocationManager()
}

extension EnvironmentValues {
  var locationManager: LocationManager {
    get { self[LocationManagerKey.self] }
    set { self[LocationManagerKey.self] = newValue }
  }
}

#Preview {
  VStack {
    Text("Location Manager Preview")
  }
  .environment(\.locationManager, LocationManager())
}
