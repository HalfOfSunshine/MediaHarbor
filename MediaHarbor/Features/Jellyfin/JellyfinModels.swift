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
            return "这里优先基于 Jellyfin 管理后台返回的媒体库列表整理，但单个媒体库刷新只显示当前账号真正可访问、能稳定提交刷新的媒体库。完整的后台全库扫描仍然使用“扫描所有媒体库”。"
        case .userVisible:
            return "当前连接没有拿到管理员媒体库列表，所以这里只显示这个账号自己可见的媒体库。完整的全库文件扫描仍然可以使用“扫描所有媒体库”。"
        }
    }
}

struct JellyfinConsoleLibraries: Equatable, Sendable {
    let libraries: [JellyfinLibrary]
    let source: JellyfinConsoleLibrarySource
}

extension JellyfinLibrary {
    static func refreshableConsoleLibraries(
        managedLibraries: [JellyfinLibrary],
        userVisibleLibraries: [JellyfinLibrary],
        source: JellyfinConsoleLibrarySource
    ) -> [JellyfinLibrary] {
        let visibleIDs = Set(userVisibleLibraries.map(\.id))

        switch source {
        case .administrator:
            return managedLibraries
                .filter { visibleIDs.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .userVisible:
            return managedLibraries
        }
    }
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
    let playbackPositionTicks: Int64?
    let isFavorite: Bool

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

    var canOpenInExternalPlayer: Bool {
        true
    }

    var playbackPositionText: String? {
        JellyfinPlaybackFormatting.positionText(from: playbackPositionTicks)
    }

    func updatingFavorite(_ isFavorite: Bool) -> JellyfinMovie {
        JellyfinMovie(
            id: id,
            name: name,
            overview: overview,
            productionYear: productionYear,
            communityRating: communityRating,
            officialRating: officialRating,
            runtimeTicks: runtimeTicks,
            premiereDateText: premiereDateText,
            primaryImageTag: primaryImageTag,
            playbackPositionTicks: playbackPositionTicks,
            isFavorite: isFavorite
        )
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
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let playbackPositionTicks: Int64?
    let isFavorite: Bool

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

        if kind == .season {
            if let indexNumber {
                return "第 \(indexNumber) 季"
            }

            return kind.title
        }

        if kind == .episode, let episodeText {
            return episodeText
        }

        return kind.title
    }

    var posterSymbolName: String {
        switch kind {
        case .movie:
            return "film.fill"
        case .series:
            return "tv.fill"
        case .season:
            return "square.stack.3d.up.fill"
        case .episode:
            return "play.tv.fill"
        case .folder:
            return "folder.fill"
        case .other:
            return "photo.stack.fill"
        }
    }

    var canOpenInExternalPlayer: Bool {
        switch kind {
        case .movie, .episode, .other:
            return true
        case .series, .season, .folder:
            return false
        }
    }

    var playbackPositionText: String? {
        JellyfinPlaybackFormatting.positionText(from: playbackPositionTicks)
    }

    var episodeText: String? {
        guard let parentIndexNumber, let indexNumber else {
            return nil
        }

        return "S\(parentIndexNumber)E\(indexNumber)"
    }

    func updatingFavorite(_ isFavorite: Bool) -> JellyfinLibraryItem {
        JellyfinLibraryItem(
            id: id,
            name: name,
            type: type,
            overview: overview,
            productionYear: productionYear,
            communityRating: communityRating,
            officialRating: officialRating,
            runtimeTicks: runtimeTicks,
            premiereDateText: premiereDateText,
            primaryImageTag: primaryImageTag,
            childCount: childCount,
            isFolder: isFolder,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            playbackPositionTicks: playbackPositionTicks,
            isFavorite: isFavorite
        )
    }
}

enum JellyfinLibraryItemKind: Equatable, Sendable {
    case movie
    case series
    case season
    case episode
    case folder
    case other

    init(type: String?, isFolder: Bool) {
        switch type?.lowercased() {
        case "movie":
            self = .movie
        case "series":
            self = .series
        case "season":
            self = .season
        case "episode":
            self = .episode
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
        case .season:
            return "季度"
        case .episode:
            return "剧集"
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
        ServerURLNormalizer.normalize(rawValue, defaultScheme: "https", defaultPort: 8096)
    }
}

enum JellyfinPlaybackFormatting {
    static func positionText(from ticks: Int64?) -> String? {
        guard let ticks, ticks > 0 else {
            return nil
        }

        let totalSeconds = Int((Double(ticks) / 10_000_000).rounded(.down))
        guard totalSeconds > 0 else {
            return nil
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
