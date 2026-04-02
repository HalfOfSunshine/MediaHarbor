import Foundation

enum AppTab: Hashable {
    case library
    case browser
    case downloads
    case settings

    var title: String {
        switch self {
        case .library:
            return "媒体库"
        case .browser:
            return "浏览器"
        case .downloads:
            return "下载"
        case .settings:
            return "设置"
        }
    }

    var iconAssetName: String {
        switch self {
        case .library:
            return "TabLibrary"
        case .browser:
            return "TabBrowser"
        case .downloads:
            return "TabDownloads"
        case .settings:
            return "TabSettings"
        }
    }

    var selectedIconAssetName: String {
        switch self {
        case .library:
            return "TabLibraryActive"
        case .browser:
            return "TabBrowserActive"
        case .downloads:
            return "TabDownloadsActive"
        case .settings:
            return "TabSettingsActive"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .library:
            return "film"
        case .browser:
            return "safari"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gearshape"
        }
    }
}
