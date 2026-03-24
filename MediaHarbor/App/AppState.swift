import Observation

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    let jellyfin: JellyfinStore

    init(jellyfin: JellyfinStore? = nil) {
        self.jellyfin = jellyfin ?? JellyfinStore()
    }
}
