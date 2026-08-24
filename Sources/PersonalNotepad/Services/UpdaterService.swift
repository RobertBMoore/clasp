#if CLASP_DIRECT_DISTRIBUTION
import Combine
import Sparkle
import SwiftUI

/// Sparkle is compiled only into the notarized Developer ID distribution.
/// Mac App Store builds intentionally omit this file's implementation and use
/// the App Store's update mechanism instead.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
#endif
