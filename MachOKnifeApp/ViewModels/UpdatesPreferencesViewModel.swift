import Foundation

struct UpdatesPreferencesViewState: Equatable {
    enum StatusTone: Equatable {
        case ready
        case warning
    }

    let statusText: String
    let detailText: String
    let statusTone: StatusTone
    let updateCheckStrategy: UpdateCheckStrategy
    let isUpdateStrategyEnabled: Bool
    let isAutomaticDownloadsEnabled: Bool
    let automaticallyDownloadsUpdates: Bool
    let isCheckNowEnabled: Bool
}

@MainActor
final class UpdatesPreferencesViewModel {
    private let updateManager: UpdateManager

    private(set) var state = UpdatesPreferencesViewState(
        statusText: "",
        detailText: "",
        statusTone: .warning,
        updateCheckStrategy: .manual,
        isUpdateStrategyEnabled: false,
        isAutomaticDownloadsEnabled: false,
        automaticallyDownloadsUpdates: false,
        isCheckNowEnabled: false
    )

    init(updateManager: UpdateManager) {
        self.updateManager = updateManager
    }

    func refresh() {
        state = Self.makeState(from: updateManager.status())
    }

    func setUpdateCheckStrategy(_ strategy: UpdateCheckStrategy) {
        updateManager.setUpdateCheckStrategy(strategy)
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updateManager.setAutomaticallyDownloadsUpdates(isEnabled)
        refresh()
    }

    func checkForUpdates() {
        updateManager.checkForUpdates()
        refresh()
    }

    private static func makeState(from status: UpdateManager.Status) -> UpdatesPreferencesViewState {
        switch status.availability {
        case .ready:
            return UpdatesPreferencesViewState(
                statusText: L10n.preferencesUpdatesStatusReady,
                detailText: L10n.preferencesUpdatesDetailReady,
                statusTone: .ready,
                updateCheckStrategy: status.updateCheckStrategy,
                isUpdateStrategyEnabled: true,
                isAutomaticDownloadsEnabled: status.canAutomaticallyDownloadUpdates,
                automaticallyDownloadsUpdates: status.automaticallyDownloadsUpdates,
                isCheckNowEnabled: status.canCheckForUpdates
            )

        case let .unavailable(reason):
            return UpdatesPreferencesViewState(
                statusText: L10n.preferencesUpdatesStatusConfigurationRequired,
                detailText: detailText(for: reason),
                statusTone: .warning,
                updateCheckStrategy: status.updateCheckStrategy,
                isUpdateStrategyEnabled: false,
                isAutomaticDownloadsEnabled: false,
                automaticallyDownloadsUpdates: false,
                isCheckNowEnabled: false
            )
        }
    }

    private static func detailText(for reason: UpdateManager.UnavailableReason) -> String {
        switch reason {
        case .feedURLMissing:
            return L10n.preferencesUpdatesDetailFeedURLMissing
        case .publicKeyMissing:
            return L10n.preferencesUpdatesDetailPublicKeyMissing
        case .sparkleUnavailable:
            return L10n.preferencesUpdatesDetailSparkleUnavailable
        }
    }
}
