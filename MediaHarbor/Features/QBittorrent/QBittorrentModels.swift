import Foundation

struct QBittorrentSessionSnapshot: Codable, Equatable, Sendable, Identifiable {
    let serverURLString: String
    let username: String
    let version: String?

    var id: String {
        accountKey
    }

    var accountKey: String {
        "\(serverURLString.lowercased())|\(username.lowercased())"
    }

    var serverName: String {
        URL(string: serverURLString)?.host ?? serverURLString
    }
}

struct QBittorrentTransferInfo: Equatable, Sendable {
    let connectionStatus: String?
    let dhtNodes: Int?
    let downloadedData: Int64
    let downloadSpeed: Int64
    let downloadRateLimit: Int64?
    let uploadedData: Int64
    let uploadSpeed: Int64
    let uploadRateLimit: Int64?
    let externalAddressV4: String?
    let externalAddressV6: String?

    var connectionStatusText: String {
        switch connectionStatus?.lowercased() {
        case "connected":
            return "已连接"
        case "firewalled":
            return "受限"
        case "disconnected":
            return "未连接"
        default:
            return "状态未知"
        }
    }

    var downloadSpeedText: String {
        formattedSpeed(downloadSpeed)
    }

    var uploadSpeedText: String {
        formattedSpeed(uploadSpeed)
    }

    var downloadedDataText: String {
        formattedByteCount(downloadedData)
    }

    var uploadedDataText: String {
        formattedByteCount(uploadedData)
    }
}

struct QBTorrent: Identifiable, Equatable, Sendable {
    let hash: String
    let name: String
    let progress: Double
    let state: String
    let size: Int64
    let totalSize: Int64
    let downloaded: Int64
    let uploaded: Int64
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let eta: Int64
    let ratio: Double
    let category: String
    let tags: String
    let savePath: String
    let addedOn: Date?

    var id: String {
        hash
    }

    var normalizedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    var progressText: String {
        "\(Int((normalizedProgress * 100).rounded()))%"
    }

    var progressValueText: String {
        let completedText = formattedByteCount(Int64(Double(displaySize) * normalizedProgress))
        return "\(completedText) / \(sizeText)"
    }

    var sizeText: String {
        formattedByteCount(displaySize)
    }

    var downloadedText: String {
        formattedByteCount(downloaded)
    }

    var uploadedText: String {
        formattedByteCount(uploaded)
    }

    var downloadSpeedText: String {
        formattedSpeed(downloadSpeed)
    }

    var uploadSpeedText: String {
        formattedSpeed(uploadSpeed)
    }

    var ratioText: String {
        guard ratio.isFinite else {
            return "--"
        }

        return String(format: "%.2f", ratio)
    }

    var etaText: String? {
        guard normalizedProgress < 1 else {
            return nil
        }

        if eta < 0 || eta >= 8_640_000 {
            return "剩余时间未知"
        }

        return formattedDuration(eta)
    }

    var stateCategory: QBTorrentStateCategory {
        let loweredState = state.lowercased()

        if loweredState == "missingfiles" || loweredState.contains("error") {
            return .error
        }

        if loweredState.contains("checking") {
            return .checking
        }

        if loweredState.hasPrefix("paused") {
            return .paused
        }

        if loweredState.hasPrefix("queued") {
            return .queued
        }

        if loweredState == "stalleddl" {
            return .stalled
        }

        if loweredState == "stalledup" {
            return normalizedProgress >= 1 ? .finished : .stalled
        }

        if loweredState.contains("down") || loweredState == "metadl" {
            return .downloading
        }

        if loweredState.contains("up") {
            return uploadSpeed > 0 ? .seeding : .finished
        }

        return normalizedProgress >= 1 ? .finished : .unknown
    }

    var stateText: String {
        switch stateCategory {
        case .downloading:
            return downloadSpeed > 0 ? "下载中" : "等待下载"
        case .seeding:
            return uploadSpeed > 0 ? "上传中" : "做种中"
        case .paused:
            return "已暂停"
        case .checking:
            return "校验中"
        case .queued:
            return normalizedProgress >= 1 ? "排队做种" : "排队下载"
        case .error:
            return "异常"
        case .finished:
            return normalizedProgress >= 1 ? "已完成" : "等待中"
        case .stalled:
            return normalizedProgress >= 1 ? "等待做种" : "等待下载"
        case .unknown:
            return "状态未知"
        }
    }

