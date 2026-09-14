import Foundation
import Combine

@MainActor
final class ClipboardMonitoringState: ObservableObject {
    @Published var isPaused: Bool

    private var cancellable: AnyCancellable?

    init(initialPaused: Bool = false) {
        self.isPaused = initialPaused

        cancellable = NotificationCenter.default
            .publisher(for: .clipboardMonitoringPausedDidChange)
            .compactMap { $0.userInfo?["paused"] as? Bool }
            .receive(on: RunLoop.main)
            .sink { [weak self] paused in
                self?.isPaused = paused
            }
    }
}
