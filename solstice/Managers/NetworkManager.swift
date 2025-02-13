import Foundation
import Network

@MainActor
class NetworkManager: ObservableObject {
  @Published private(set) var isConnected = false
  private let monitor: NWPathMonitor
  private let queue: DispatchQueue

  static let shared = NetworkManager()

  private init() {
    self.monitor = NWPathMonitor()
    self.queue = DispatchQueue(label: "NetworkManager")
    setupMonitor()
  }

  private func setupMonitor() {
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        self?.isConnected = path.status == .satisfied
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}
