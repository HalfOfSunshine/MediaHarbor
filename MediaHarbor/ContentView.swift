import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
                }
                .tag(AppTab.home)

            LibraryView()
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.systemImage)
                }
                .tag(AppTab.library)

            DownloadsView()
                .tabItem {
                    Label(AppTab.downloads.title, systemImage: AppTab.downloads.systemImage)
                }
                .tag(AppTab.downloads)

            SettingsView()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
