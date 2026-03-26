import Foundation

enum AppTab: Hashable {
    case home
    case library
    case downloads
    case settings

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .library:
            return "媒体库"
        case .downloads:
            return "下载"
        case .settings:
            return "设置"
        }
    }

    var iconAssetName: String {
        switch self {
        case .home:
            return "TabHome"
        case .library:
            return "TabLibrary"
        case .downloads:
            return "TabDownloads"
        case .settings:
            return "TabSettings"
        }
    }

    var selectedIconAssetName: String {
        switch self {
        case .home:
            return "TabHomeActive"
        case .library:
            return "TabLibraryActive"
        case .downloads:
            return "TabDownloadsActive"
        case .settings:
            return "TabSettingsActive"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .home:
            return "house"
        case .library:
            return "film"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gearshape"
        }
    }
}
