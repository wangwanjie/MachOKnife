import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

enum UpdateCheckStrategy: String, CaseIterable {
    case manual
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
    private let clientProvider: ClientProvider

    init(
        configurationProvider: @escaping ConfigurationProvider = UpdateManager.defaultConfiguration,
        clientProvider: ClientProvider? = nil
    ) {
        self.configurationProvider = configurationProvider
        self.clientProvider = clientProvider ?? UpdateManager.defaultClient
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

        guard let client = clientProvider() else {
            return makeUnavailableStatus(reason: .sparkleUnavailable)
        }

        return Status(
            availability: .ready,
            updateCheckStrategy: client.automaticallyChecksForUpdates ? .daily : .manual,
            canCheckForUpdates: client.canCheckForUpdates,
            canAutomaticallyDownloadUpdates: client.allowsAutomaticUpdates,
            automaticallyDownloadsUpdates: client.automaticallyDownloadsUpdates
        )
    }

    func checkForUpdates() {
        guard
            let client = clientProvider(),
            status().availability == .ready,
            client.canCheckForUpdates
        else {
            return
        }

        client.checkForUpdates()
    }

    func setUpdateCheckStrategy(_ strategy: UpdateCheckStrategy) {
        guard let client = clientProvider(), status().availability == .ready else {
            return
        }

        switch strategy {
        case .manual:
            client.automaticallyChecksForUpdates = false
        case .daily:
            client.updateCheckInterval = Self.dailyUpdateCheckInterval
            client.automaticallyChecksForUpdates = true
        }
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard let client = clientProvider(), status().availability == .ready else {
            return
        }

        client.automaticallyDownloadsUpdates = isEnabled
    }

    private func makeUnavailableStatus(reason: UnavailableReason) -> Status {
        Status(
            availability: .unavailable(reason),
            updateCheckStrategy: .manual,
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

    nonisolated private static func defaultClient() -> UpdateClient? {
        #if canImport(Sparkle)
        nil
        #else
        nil
        #endif
    }
}
