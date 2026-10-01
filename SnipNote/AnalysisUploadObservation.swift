import Combine
import Foundation

/// Observes presentation data without initializing the live coordinator in screen fixtures.
@MainActor final class AnalysisUploadObservation: ObservableObject {
  @Published private(set) var snapshots: [UUID: BackgroundUploadManifest]
  private var subscription: AnyCancellable?

  init(coordinator: BackgroundUploadCoordinator?) {
    snapshots = coordinator?.snapshots ?? [:]
    subscription = coordinator?.$snapshots.sink { [weak self] in self?.snapshots = $0 }
  }
}
