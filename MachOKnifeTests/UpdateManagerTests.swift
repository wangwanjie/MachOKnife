import Foundation
import Testing
@testable import MachOKnife

@MainActor
struct UpdateManagerTests {
    @Test("status reports feed configuration problems before updates are enabled")
    func statusReportsFeedConfigurationProblems() {
        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )

        let status = manager.status()

        #expect(status.availability == .unavailable(.feedURLMissing))
        #expect(status.canCheckForUpdates == false)
    }

    @Test("status reports ready when update configuration and client are available")
    func statusReportsReadyWhenConfigurationAndClientAreAvailable() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        let status = manager.status()

        #expect(status.availability == .ready)
        #expect(status.updateCheckStrategy == .daily)
        #expect(status.canCheckForUpdates)
        #expect(status.canAutomaticallyDownloadUpdates)
        #expect(status.automaticallyDownloadsUpdates == false)
    }

    @Test("status maps disabled automatic checks to manual strategy")
    func statusMapsDisabledAutomaticChecksToManualStrategy() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            updateCheckInterval: 0,
            allowsAutomaticUpdates: false,
            automaticallyDownloadsUpdates: false
        )

        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        let status = manager.status()

        #expect(status.updateCheckStrategy == .manual)
        #expect(status.canAutomaticallyDownloadUpdates == false)
    }

    @Test("setting daily strategy enables automatic checks with the daily interval")
    func settingDailyStrategyEnablesAutomaticChecksWithDailyInterval() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            updateCheckInterval: 0,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        manager.setUpdateCheckStrategy(.daily)

        #expect(client.automaticallyChecksForUpdates == true)
        #expect(client.updateCheckInterval == 24 * 60 * 60)
    }

    @Test("setting manual strategy disables automatic checks")
    func settingManualStrategyDisablesAutomaticChecks() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        manager.setUpdateCheckStrategy(.manual)

        #expect(client.automaticallyChecksForUpdates == false)
    }

    @Test("setting automatic downloads forwards to the update client")
    func settingAutomaticDownloadsForwardsToUpdateClient() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        let manager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        manager.setAutomaticallyDownloadsUpdates(true)

        #expect(client.automaticallyDownloadsUpdates == true)
    }

    @Test("manual update checks are forwarded only when the updater is ready")
    func manualUpdateChecksAreForwardedOnlyWhenUpdaterIsReady() {
        let client = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        let readyManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { client }
        )

        readyManager.checkForUpdates()
        #expect(client.checkForUpdatesCallCount == 1)

        let unavailableManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { client }
        )

        unavailableManager.checkForUpdates()
        #expect(client.checkForUpdatesCallCount == 1)
    }
}

@MainActor
private final class StubUpdateClient: UpdateClient {
    let canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    var updateCheckInterval: TimeInterval
    let allowsAutomaticUpdates: Bool
    var automaticallyDownloadsUpdates: Bool
    private(set) var checkForUpdatesCallCount = 0

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

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }
}
