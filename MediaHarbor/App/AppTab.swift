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

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .library:
            return "film.stack.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}
