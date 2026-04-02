import AVKit
import Observation
import SwiftUI

struct JellyfinPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let streamURL: URL
    let routeText: String
    let startPositionTicks: Int64?

    @State private var controller = JellyfinPlayerController()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            JellyfinAVPlayerViewController(player: controller.player)
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    if controller.isBuffering {
                        Label("正在缓冲", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Text(controller.routeText)
                        if let startPositionText = controller.startPositionText {
                            Text("起播点 \(startPositionText)")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.88))

                    Text("\(controller.currentTimeText) / \(controller.durationText) · \(controller.statusText)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .ignoresSafeArea(edges: .bottom)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.56), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 18)
        }
        .task(id: "\(streamURL.absoluteString)|\(startPositionTicks ?? 0)") {
            controller.load(url: streamURL, routeText: routeText, startPositionTicks: startPositionTicks)
        }
        .onDisappear {
            controller.reset()
        }
        .statusBarHidden()
        .accessibilityIdentifier("jellyfin.player.screen")
    }
}

@MainActor
@Observable
final class JellyfinPlayerController {
    let player = AVPlayer()

    var statusText = "正在初始化"
    var currentTimeText = "00:00"
    var durationText = "--:--"
    var routeText = "App 内播放"
    var isBuffering = true
    var startPositionText: String?

    @ObservationIgnored
    private var periodicTimeObserver: Any?

    @ObservationIgnored
    private var itemStatusObservation: NSKeyValueObservation?

    @ObservationIgnored
    private var timeControlObservation: NSKeyValueObservation?

    func load(url: URL, routeText: String, startPositionTicks: Int64?) {
        reset()

        self.routeText = routeText
        startPositionText = JellyfinPlaybackFormatting.positionText(from: startPositionTicks)
        statusText = "正在初始化"
        isBuffering = true

        let item = AVPlayerItem(url: url)
        observe(playerItem: item, startPositionTicks: startPositionTicks)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func reset() {
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil

        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(playerItem: AVPlayerItem, startPositionTicks: Int64?) {
        itemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    if let startPositionTicks, startPositionTicks > 0 {
                        let seconds = Double(startPositionTicks) / 10_000_000
                        let time = CMTime(seconds: seconds, preferredTimescale: 600)
                        self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    }

                    self.durationText = Self.formattedTime(from: item.duration)
                    self.statusText = "正在播放"
                case .failed:
                    self.statusText = item.error?.localizedDescription ?? "播放失败"
                    self.isBuffering = false
                default:
                    self.statusText = "正在初始化"
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch player.timeControlStatus {
                case .paused:
                    if player.currentItem?.status == .readyToPlay {
                        self.statusText = "已暂停"
                    }
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.statusText = "正在缓冲"
                    self.isBuffering = true
                case .playing:
                    self.statusText = "正在播放"
                    self.isBuffering = false
                @unknown default:
                    self.statusText = "正在初始化"
                    self.isBuffering = true
                }
            }
        }

        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTimeText = Self.formattedTime(from: time)
                if let duration = self.player.currentItem?.duration, duration.isNumeric {
                    self.durationText = Self.formattedTime(from: duration)
                }
            }
        }
    }

    private static func formattedTime(from time: CMTime) -> String {
        guard time.isNumeric, time.seconds.isFinite, time.seconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(time.seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct JellyfinAVPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.view.backgroundColor = .black
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
