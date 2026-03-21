import Foundation
import AppKit
import Sparkle

enum UpdateCheckStrategy: String, CaseIterable {
    case manual
    case startup
    case daily
}

struct UpdateConfiguration: Equatable {
    let feedURLString: String
    let publicEDKey: String
}

protocol UpdateClient: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var allowsAutomaticUpdates: Bool { get }
    var automaticallyDownloadsUpdates: Bool { get set }

    func checkForUpdates()
    func checkForUpdatesInBackground()
}

@MainActor
final class UpdateManager {
    static let dailyUpdateCheckInterval: TimeInterval = 24 * 60 * 60

    enum UnavailableReason: Equatable {
        case feedURLMissing
        case publicKeyMissing
        case sparkleUnavailable
    }

    enum Availability: Equatable {
        case unavailable(UnavailableReason)
        case ready
    }

    struct Status: Equatable {
        let availability: Availability
        let updateCheckStrategy: UpdateCheckStrategy
        let canCheckForUpdates: Bool
        let canAutomaticallyDownloadUpdates: Bool
        let automaticallyDownloadsUpdates: Bool
    }

    typealias ConfigurationProvider = () -> UpdateConfiguration
    typealias ClientProvider = () -> UpdateClient?

    private let configurationProvider: ConfigurationProvider
    private let injectedClientProvider: ClientProvider?
    private let defaults: UserDefaults
    private lazy var defaultClient = Self.makeDefaultClient()

    private enum Keys {
        static let updateCheckStrategy = "app.updateCheckStrategy"
    }

    init(
        configurationProvider: @escaping ConfigurationProvider = UpdateManager.defaultConfiguration,
        clientProvider: ClientProvider? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.configurationProvider = configurationProvider
        self.injectedClientProvider = clientProvider
        self.defaults = defaults
    }

    func status() -> Status {
        let configuration = configurationProvider()
        let feedURLString = configuration.feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicEDKey = configuration.publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if feedURLString.isEmpty {
            return makeUnavailableStatus(reason: .feedURLMissing)
        }

        if publicEDKey.isEmpty {
            return makeUnavailableStatus(reason: .publicKeyMissing)
        }

        guard let client = activeClient() else {
            return makeUnavailableStatus(reason: .sparkleUnavailable)
        }

        return Status(
            availability: .ready,
            updateCheckStrategy: storedUpdateCheckStrategy()
                ?? (client.automaticallyChecksForUpdates ? .daily : .manual),
            canCheckForUpdates: client.canCheckForUpdates,
            canAutomaticallyDownloadUpdates: client.allowsAutomaticUpdates,
            automaticallyDownloadsUpdates: client.automaticallyDownloadsUpdates
        )
    }

    func checkForUpdates() {
        guard
            let client = activeClient(),
            status().availability == .ready,
            client.canCheckForUpdates
        else {
            return
        }

        client.checkForUpdates()
    }

    func performLaunchCheckIfNeeded() {
        let currentStatus = status()
        guard
            currentStatus.availability == .ready,
            currentStatus.updateCheckStrategy == .startup,
            let client = activeClient(),
            client.canCheckForUpdates
        else {
            return
        }

        client.checkForUpdatesInBackground()
    }

    func openGitHubHomepage() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "MachOKnifeGitHubURL") as? String,
            let url = URL(string: urlString)
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func setUpdateCheckStrategy(_ strategy: UpdateCheckStrategy) {
        guard let client = activeClient(), status().availability == .ready else {
            return
        }

        switch strategy {
        case .manual:
            persistUpdateCheckStrategy(.manual)
            client.automaticallyChecksForUpdates = false
        case .startup:
            persistUpdateCheckStrategy(.startup)
            client.automaticallyChecksForUpdates = false
        case .daily:
            persistUpdateCheckStrategy(.daily)
            client.updateCheckInterval = Self.dailyUpdateCheckInterval
            client.automaticallyChecksForUpdates = true
        }
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard let client = activeClient(), status().availability == .ready else {
            return
        }

        client.automaticallyDownloadsUpdates = isEnabled
    }

    private func makeUnavailableStatus(reason: UnavailableReason) -> Status {
        Status(
            availability: .unavailable(reason),
            updateCheckStrategy: storedUpdateCheckStrategy() ?? .manual,
            canCheckForUpdates: false,
            canAutomaticallyDownloadUpdates: false,
            automaticallyDownloadsUpdates: false
        )
    }

    nonisolated private static func defaultConfiguration() -> UpdateConfiguration {
        let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicEDKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""

        return UpdateConfiguration(feedURLString: feedURLString, publicEDKey: publicEDKey)
    }

    private func activeClient() -> UpdateClient? {
        injectedClientProvider?() ?? defaultClient
    }

    private func storedUpdateCheckStrategy() -> UpdateCheckStrategy? {
        guard let rawValue = defaults.string(forKey: Keys.updateCheckStrategy) else {
            return nil
        }
        return UpdateCheckStrategy(rawValue: rawValue)
    }

    private func persistUpdateCheckStrategy(_ strategy: UpdateCheckStrategy) {
        defaults.set(strategy.rawValue, forKey: Keys.updateCheckStrategy)
    }

    private static func makeDefaultClient() -> UpdateClient {
        SparkleUpdateClient()
    }
}

@MainActor
private final class SparkleUpdateClient: NSObject, UpdateClient {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }

    var allowsAutomaticUpdates: Bool {
        updaterController.updater.allowsAutomaticUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
}
