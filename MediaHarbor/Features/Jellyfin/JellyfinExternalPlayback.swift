import Foundation
import UIKit

enum JellyfinExternalPlaybackError: LocalizedError {
    case missingWebURL
    case missingStreamURL
    case appUnavailable(String)
    case invalidTargetURL

    var errorDescription: String? {
        switch self {
        case .missingWebURL:
            return "当前无法生成 Jellyfin 网页地址。"
        case .missingStreamURL:
            return "当前无法生成可供播放使用的视频流地址。"
        case let .appUnavailable(name):
            return "没有检测到 \(name)。请先安装对应 App。"
        case .invalidTargetURL:
            return "无法生成跳转地址。"
        }
    }
}

enum JellyfinExternalPlayback {
    static func targetURL(
        for target: JellyfinPlaybackOpenTarget,
        webURL: URL?,
        streamURL: URL?
    ) throws -> URL {
        switch target {
        case .app:
            guard let streamURL else {
                throw JellyfinExternalPlaybackError.missingStreamURL
            }
            return streamURL
        case .web:
            guard let webURL else {
                throw JellyfinExternalPlaybackError.missingWebURL
            }
            return webURL
        case .infuse:
            guard let streamURL else {
                throw JellyfinExternalPlaybackError.missingStreamURL
            }
            guard canOpenScheme("infuse") else {
                throw JellyfinExternalPlaybackError.appUnavailable("Infuse")
            }
            return try infuseURL(streamURL: streamURL)
        case .vidHub:
            guard let streamURL else {
                throw JellyfinExternalPlaybackError.missingStreamURL
            }
            guard canOpenScheme("open-vidhub") else {
                throw JellyfinExternalPlaybackError.appUnavailable("VidHub")
            }
            return try vidHubURL(streamURL: streamURL)
        }
    }

    private static func canOpenScheme(_ scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func infuseURL(streamURL: URL) throws -> URL {
        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        components.queryItems = [
            URLQueryItem(name: "url", value: streamURL.absoluteString),
        ]

        guard let url = components.url else {
            throw JellyfinExternalPlaybackError.invalidTargetURL
        }

        return url
    }

    private static func vidHubURL(streamURL: URL) throws -> URL {
        var components = URLComponents()
        components.scheme = "open-vidhub"
        components.host = "x-callback-url"
        components.path = "/open"
        components.queryItems = [
            URLQueryItem(name: "url", value: streamURL.absoluteString),
        ]

        guard let url = components.url else {
            throw JellyfinExternalPlaybackError.invalidTargetURL
        }

        return url
    }
}
