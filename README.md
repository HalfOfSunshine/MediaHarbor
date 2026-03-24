# MediaHarbor

MediaHarbor is an iOS app for managing a personal NAS movie library.

## Tech Direction

- SwiftUI app shell
- Native Jellyfin and qBittorrent integrations
- Hybrid MoviePilot experience with API plus `WKWebView`
- `AVPlayer` for later playback support

## Getting Started

1. Open `/Users/mamingkang/Desktop/NASMovies/MediaHarbor/MediaHarbor.xcodeproj` in Xcode.
2. Select the `MediaHarbor` scheme.
3. Build and run on an iOS 17+ simulator or device.

## Repo Notes

- Dependency management should prefer Swift Package Manager.
- Secrets and server credentials should stay in Keychain or local config, not in git.
- Early focus is on app shell, server management, and core media/download workflows.
