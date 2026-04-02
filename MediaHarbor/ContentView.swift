import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            LibraryView()
                .tabItem {
                    tabBarItem(for: .library)
                }
                .tag(AppTab.library)

            if appState.browser.isEnabled {
                BrowserView()
                    .tabItem {
                        tabBarItem(for: .browser)
                    }
                    .tag(AppTab.browser)
            }

            DownloadsView()
                .tabItem {
                    tabBarItem(for: .downloads)
                }
                .tag(AppTab.downloads)

            SettingsView()
                .tabItem {
                    tabBarItem(for: .settings)
                }
                .tag(AppTab.settings)
        }
        .tint(MediaHarborTheme.tabSelectedColor)
    }

    @ViewBuilder
    private func tabBarItem(for tab: AppTab) -> some View {
        let assetName = appState.selectedTab == tab ? tab.selectedIconAssetName : tab.iconAssetName

        if let image = UIImage(named: assetName)?.withRenderingMode(.alwaysOriginal) {
            Image(uiImage: image)
            Text(tab.title)
        } else {
            Image(systemName: tab.fallbackSystemImage)
            Text(tab.title)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
