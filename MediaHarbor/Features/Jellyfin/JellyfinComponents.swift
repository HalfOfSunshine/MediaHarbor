import SwiftUI

private struct JellyfinPlaybackDestinationActionCard: View {
    let iconName: String
    let title: String
    let summary: String
    let selectedTarget: JellyfinPlaybackOpenTarget
    let availableTargets: [JellyfinPlaybackOpenTarget]
    let action: () -> Void
    let onSelectTarget: (JellyfinPlaybackOpenTarget) -> Void

    var body: some View {
            HStack(spacing: 12) {
                Button(action: action) {
                    HStack(spacing: 12) {
                        Image(systemName: iconName)
                            .font(.title3.weight(.semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)

                            Text(summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if availableTargets.isEmpty == false {
                    Menu {
                        ForEach(availableTargets) { target in
                            Button {
                                onSelectTarget(target)
                            } label: {
                                Label(
                                    target.title,
                                    systemImage: selectedTarget == target ? "checkmark" : target.iconName
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct JellyfinServerCard: View {
    let session: JellyfinSessionSnapshot
    let isRefreshing: Bool
    var showsServerURL: Bool = true
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.serverName)
                        .font(.title3.weight(.semibold))

                    if showsServerURL {
                        Text(session.serverURLString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
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

                if let version = session.serverVersion {
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
                            Color(red: 0.12, green: 0.19, blue: 0.24),
                            Color(red: 0.19, green: 0.27, blue: 0.34),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundStyle(.white)
    }
}

struct DetailPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct JellyfinSavedSessionRow: View {
    let session: JellyfinSessionSnapshot
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                    .frame(width: 42, height: 42)

                Image(systemName: isActive ? "checkmark.circle.fill" : "person.crop.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.username)
                        .font(.headline)

                    if isActive {
                        Text("当前")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                Text(session.serverSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(session.serverURLString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }
}

struct JellyfinLibraryChip: View {
    let library: JellyfinLibrary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(library.name)
                .font(.headline)

            Text(library.subtitle)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.17) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

struct JellyfinLibraryListCard: View {
    let library: JellyfinLibrary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                    .frame(width: 56, height: 56)

                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(library.name)
                    .font(.headline)

                Text(library.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch library.kind {
        case .movies:
            return "film.fill"
        case .tvShows:
            return "tv.fill"
        case .mixed:
            return "square.stack.3d.up.fill"
        case .homeVideos:
            return "video.fill"
        case .collections:
            return "rectangle.stack.fill"
        case .other:
            return "externaldrive.fill"
        }
    }
}

struct JellyfinManagedLibraryRow: View {
    let library: JellyfinLibrary
    let isRefreshing: Bool
    let isActionDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(library.name)
                    .font(.headline)

                Text(library.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: action) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isActionDisabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch library.kind {
        case .movies:
            return "film.fill"
        case .tvShows:
            return "tv.fill"
        case .mixed:
            return "square.stack.3d.up.fill"
        case .homeVideos:
            return "video.fill"
        case .collections:
            return "rectangle.stack.fill"
        case .other:
            return "externaldrive.fill"
        }
    }
}

struct JellyfinLibraryHeroCard: View {
    let library: JellyfinLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(library.name)
                .font(.title2.weight(.bold))

            Text(library.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("当前页展示的是这个媒体库里的主要电影和电视剧条目。单库刷新会调用 Jellyfin 官方的当前库项目刷新接口；如果你需要完整的全库文件扫描，请使用“扫描所有媒体库”。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct JellyfinMovieCard: View {
    @Environment(AppState.self) private var appState

    let movie: JellyfinMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JellyfinPosterArtwork(
                url: appState.jellyfin.primaryImageURL(for: movie, maxWidth: 440, maxHeight: 660),
                height: 180,
                cornerRadius: 20,
                symbolName: "film.stack.fill"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.yearText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let playbackPositionText = movie.playbackPositionText {
                        Text("看到 \(playbackPositionText)")
                    } else {
                        Text(movie.yearText)
                    }

                    if movie.isFavorite {
                        Image(systemName: "heart.fill")
                    }

                    if movie.playbackPositionText == nil {
                        EmptyView()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(movie.yearText)

                    if let rating = movie.ratingText {
                        Text("评分 \(rating)")
                    }

                    if let runtime = movie.runtimeText {
                        Text(runtime)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(movie.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct JellyfinLibraryItemCard: View {
    @Environment(AppState.self) private var appState

    let item: JellyfinLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JellyfinPosterArtwork(
                url: appState.jellyfin.primaryImageURL(for: item, maxWidth: 440, maxHeight: 660),
                height: 180,
                cornerRadius: 20,
                symbolName: item.posterSymbolName
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.episodeText ?? item.metaText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let playbackPositionText = item.playbackPositionText {
                        Text("看到 \(playbackPositionText)")
                    } else if let episodeText = item.episodeText {
                        Text(episodeText)
                    } else {
                        Text(item.metaText)
                    }

                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(item.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct JellyfinMovieGridCard: View {
    @Environment(AppState.self) private var appState

    let movie: JellyfinMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JellyfinPosterArtwork(
                url: appState.jellyfin.primaryImageURL(for: movie, maxWidth: 520, maxHeight: 780),
                height: 180,
                cornerRadius: 18,
                symbolName: "film.fill"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(movie.yearText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    if let rating = movie.ratingText {
                        Text("评分 \(rating)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(14)
            }

            Text(movie.name)
                .font(.headline)
                .lineLimit(2)

            Text(movie.summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct JellyfinLibraryItemGridCard: View {
    @Environment(AppState.self) private var appState

    let item: JellyfinLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JellyfinPosterArtwork(
                url: appState.jellyfin.primaryImageURL(for: item, maxWidth: 520, maxHeight: 780),
                height: 180,
                cornerRadius: 18,
                symbolName: item.posterSymbolName
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.metaText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))

                    if let rating = item.ratingText {
                        Text("评分 \(rating)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(14)
            }

            Text(item.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(item.yearText)

                if let runtime = item.runtimeText {
                    Text(runtime)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(item.summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "externaldrive.fill.badge.wifi")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct JellyfinTaskRow: View {
    let task: JellyfinTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.headline)

                    if let summary = task.summary, summary.isEmpty == false {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                TaskStateBadge(state: task.state, progressText: task.progressText)
            }

            if let category = task.category, category.isEmpty == false {
                Text(category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TaskStateBadge: View {
    let state: JellyfinTaskState
    let progressText: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(state.title)
                .font(.caption.weight(.semibold))

            if let progressText {
                Text(progressText)
                    .font(.caption2)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var foregroundColor: Color {
        switch state {
        case .idle:
            return .secondary
        case .cancelling:
            return Color(red: 0.75, green: 0.39, blue: 0.08)
        case .running:
            return Color(red: 0.04, green: 0.43, blue: 0.28)
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle:
            return Color(.tertiarySystemFill)
        case .cancelling:
            return Color(red: 0.97, green: 0.90, blue: 0.76)
        case .running:
            return Color(red: 0.83, green: 0.94, blue: 0.87)
        }
    }
}

struct JellyfinInfoNote: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct JellyfinEpisodeBrowserSection: View {
    @Environment(AppState.self) private var appState

    let item: JellyfinLibraryItem

    @State private var episodes: [JellyfinLibraryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sectionTitle)
                .font(.headline)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载剧集列表…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                JellyfinInfoNote(title: "加载失败", message: errorMessage)
            } else if groupedEpisodes.isEmpty {
                JellyfinInfoNote(title: sectionTitle, message: "Jellyfin 还没有返回可播放的剧集。")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedEpisodes, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(group.items) { episode in
                                NavigationLink {
                                    JellyfinLibraryItemDetailView(item: episode)
                                } label: {
                                    JellyfinEpisodeRow(item: episode)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .id("episode-browser")
        .task(id: item.id) {
            await loadEpisodes()
        }
    }

    private var sectionTitle: String {
        item.kind == .season ? "剧集" : "选集"
    }

    private var groupedEpisodes: [EpisodeGroup] {
        let sortedEpisodes = episodes.sorted { lhs, rhs in
            let lhsSeason = lhs.parentIndexNumber ?? 0
            let rhsSeason = rhs.parentIndexNumber ?? 0
            if lhsSeason != rhsSeason {
                return lhsSeason < rhsSeason
            }

            let lhsEpisode = lhs.indexNumber ?? 0
            let rhsEpisode = rhs.indexNumber ?? 0
            if lhsEpisode != rhsEpisode {
                return lhsEpisode < rhsEpisode
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if item.kind == .season {
            return [EpisodeGroup(id: item.id, title: item.metaText, items: sortedEpisodes)]
        }

        let grouped = Dictionary(grouping: sortedEpisodes) { $0.parentIndexNumber ?? 0 }
        return grouped
            .keys
            .sorted()
            .map { seasonNumber in
                EpisodeGroup(
                    id: "\(item.id)|\(seasonNumber)",
                    title: seasonNumber > 0 ? "第 \(seasonNumber) 季" : "未标记季度",
                    items: grouped[seasonNumber] ?? []
                )
            }
    }

    private func loadEpisodes() async {
        guard item.kind == .series || item.kind == .season else {
            episodes = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            episodes = try await appState.jellyfin.childItems(for: item)
                .filter { $0.kind == .episode }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct EpisodeGroup {
        let id: String
        let title: String
        let items: [JellyfinLibraryItem]
    }
}

private struct JellyfinEpisodeRow: View {
    let item: JellyfinLibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let episodeText = item.episodeText {
                        Text(episodeText)
                    }

                    if let runtimeText = item.runtimeText {
                        Text(runtimeText)
                    }

                    if let playbackPositionText = item.playbackPositionText {
                        Text("看到 \(playbackPositionText)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct JellyfinMovieDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let movie: JellyfinMovie

    @State private var playbackOpenErrorMessage: String?
    @State private var internalPlayerSession: JellyfinInternalPlayerSession?
    @State private var isOpeningPlayback = false
    @State private var isFavorite: Bool
    @State private var favoriteErrorMessage: String?

    init(movie: JellyfinMovie) {
        self.movie = movie
        _isFavorite = State(initialValue: movie.isFavorite)
    }

    private var selectedPlaybackTarget: JellyfinPlaybackOpenTarget {
        appState.jellyfinPlaybackPreferences.preferredOpenTarget
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                JellyfinPosterArtwork(
                    url: appState.jellyfin.primaryImageURL(for: movie, maxWidth: 900, maxHeight: 1350),
                    height: 260,
                    cornerRadius: 28,
                    symbolName: "film.stack.fill"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movie.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 10) {
                            Text(movie.yearText)

                            if let rating = movie.ratingText {
                                Text("评分 \(rating)")
                            }

                            if let runtime = movie.runtimeText {
                                Text(runtime)
                            }
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.86))
                    }
                    .padding(20)
                }

                if let officialRating = movie.officialRating {
                    Label(officialRating, systemImage: "checkmark.shield.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                JellyfinPlaybackDestinationActionCard(
                    iconName: isOpeningPlayback ? "hourglass" : selectedPlaybackTarget.iconName,
                    title: isOpeningPlayback ? "正在准备播放" : selectedPlaybackTarget.actionTitle(playbackPositionText: movie.playbackPositionText),
                    summary: isOpeningPlayback ? "正在向 Jellyfin 请求可播放的视频流。" : selectedPlaybackTarget.actionSummary(playbackPositionText: movie.playbackPositionText),
                    selectedTarget: selectedPlaybackTarget,
                    availableTargets: JellyfinPlaybackOpenTarget.allCases
                ) {
                    Task {
                        await openPlaybackTarget(selectedPlaybackTarget)
                    }
                } onSelectTarget: { target in
                    appState.jellyfinPlaybackPreferences.preferredOpenTarget = target
                }

                Text(movie.summaryText)
                    .font(.body)
                    .lineSpacing(4)
            }
            .padding()
        }
        .navigationTitle(movie.name)
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await toggleFavorite()
                    }
                } label: {
                    if appState.jellyfin.favoriteActionItemID == movie.id {
                        ProgressView()
                    } else {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }
                }
            }
        }
        .alert("打开失败", isPresented: Binding(
            get: { playbackOpenErrorMessage != nil },
            set: { newValue in
                if newValue == false {
                    playbackOpenErrorMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(playbackOpenErrorMessage ?? "")
        }
        .alert("收藏操作失败", isPresented: Binding(
            get: { favoriteErrorMessage != nil },
            set: { newValue in
                if newValue == false {
                    favoriteErrorMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
        .fullScreenCover(item: $internalPlayerSession) { session in
            JellyfinPlayerView(
                title: session.title,
                candidates: session.candidates,
                startPositionTicks: session.startPositionTicks
            )
        }
    }

    private func openPlaybackTarget(_ target: JellyfinPlaybackOpenTarget) async {
        do {
            if target == .app {
                guard isOpeningPlayback == false else {
                    return
                }

                isOpeningPlayback = true
                defer {
                    isOpeningPlayback = false
                }

                let stream = try await appState.jellyfin.playbackStream(for: movie.id)
                internalPlayerSession = JellyfinInternalPlayerSession(
                    title: movie.name,
                    candidates: stream.candidates,
                    startPositionTicks: movie.playbackPositionTicks
                )
                return
            }

            let url = try JellyfinExternalPlayback.targetURL(
                for: target,
                webURL: appState.jellyfin.webDetailsURL(for: movie.id),
                streamURL: movie.canOpenInExternalPlayer ? appState.jellyfin.directVideoURL(for: movie.id) : nil
            )
            openURL(url)
        } catch {
            playbackOpenErrorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite() async {
        let targetValue = !isFavorite

        do {
            try await appState.jellyfin.setFavorite(itemID: movie.id, isFavorite: targetValue)
            isFavorite = targetValue
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }
}

struct JellyfinLibraryItemDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let item: JellyfinLibraryItem

    @State private var playbackOpenErrorMessage: String?
    @State private var internalPlayerSession: JellyfinInternalPlayerSession?
    @State private var isOpeningPlayback = false
    @State private var isFavorite: Bool
    @State private var favoriteErrorMessage: String?

    init(item: JellyfinLibraryItem) {
        self.item = item
        _isFavorite = State(initialValue: item.isFavorite)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    JellyfinPosterArtwork(
                        url: appState.jellyfin.primaryImageURL(for: item, maxWidth: 900, maxHeight: 1350),
                        height: 260,
                        cornerRadius: 28,
                        symbolName: item.posterSymbolName
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)

                            HStack(spacing: 10) {
                                Text(item.metaText)
                                Text(item.yearText)

                                if let rating = item.ratingText {
                                    Text("评分 \(rating)")
                                }

                                if let runtime = item.runtimeText {
                                    Text(runtime)
                                }
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.86))
                        }
                        .padding(20)
                    }

                    if let officialRating = item.officialRating {
                        Label(officialRating, systemImage: "checkmark.shield.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if availableTargets.isEmpty == false {
                        JellyfinPlaybackDestinationActionCard(
                            iconName: isOpeningPlayback ? "hourglass" : actionCardIconName,
                            title: isOpeningPlayback ? "正在准备播放" : actionCardTitle,
                            summary: isOpeningPlayback ? "正在向 Jellyfin 请求可播放的视频流。" : actionCardSummary,
                            selectedTarget: selectedPlaybackTarget,
                            availableTargets: availableTargets
                        ) {
                            Task {
                                await handlePrimaryAction(proxy: proxy)
                            }
                        } onSelectTarget: { target in
                            appState.jellyfinPlaybackPreferences.preferredOpenTarget = target
                        }
                    }

                    Text(item.summaryText)
                        .font(.body)
                        .lineSpacing(4)

                    if showsEpisodeBrowser {
                        JellyfinEpisodeBrowserSection(item: item)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await toggleFavorite()
                    }
                } label: {
                    if appState.jellyfin.favoriteActionItemID == item.id {
                        ProgressView()
                    } else {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }
                }
            }
        }
        .alert("打开失败", isPresented: Binding(
            get: { playbackOpenErrorMessage != nil },
            set: { newValue in
                if newValue == false {
                    playbackOpenErrorMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(playbackOpenErrorMessage ?? "")
        }
        .alert("收藏操作失败", isPresented: Binding(
            get: { favoriteErrorMessage != nil },
            set: { newValue in
                if newValue == false {
                    favoriteErrorMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
        .fullScreenCover(item: $internalPlayerSession) { session in
            JellyfinPlayerView(
                title: session.title,
                candidates: session.candidates,
                startPositionTicks: session.startPositionTicks
            )
        }
    }

    private var preferredOpenTarget: JellyfinPlaybackOpenTarget {
        appState.jellyfinPlaybackPreferences.preferredOpenTarget
    }

    private var showsEpisodeBrowser: Bool {
        item.kind == .series || item.kind == .season
    }

    private var availableTargets: [JellyfinPlaybackOpenTarget] {
        if item.canOpenInExternalPlayer {
            return JellyfinPlaybackOpenTarget.allCases
        }

        if showsEpisodeBrowser {
            return [.app, .web]
        }

        return [.web]
    }

    private var selectedPlaybackTarget: JellyfinPlaybackOpenTarget {
        if availableTargets.contains(preferredOpenTarget) {
            return preferredOpenTarget
        }

        if availableTargets.contains(.app) {
            return .app
        }

        return availableTargets.first ?? .web
    }

    private var actionCardIconName: String {
        if showsEpisodeBrowser, selectedPlaybackTarget == .app {
            return "play.rectangle.fill"
        }

        return selectedPlaybackTarget.iconName
    }

    private var actionCardTitle: String {
        if showsEpisodeBrowser, selectedPlaybackTarget == .app {
            switch item.kind {
            case .series:
                return "查看选集"
            case .season:
                return "查看剧集"
            default:
                break
            }
        }

        return selectedPlaybackTarget.actionTitle(playbackPositionText: item.playbackPositionText)
    }

    private var actionCardSummary: String {
        if showsEpisodeBrowser, selectedPlaybackTarget == .app {
            switch item.kind {
            case .series:
                return "保留应用内选集逻辑。点开后先看剧集列表，再进入具体播放。"
            case .season:
                return "保留应用内选集逻辑。点开后先看这一季的剧集列表，再进入具体播放。"
            default:
                break
            }
        }

        return selectedPlaybackTarget.actionSummary(playbackPositionText: item.playbackPositionText)
    }

    private func handlePrimaryAction(proxy: ScrollViewProxy) async {
        if showsEpisodeBrowser, selectedPlaybackTarget == .app {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("episode-browser", anchor: .top)
            }
            return
        }

        await openPlaybackTarget(selectedPlaybackTarget)
    }

    private func openPlaybackTarget(_ target: JellyfinPlaybackOpenTarget) async {
        do {
            if target == .app {
                guard isOpeningPlayback == false else {
                    return
                }

                isOpeningPlayback = true
                defer {
                    isOpeningPlayback = false
                }

                let stream = try await appState.jellyfin.playbackStream(for: item.id)
                internalPlayerSession = JellyfinInternalPlayerSession(
                    title: item.name,
                    candidates: stream.candidates,
                    startPositionTicks: item.playbackPositionTicks
                )
                return
            }

            let url = try JellyfinExternalPlayback.targetURL(
                for: target,
                webURL: appState.jellyfin.webDetailsURL(for: item.id),
                streamURL: item.canOpenInExternalPlayer ? appState.jellyfin.directVideoURL(for: item.id) : nil
            )
            openURL(url)
        } catch {
            playbackOpenErrorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite() async {
        let targetValue = !isFavorite

        do {
            try await appState.jellyfin.setFavorite(itemID: item.id, isFavorite: targetValue)
            isFavorite = targetValue
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }
}

private struct JellyfinInternalPlayerSession: Identifiable {
    let title: String
    let candidates: [JellyfinPlaybackCandidate]
    let startPositionTicks: Int64?

    var id: String {
        let routeKey = candidates.map(\.routeDescription).joined(separator: "|")
        let urlKey = candidates.map(\.url.absoluteString).joined(separator: "|")
        return "\(title)|\(routeKey)|\(urlKey)|\(startPositionTicks ?? 0)"
    }
}
