//
//  MediaHarborApp.swift
//  MediaHarbor
//
//  Created by mamingkang on 2026/3/24.
//

import SwiftUI

@main
struct MediaHarborApp: App {
    @UIApplicationDelegateAdaptor(MediaHarborAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        MediaHarborTheme.configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
