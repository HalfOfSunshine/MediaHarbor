import SwiftUI

struct QBittorrentServerCard: View {
    let session: QBittorrentSessionSnapshot
    let isRefreshing: Bool
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("qBittorrent")
                        .font(.title3.weight(.semibold))

                    Text(session.serverURLString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button(action: refreshAction) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                DetailPill(title: "用户", value: session.username)

                if let version = session.version {
                    DetailPill(title: "版本", value: version)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.20, blue: 0.16),
                            Color(red: 0.12, green: 0.35, blue: 0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundStyle(.white)
    }
}

struct QBittorrentTransferOverviewCard: View {
    let info: QBittorrentTransferInfo
    let torrentCount: Int
    let activeTorrentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("传输概览")
                    .font(.headline)

                Spacer()

                Text(info.connectionStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.04, green: 0.43, blue: 0.28))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.83, green: 0.94, blue: 0.87), in: Capsule())
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                QBMetricCard(title: "下载速度", value: info.downloadSpeedText, symbolName: "arrow.down.circle.fill", tint: .blue)
                QBMetricCard(title: "上传速度", value: info.uploadSpeedText, symbolName: "arrow.up.circle.fill", tint: .green)
                QBMetricCard(title: "任务总数", value: "\(torrentCount)", symbolName: "list.bullet.rectangle.fill", tint: .orange)
                QBMetricCard(title: "活跃任务", value: "\(activeTorrentCount)", symbolName: "bolt.fill", tint: .pink)
            }

            Text("累计下载 \(info.downloadedDataText) · 累计上传 \(info.uploadedDataText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }
}

struct QBMetricCard: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct QBTorrentRow: View {
    let torrent: QBTorrent
    let isBusy: Bool
    let toggleAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(torrent.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(torrent.detailSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                QBTorrentStateBadge(torrent: torrent)
            }

            ProgressView(value: torrent.normalizedProgress)
                .tint(progressTint)

            HStack {
                Text(torrent.progressValueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let speedSummaryText = torrent.speedSummaryText {
                    Text(speedSummaryText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let extraSummaryText = torrent.extraSummaryText {
                Text(extraSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let locationText = torrent.locationText {
                Text(locationText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button(action: toggleAction) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(torrent.primaryActionTitle, systemImage: torrent.canResume ? "play.fill" : "pause.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || (torrent.canResume == false && torrent.canPause == false))

                Button("删除", role: .destructive, action: deleteAction)
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var progressTint: Color {
        switch torrent.stateCategory {
        case .downloading:
            return .blue
        case .seeding, .finished:
            return .green
        case .paused:
            return .gray
        case .checking, .queued, .stalled:
            return .orange
        case .error, .unknown:
            return .red
        }
    }
}

struct QBTorrentPaginationCard: View {
    @Binding var pageSize: QBTorrentPageSize
    @Binding var sortKey: QBittorrentTorrentSortKey
    @Binding var sortDirection: QBittorrentTorrentSortDirection

    let currentPage: Int
    let totalPages: Int
    let itemRangeText: String
    let previousAction: () -> Void
    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分页展示")
                        .font(.headline)

                    Text(itemRangeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker("每页", selection: $pageSize) {
                    ForEach(QBTorrentPageSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                Picker("排序字段", selection: $sortKey) {
                    ForEach(QBittorrentTorrentSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.menu)

                Picker("排序方向", selection: $sortDirection) {
                    ForEach(QBittorrentTorrentSortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                Button(action: previousAction) {
                    Label("上一页", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(currentPage <= 0)

                Text("第 \(currentPage + 1) / \(totalPages) 页")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                Button(action: nextAction) {
                    Label("下一页", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(currentPage >= totalPages - 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct QBTorrentStateBadge: View {
    let torrent: QBTorrent

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(torrent.stateText)
                .font(.caption.weight(.semibold))

            Text(torrent.progressText)
                .font(.caption2)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        switch torrent.stateCategory {
        case .downloading:
            return .blue
        case .seeding, .finished:
            return Color(red: 0.04, green: 0.43, blue: 0.28)
        case .paused:
            return .secondary
        case .checking, .queued, .stalled:
            return Color(red: 0.75, green: 0.39, blue: 0.08)
        case .error, .unknown:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch torrent.stateCategory {
        case .downloading:
            return Color.blue.opacity(0.14)
        case .seeding, .finished:
            return Color(red: 0.83, green: 0.94, blue: 0.87)
        case .paused:
            return Color(.tertiarySystemFill)
        case .checking, .queued, .stalled:
            return Color(red: 0.97, green: 0.90, blue: 0.76)
        case .error, .unknown:
            return Color.red.opacity(0.12)
        }
    }
}