    var speedSummaryText: String? {
        let parts = [
            downloadSpeed > 0 ? "↓ \(downloadSpeedText)" : nil,
            uploadSpeed > 0 ? "↑ \(uploadSpeedText)" : nil,
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var detailSummaryText: String {
        [
            progressText,
            sizeText,
            "分享率 \(ratioText)",
        ].joined(separator: " · ")
    }

    var extraSummaryText: String? {
        let parts = [
            etaText,
            category.isEmpty ? nil : "分类 \(category)",
            tags.isEmpty ? nil : "标签 \(tags)",
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var locationText: String? {
        let trimmed = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canResume: Bool {
        stateCategory == .paused
    }

    var canPause: Bool {
        switch stateCategory {
        case .paused, .checking, .error:
            return false
        default:
            return true
        }
    }

    var primaryActionTitle: String {
        canResume ? "继续" : "暂停"
    }

    func matches(searchTerm: String) -> Bool {
        let trimmed = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return true
        }

        let loweredSearch = trimmed.lowercased()
        return [
            name.lowercased(),
            category.lowercased(),
            tags.lowercased(),
            savePath.lowercased(),
        ].contains { $0.contains(loweredSearch) }
    }

    private var displaySize: Int64 {
        max(totalSize, size)
    }
}

enum QBTorrentStateCategory: Sendable {
    case downloading
    case seeding
    case paused
    case checking
    case queued
    case error
    case finished
    case stalled
    case unknown
}

enum QBTorrentPageSize: Int, CaseIterable, Identifiable, Sendable {
    case twenty = 20
    case fifty = 50
    case hundred = 100

    var id: Int {
        rawValue
    }

    var title: String {
        "\(rawValue) 项"
    }
}

enum QBTorrentPagination {
    static func totalPages(itemCount: Int, pageSize: Int) -> Int {
        guard itemCount > 0, pageSize > 0 else {
            return 1
        }

        return Int(ceil(Double(itemCount) / Double(pageSize)))
    }

    static func normalizedPageIndex(_ pageIndex: Int, itemCount: Int, pageSize: Int) -> Int {
        let totalPages = totalPages(itemCount: itemCount, pageSize: pageSize)
        return min(max(pageIndex, 0), totalPages - 1)
    }

    static func items<T>(_ items: [T], pageIndex: Int, pageSize: Int) -> ArraySlice<T> {
        guard items.isEmpty == false, pageSize > 0 else {
            return []
        }

        let safePageIndex = normalizedPageIndex(pageIndex, itemCount: items.count, pageSize: pageSize)
        let lowerBound = safePageIndex * pageSize
        let upperBound = min(lowerBound + pageSize, items.count)
        return items[lowerBound ..< upperBound]
    }

    static func rangeText(itemCount: Int, pageIndex: Int, pageSize: Int) -> String {
        guard itemCount > 0, pageSize > 0 else {
            return "第 0-0 项，共 0 项"
        }

        let safePageIndex = normalizedPageIndex(pageIndex, itemCount: itemCount, pageSize: pageSize)
        let lowerBound = safePageIndex * pageSize + 1
        let upperBound = min((safePageIndex + 1) * pageSize, itemCount)
        return "第 \(lowerBound)-\(upperBound) 项，共 \(itemCount) 项"
    }
}

enum QBittorrentServerURL {
    static func normalize(_ rawValue: String) -> URL? {
        ServerURLNormalizer.normalize(rawValue, defaultScheme: "http", defaultPort: 8899)
    }
}

private let qbByteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB, .useKB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.isAdaptive = true
    formatter.zeroPadsFractionDigits = false
    return formatter
}()

private let qbDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter
}()

private func formattedByteCount(_ value: Int64) -> String {
    qbByteCountFormatter.string(fromByteCount: max(value, 0))
}

private func formattedSpeed(_ bytesPerSecond: Int64) -> String {
    "\(formattedByteCount(bytesPerSecond))/s"
}

private func formattedDuration(_ seconds: Int64) -> String? {
    qbDurationFormatter.string(from: TimeInterval(max(seconds, 0)))
}
