import Observation

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    let jellyfin: JellyfinStore
    let qbittorrent: QBittorrentStore

    init(jellyfin: JellyfinStore? = nil, qbittorrent: QBittorrentStore? = nil) {
        self.jellyfin = jellyfin ?? JellyfinStore()
        self.qbittorrent = qbittorrent ?? QBittorrentStore()
    }
}
