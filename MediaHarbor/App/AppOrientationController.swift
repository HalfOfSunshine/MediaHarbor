import UIKit

enum AppOrientationController {
    enum PlaybackOrientationMode: Equatable {
        case portrait
        case landscape

        var supportedMask: UIInterfaceOrientationMask {
            switch self {
            case .portrait:
                return .portrait
            case .landscape:
                return .landscape
            }
        }

        var requestedOrientation: UIInterfaceOrientationMask {
            switch self {
            case .portrait:
                return .portrait
            case .landscape:
                return .landscapeRight
            }
        }

        var toggleTarget: PlaybackOrientationMode {
            switch self {
            case .portrait:
                return .landscape
            case .landscape:
                return .portrait
            }
        }
    }

    static var orientationLock: UIInterfaceOrientationMask = .portrait
    static var playbackOrientationMode: PlaybackOrientationMode = .portrait

    @MainActor
    static func setPlaybackOrientationMode(_ mode: PlaybackOrientationMode) {
        playbackOrientationMode = mode
        orientationLock = mode.supportedMask

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        if let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController {
            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mode.requestedOrientation))
    }

    @MainActor
    static func togglePlaybackOrientationMode() {
        setPlaybackOrientationMode(playbackOrientationMode.toggleTarget)
    }
}

final class MediaHarborAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.orientationLock
    }
}
