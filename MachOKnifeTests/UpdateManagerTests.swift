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
            clientProvider: { nil },
            defaults: makeIsolatedDefaults()
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
        )

        manager.setUpdateCheckStrategy(.daily)

        #expect(client.automaticallyChecksForUpdates == true)
        #expect(client.updateCheckInterval == 24 * 60 * 60)
    }

    @Test("setting startup strategy disables periodic checks but still performs launch-time background checks")
    func settingStartupStrategyDisablesPeriodicChecksButStillPerformsLaunchTimeBackgroundChecks() {
        let suiteName = "MachOKnifeTests.UpdateManagerTests.Startup.\(UUID().uuidString)"
        let defaults = try! #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

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
            clientProvider: { client },
            defaults: defaults
        )

        manager.setUpdateCheckStrategy(.startup)

        #expect(client.automaticallyChecksForUpdates == false)
        #expect(manager.status().updateCheckStrategy == .startup)

        manager.performLaunchCheckIfNeeded()

        #expect(client.checkForUpdatesCallCount == 0)
        #expect(client.backgroundCheckForUpdatesCallCount == 1)
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
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
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
        )

        readyManager.checkForUpdates()
        #expect(client.checkForUpdatesCallCount == 1)

        let unavailableManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { client },
            defaults: makeIsolatedDefaults()
        )

        unavailableManager.checkForUpdates()
        #expect(client.checkForUpdatesCallCount == 1)
    }

    @Test("launch-time checks only run in background for the startup strategy")
    func launchTimeChecksOnlyRunInBackgroundForTheStartupStrategy() {
        let startupClient = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            updateCheckInterval: 0,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )
        let startupDefaults = makeIsolatedDefaults()
        startupDefaults.set(UpdateCheckStrategy.startup.rawValue, forKey: "app.updateCheckStrategy")
        let startupManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { startupClient },
            defaults: startupDefaults
        )

        startupManager.performLaunchCheckIfNeeded()
        #expect(startupClient.checkForUpdatesCallCount == 0)
        #expect(startupClient.backgroundCheckForUpdatesCallCount == 1)

        let dailyClient = StubUpdateClient(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            updateCheckInterval: 24 * 60 * 60,
            allowsAutomaticUpdates: true,
            automaticallyDownloadsUpdates: false
        )
        let dailyDefaults = makeIsolatedDefaults()
        dailyDefaults.set(UpdateCheckStrategy.daily.rawValue, forKey: "app.updateCheckStrategy")
        let dailyManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(
                    feedURLString: "https://example.com/appcast.xml",
                    publicEDKey: "test-public-key"
                )
            },
            clientProvider: { dailyClient },
            defaults: dailyDefaults
        )

        dailyManager.performLaunchCheckIfNeeded()
        #expect(dailyClient.checkForUpdatesCallCount == 0)
        #expect(dailyClient.backgroundCheckForUpdatesCallCount == 0)
    }
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "MachOKnifeTests.UpdateManager.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName) ?? .standard
}

@MainActor
private final class StubUpdateClient: UpdateClient {
    let canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    var updateCheckInterval: TimeInterval
    let allowsAutomaticUpdates: Bool
    var automaticallyDownloadsUpdates: Bool
    private(set) var checkForUpdatesCallCount = 0
    private(set) var backgroundCheckForUpdatesCallCount = 0

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

    func checkForUpdatesInBackground() {
        backgroundCheckForUpdatesCallCount += 1
    }
}
