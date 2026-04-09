import Foundation
import Observation

enum JellyfinPlaybackOpenTarget: String, CaseIterable, Codable, Identifiable, Sendable {
    case app
    case web
    case infuse
    case vidHub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app:
            return "App 内播放"
        case .web:
            return "网页"
        case .infuse:
            return "Infuse"
        case .vidHub:
            return "VidHub"
        }
    }

    var summary: String {
        switch self {
        case .app:
            return "使用 MediaHarbor 内置播放器"
        case .web:
            return "打开 Jellyfin 网页详情页"
        case .infuse:
            return "把视频流交给 Infuse 播放"
        case .vidHub:
            return "把视频流交给 VidHub 播放"
        }
    }

    var iconName: String {
        switch self {
        case .app:
            return "play.rectangle.fill"
        case .web:
            return "globe"
        case .infuse:
            return "sparkles.tv"
        case .vidHub:
            return "play.tv"
        }
    }

    func actionTitle(playbackPositionText: String?) -> String {
        switch self {
        case .app:
            return playbackPositionText == nil ? "播放" : "继续播放"
        case .web:
            return "用网页打开"
        case .infuse:
            return "用 Infuse 打开"
        case .vidHub:
            return "用 VidHub 打开"
        }
    }

    func actionSummary(playbackPositionText: String?) -> String {
        switch self {
        case .app:
            if let playbackPositionText, playbackPositionText.isEmpty == false {
                return "从 \(playbackPositionText) 开始，使用 MediaHarbor 内置播放器"
            }
            return summary
        case .web, .infuse, .vidHub:
            return summary
        }
    }
}

@MainActor
@Observable
final class JellyfinPlaybackPreferences {
    var preferredOpenTarget: JellyfinPlaybackOpenTarget {
        didSet {
            storage.set(preferredOpenTarget.rawValue, forKey: Self.preferredOpenTargetKey)
        }
    }

    @ObservationIgnored
    private let storage: CloudBackedDefaults

    @ObservationIgnored
    private var cloudObserver: NSObjectProtocol?

    private static let preferredOpenTargetKey = "jellyfin.playback.preferred-open-target"

    init(defaults: UserDefaults = .standard, cloudStore: NSUbiquitousKeyValueStore? = nil) {
        self.storage = CloudBackedDefaults(defaults: defaults, cloudStore: cloudStore)

        if let rawValue = storage.string(forKey: Self.preferredOpenTargetKey),
           let target = JellyfinPlaybackOpenTarget(rawValue: rawValue)
        {
            preferredOpenTarget = target
        } else {
            preferredOpenTarget = .app
        }

        installCloudObserver()
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    private func installCloudObserver() {
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFromCloud()
            }
        }
    }

    private func syncFromCloud() {
        if let rawValue = storage.string(forKey: Self.preferredOpenTargetKey),
           let target = JellyfinPlaybackOpenTarget(rawValue: rawValue)
        {
            preferredOpenTarget = target
        } else {
            preferredOpenTarget = .app
        }
    }
}
