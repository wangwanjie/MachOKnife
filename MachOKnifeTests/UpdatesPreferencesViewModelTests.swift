import Foundation
import Testing
@testable import MachOKnife

@MainActor
struct UpdatesPreferencesViewModelTests {
    @Test("refresh shows configuration guidance when Sparkle metadata is missing")
    func refreshShowsConfigurationGuidanceWhenSparkleMetadataIsMissing() {
        let viewModel = UpdatesPreferencesViewModel(
            updateManager: UpdateManager(
                configurationProvider: {
                    UpdateConfiguration(feedURLString: "", publicEDKey: "")
                },
                clientProvider: { nil },
                defaults: makeIsolatedUpdatesDefaults()
            )
        )

        viewModel.refresh()

        #expect(viewModel.state.statusText == L10n.preferencesUpdatesStatusConfigurationRequired)
        #expect(viewModel.state.detailText == L10n.preferencesUpdatesDetailFeedURLMissing)
        #expect(viewModel.state.isUpdateStrategyEnabled == false)
        #expect(viewModel.state.isAutomaticDownloadsEnabled == false)
        #expect(viewModel.state.isCheckNowEnabled == false)
    }

    @Test("refresh exposes ready updater controls when Sparkle is available")
    func refreshExposesReadyUpdaterControlsWhenSparkleIsAvailable() {
        let client = StubPreferencesUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: true
        )
        let viewModel = UpdatesPreferencesViewModel(
            updateManager: UpdateManager(
                configurationProvider: {
                    UpdateConfiguration(
                        feedURLString: "https://example.com/appcast.xml",
                        publicEDKey: "test-public-key"
                    )
                },
                clientProvider: { client },
                defaults: makeIsolatedUpdatesDefaults()
            )
        )

        viewModel.refresh()

        #expect(viewModel.state.statusText == L10n.preferencesUpdatesStatusReady)
        #expect(viewModel.state.updateCheckStrategy == .daily)
        #expect(viewModel.state.isUpdateStrategyEnabled)
        #expect(viewModel.state.isAutomaticDownloadsEnabled)
        #expect(viewModel.state.automaticallyDownloadsUpdates)
        #expect(viewModel.state.isCheckNowEnabled)
    }

    @Test("changing update controls forwards to the updater and refreshes presentation")
    func changingUpdateControlsForwardsToUpdaterAndRefreshesPresentation() {
        let client = StubPreferencesUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            updateCheckInterval: 0,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )
        let viewModel = UpdatesPreferencesViewModel(
            updateManager: UpdateManager(
                configurationProvider: {
                    UpdateConfiguration(
                        feedURLString: "https://example.com/appcast.xml",
                        publicEDKey: "test-public-key"
                    )
                },
                clientProvider: { client },
                defaults: makeIsolatedUpdatesDefaults()
            )
        )

        viewModel.refresh()
        viewModel.setUpdateCheckStrategy(.daily)
        viewModel.setAutomaticallyDownloadsUpdates(true)

        #expect(client.automaticallyChecksForUpdates)
        #expect(client.updateCheckInterval == 24 * 60 * 60)
        #expect(client.automaticallyDownloadsUpdates)
        #expect(viewModel.state.updateCheckStrategy == .daily)
        #expect(viewModel.state.automaticallyDownloadsUpdates)
    }
}

private func makeIsolatedUpdatesDefaults() -> UserDefaults {
    let suiteName = "MachOKnifeTests.UpdatesPreferences.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName) ?? .standard
}

@MainActor
private final class StubPreferencesUpdateClient: UpdateClient {
    let canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    var updateCheckInterval: TimeInterval
    let allowsAutomaticUpdates: Bool
    var automaticallyDownloadsUpdates: Bool

    init(
        canCheckForUpdates: Bool,
        automaticallyChecksForUpdates: Bool,
        updateCheckInterval: TimeInterval,
        allowsAutomaticUpdates: Bool,
        automaticallyDownloadsUpdates: Bool
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.updateCheckInterval = updateCheckInterval
        self.allowsAutomaticUpdates = allowsAutomaticUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    }

    func checkForUpdates() {}

    func checkForUpdatesInBackground() {}
}
