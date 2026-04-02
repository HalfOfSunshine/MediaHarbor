import Observation

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .library
    let jellyfin: JellyfinStore
    let qbittorrent: QBittorrentStore
    let browser: BrowserStore
    let jellyfinPlaybackPreferences: JellyfinPlaybackPreferences

    init(
        jellyfin: JellyfinStore? = nil,
        qbittorrent: QBittorrentStore? = nil,
        browser: BrowserStore? = nil,
        jellyfinPlaybackPreferences: JellyfinPlaybackPreferences? = nil
    ) {
        self.jellyfin = jellyfin ?? JellyfinStore()
        self.qbittorrent = qbittorrent ?? QBittorrentStore()
        self.browser = browser ?? BrowserStore()
        self.jellyfinPlaybackPreferences = jellyfinPlaybackPreferences ?? JellyfinPlaybackPreferences()
    }
}
