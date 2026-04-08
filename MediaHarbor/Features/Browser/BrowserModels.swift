import Foundation

enum BrowserSiteKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case moviePilot
    case mTeam
    case hdkyl
    case customPT

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .moviePilot:
            return "MoviePilot"
        case .mTeam:
            return "M-Team"
        case .hdkyl:
            return "HDKyl"
        case .customPT:
            return "自定义 PT"
        }
    }
}

struct BrowserSite: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var homeURLString: String
    var kind: BrowserSiteKind
    var isBuiltin: Bool
    var isVisible: Bool

    var normalizedHomeURL: URL? {
        BrowserSite.normalizeAddress(homeURLString)
    }

    var host: String? {
        normalizedHomeURL?.host?.lowercased()
    }

    var supportsResourceAssistant: Bool {
        kind != .moviePilot
    }

    var requiresAPIToken: Bool {
        kind == .mTeam
    }

    static let moviePilotID = "browser-site-moviepilot"
    static let mTeamID = "browser-site-mteam"
    static let hdkylID = "browser-site-hdkyl"

    static func defaultSites() -> [BrowserSite] {
        [
            BrowserSite(
                id: moviePilotID,
                title: "MoviePilot",
                homeURLString: "http://router.mingkang.uk:3000/#/",
                kind: .moviePilot,
                isBuiltin: true,
                isVisible: true
            ),
            BrowserSite(
                id: mTeamID,
                title: "M-Team",
                homeURLString: "https://h5.m-team.cc/",
                kind: .mTeam,
                isBuiltin: true,
                isVisible: true
            ),
            BrowserSite(
                id: hdkylID,
                title: "HDKyl",
                homeURLString: "https://www.hdkyl.in/",
                kind: .hdkyl,
                isBuiltin: true,
                isVisible: true
            ),
        ]
    }

    static func mergedStoredSitesPreservingOrder(_ storedSites: [BrowserSite]) -> [BrowserSite] {
        let builtinIDs = Set(defaultSites().map(\.id))
        let missingBuiltins = defaultSites().filter { builtin in
            storedSites.contains(where: { $0.id == builtin.id }) == false
        }

        let cleanedStoredSites = storedSites.filter { site in
            site.isBuiltin == false || builtinIDs.contains(site.id)
        }

        return cleanedStoredSites + missingBuiltins
    }

    static func normalizeAddress(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else {
            return nil
        }

        return url
    }
}

struct BrowserCredential: Codable, Equatable, Sendable {
    var username: String
    var password: String
    var apiToken: String

    static let empty = BrowserCredential(username: "", password: "", apiToken: "")

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BrowserResource: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let detailsURLString: String?
    let downloadURLString: String?
    let imageURLString: String?
    let torrentID: String?
    let isFree: Bool

    var canSendToDownloader: Bool {
        let trimmedDownloadURL = downloadURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedTorrentID = torrentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedDownloadURL.isEmpty == false || trimmedTorrentID.isEmpty == false
    }
}

struct BrowserPageSnapshot: Equatable, Sendable {
    var currentURLString: String
    var pageTitle: String
    var resources: [BrowserResource]

    static let empty = BrowserPageSnapshot(
        currentURLString: "",
        pageTitle: "",
        resources: []
    )
}
