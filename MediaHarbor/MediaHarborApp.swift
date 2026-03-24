//
//  MediaHarborApp.swift
//  MediaHarbor
//
//  Created by mamingkang on 2026/3/24.
//

import SwiftUI

@main
struct MediaHarborApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
