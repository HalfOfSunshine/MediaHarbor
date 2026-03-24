import Foundation

struct JellyfinSessionSnapshot: Codable, Equatable, Sendable, Identifiable {
    let serverURLString: String
    let serverName: String
    let serverVersion: String?
    let username: String
    let userID: String

    var id: String {
        accountKey
    }

    var accountKey: String {
        "\(serverURLString.lowercased())|\(userID)"
    }

    var serverSummary: String {
        serverName.isEmpty ? serverURLString : serverName
    }

    var accountSummary: String {
        "\(username) @ \(serverSummary)"
    }
}

struct JellyfinPublicInfo: Equatable, Sendable {
    let serverName: String
    let version: String?
    let identifier: String?
    let localAddress: String?
}

struct JellyfinLibrary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let collectionType: String?
    let itemCount: Int?
    let type: String?
    let isFolder: Bool

    var kind: JellyfinLibraryKind {
        JellyfinLibraryKind(collectionType: collectionType, type: type)
    }

    var subtitle: String {
        let kindTitle = kind.title

        if let itemCount {
            return "\(kindTitle) · \(itemCount) 项"
        }

        if kind != .other {
            return kindTitle
        }

        return "媒体库"
    }

    var isManageableMediaLibrary: Bool {
        if type == "CollectionFolder" {
            return true
        }

        switch collectionType?.lowercased() {
        case "movies", "tvshows", "mixed", "homevideos", "boxsets":
            return true
        default:
            return false
        }
    }

    static func mediaLibraries(from libraries: [JellyfinLibrary]) -> [JellyfinLibrary] {
        let filteredLibraries = libraries.filter(\.isManageableMediaLibrary)
        let candidate = filteredLibraries.isEmpty ? libraries : filteredLibraries

        return candidate.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum JellyfinConsoleLibrarySource: Equatable, Sendable {
    case administrator
    case userVisible

    var noticeTitle: String {
        switch self {
        case .administrator:
            return "后台媒体库"
        case .userVisible:
            return "账号可见媒体库"
        }
    }

    var noticeMessage: String {
        switch self {
        case .administrator:
            return "这里展示的是 Jellyfin 管理后台返回的全部媒体库，包括当前账号媒体访问权限没有勾选的库。单个媒体库刷新会直接对对应媒体库提交刷新请求。"
        case .userVisible:
            return "当前连接没有拿到管理员媒体库列表，所以这里只显示这个账号自己可见的媒体库。完整的全库文件扫描仍然可以使用“扫描所有媒体库”。"
        }
    }
}

struct JellyfinConsoleLibraries: Equatable, Sendable {
    let libraries: [JellyfinLibrary]
    let source: JellyfinConsoleLibrarySource
}

enum JellyfinLibraryKind: Equatable, Sendable {
    case movies
    case tvShows
    case mixed
    case homeVideos
    case collections
    case other

    init(collectionType: String?, type: String?) {
        switch collectionType?.lowercased() {
        case "movies":
            self = .movies
        case "tvshows":
            self = .tvShows
        case "mixed":
            self = .mixed
        case "homevideos":
            self = .homeVideos
        case "boxsets":
            self = .collections
        default:
            if type == "CollectionFolder" {
                self = .mixed
            } else {
                self = .other
            }
        }
    }

    var title: String {
        switch self {
        case .movies:
            return "电影"
        case .tvShows:
            return "电视剧"
        case .mixed:
            return "混合媒体"
        case .homeVideos:
            return "家庭视频"
        case .collections:
            return "合集"
        case .other:
            return "媒体库"
        }
    }

    var itemTypesQueryValue: String? {
        switch self {
        case .movies:
            return "Movie"
        case .tvShows:
            return "Series"
        case .mixed, .homeVideos, .collections:
            return "Movie,Series"
        case .other:
            return nil
        }
    }
}

struct JellyfinMovie: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let runtimeTicks: Int64?
    let premiereDateText: String?
    let primaryImageTag: String?

    var yearText: String {
        if let productionYear {
            return String(productionYear)
        }

        return "年份未知"
    }

    var runtimeText: String? {
        guard let runtimeTicks else {
            return nil
        }

        let minutes = Int((Double(runtimeTicks) / 10_000_000) / 60)
        guard minutes > 0 else {
            return nil
        }

        return "\(minutes) 分钟"
    }

    var ratingText: String? {
        guard let communityRating, communityRating.isFinite else {
            return nil
        }

        return String(format: "%.1f", communityRating)
    }

    var summaryText: String {
        if let overview, overview.isEmpty == false {
            return overview
        }

        return "暂时还没有剧情简介。"
    }
}

struct JellyfinLibraryItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String?
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let runtimeTicks: Int64?
    let premiereDateText: String?
    let primaryImageTag: String?
    let childCount: Int?
    let isFolder: Bool

    var kind: JellyfinLibraryItemKind {
        JellyfinLibraryItemKind(type: type, isFolder: isFolder)
    }

    var yearText: String {
        if let productionYear {
            return String(productionYear)
        }

        return "年份未知"
    }

    var runtimeText: String? {
        guard let runtimeTicks else {
            return nil
        }

        let minutes = Int((Double(runtimeTicks) / 10_000_000) / 60)
        guard minutes > 0 else {
            return nil
        }

        return "\(minutes) 分钟"
    }

    var ratingText: String? {
        guard let communityRating, communityRating.isFinite else {
            return nil
        }

        return String(format: "%.1f", communityRating)
    }

    var summaryText: String {
        if let overview, overview.isEmpty == false {
            return overview
        }

        return "暂时还没有剧情简介。"
    }

    var metaText: String {
        if let childCount, kind == .series {
            return "\(kind.title) · \(childCount) 项"
        }

        return kind.title
    }

    var posterSymbolName: String {
        switch kind {
        case .movie:
            return "film.fill"
        case .series:
            return "tv.fill"
        case .folder:
            return "folder.fill"
        case .other:
            return "photo.stack.fill"
        }
    }
}

enum JellyfinLibraryItemKind: Equatable, Sendable {
    case movie
    case series
    case folder
    case other

    init(type: String?, isFolder: Bool) {
        switch type?.lowercased() {
        case "movie":
            self = .movie
        case "series":
            self = .series
        default:
            self = isFolder ? .folder : .other
        }
    }

    var title: String {
        switch self {
        case .movie:
            return "电影"
        case .series:
            return "电视剧"
        case .folder:
            return "文件夹"
        case .other:
            return "媒体"
        }
    }
}

enum JellyfinTaskState: String, Codable, Sendable {
    case idle = "Idle"
    case cancelling = "Cancelling"
    case running = "Running"

    var title: String {
        switch self {
        case .idle:
            return "空闲"
        case .cancelling:
            return "停止中"
        case .running:
            return "运行中"
        }
    }
}

struct JellyfinTask: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let state: JellyfinTaskState
    let progress: Double?
    let category: String?
    let key: String?
    let summary: String?
    let lastRunDateText: String?
    let lastRunStatus: String?

    var isRunning: Bool {
        state == .running
    }

    var isLibraryScanTask: Bool {
        if key == "RefreshLibrary" {
            return true
        }

        let loweredName = name.lowercased()
        return loweredName.contains("scan media library") || loweredName.contains("扫描媒体库")
    }

    var progressText: String? {
        guard let progress, progress.isFinite else {
            return nil
        }

        let clamped = min(max(progress, 0), 100)
        return "\(Int(clamped.rounded()))%"
    }
}

enum JellyfinServerURL {
    static func normalize(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: value) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard components.host?.isEmpty == false else {
            return nil
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }
}
