import MobileVLCKit
import Observation
import SwiftUI
import UIKit

struct JellyfinPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let candidates: [JellyfinPlaybackCandidate]
    let startPositionTicks: Int64?

    @State private var controller = JellyfinPlayerController()
    @State private var playbackOrientationMode: AppOrientationController.PlaybackOrientationMode = .landscape

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            JellyfinVLCPlayerSurface(controller: controller)
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

            VStack {
                HStack {
                    Spacer()

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
                }

                Spacer()

                HStack {
                    Spacer()

                    Button {
                        togglePlaybackOrientation()
                    } label: {
                        Image(systemName: playbackOrientationButtonIconName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.56), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .task(id: candidateTaskID) {
            controller.load(candidates: candidates, startPositionTicks: startPositionTicks)
        }
        .onAppear {
            playbackOrientationMode = .landscape
            AppOrientationController.setPlaybackOrientationMode(.landscape)
        }
        .onDisappear {
            controller.reset()
            AppOrientationController.setPlaybackOrientationMode(.portrait)
        }
        .statusBarHidden()
        .accessibilityIdentifier("jellyfin.player.screen")
    }

    private var candidateTaskID: String {
        let candidateKey = candidates
            .map { "\($0.routeDescription)|\($0.url.absoluteString)" }
            .joined(separator: "||")
        return "\(candidateKey)|\(startPositionTicks ?? 0)"
    }

    private var playbackOrientationButtonIconName: String {
        switch playbackOrientationMode {
        case .portrait:
            return "rectangle.landscape.rotate"
        case .landscape:
            return "rectangle.portrait.rotate"
        }
    }

    private func togglePlaybackOrientation() {
        playbackOrientationMode = playbackOrientationMode.toggleTarget
        AppOrientationController.setPlaybackOrientationMode(playbackOrientationMode)
    }
}

private struct JellyfinVLCPlayerSurface: UIViewRepresentable {
    let controller: JellyfinPlayerController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attachDrawable(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.attachDrawable(uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.layer.sublayers?.removeAll()
    }
}

@MainActor
@Observable
final class JellyfinPlayerController: NSObject, VLCMediaPlayerDelegate {
    var statusText = "正在初始化"
    var currentTimeText = "00:00"
    var durationText = "--:--"
    var routeText = "App 内播放"
    var isBuffering = true
    var startPositionText: String?

    @ObservationIgnored
    private let player: VLCMediaPlayer

    @ObservationIgnored
    private weak var drawableView: UIView?

    @ObservationIgnored
    private var pendingStartMilliseconds: Int32?

    @ObservationIgnored
    private var didApplyInitialSeek = false

    @ObservationIgnored
    private var candidates: [JellyfinPlaybackCandidate] = []

    @ObservationIgnored
    private var currentCandidateIndex = 0

    @ObservationIgnored
    private var isSwitchingCandidate = false

    @ObservationIgnored
    private var hasLoadedCandidate = false

    override init() {
        self.player = VLCMediaPlayer(options: [
            "--no-video-title-show",
            "--network-caching=1000",
            "--clock-jitter=0",
            "--clock-synchro=0",
        ])
        super.init()
        player.delegate = self
    }

    deinit {
        player.delegate = nil
        player.stop()
    }

    func attachDrawable(_ view: UIView) {
        guard drawableView !== view else { return }
        drawableView = view
        player.drawable = view
    }

    func load(candidates: [JellyfinPlaybackCandidate], startPositionTicks: Int64?) {
        reset()

        self.candidates = candidates
        self.startPositionText = JellyfinPlaybackFormatting.positionText(from: startPositionTicks)
        self.pendingStartMilliseconds = Self.startMilliseconds(from: startPositionTicks)
        self.didApplyInitialSeek = pendingStartMilliseconds == nil
        self.statusText = "正在初始化"
        self.isBuffering = true
        self.currentTimeText = "00:00"
        self.durationText = "--:--"
        currentCandidateIndex = 0
        playCurrentCandidate()
    }

    func reset() {
        player.stop()
        player.media = nil
        candidates = []
        currentCandidateIndex = 0
        isSwitchingCandidate = false
        hasLoadedCandidate = false
        pendingStartMilliseconds = nil
        didApplyInitialSeek = false
        statusText = "正在初始化"
        isBuffering = true
        currentTimeText = "00:00"
        durationText = "--:--"
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            updateForCurrentState()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            updatePlaybackClock()
        }
    }

    private func updateForCurrentState() {
        switch player.state {
        case .opening:
            statusText = "正在初始化"
            isBuffering = true
        case .buffering, .esAdded:
            statusText = "正在缓冲"
            isBuffering = true
        case .playing:
            statusText = "正在播放"
            isBuffering = false
            applyInitialSeekIfNeeded()
            updatePlaybackClock()
        case .paused:
            statusText = "已暂停"
            isBuffering = false
            updatePlaybackClock()
        case .ended:
            statusText = "播放结束"
            isBuffering = false
            updatePlaybackClock()
        case .error:
            if tryAdvanceToNextCandidateIfNeeded() == false {
                hasLoadedCandidate = false
                statusText = "播放失败"
                isBuffering = false
            }
        case .stopped:
            guard hasLoadedCandidate else {
                return
            }

            if tryAdvanceToNextCandidateIfNeeded() == false {
                hasLoadedCandidate = false
                statusText = "已停止"
                isBuffering = false
            }
        default:
            statusText = "正在初始化"
            isBuffering = true
        }
    }

    private func updatePlaybackClock() {
        currentTimeText = Self.formattedTime(milliseconds: player.time.intValue)

        if let mediaLength = player.media?.length.intValue, mediaLength > 0 {
            durationText = Self.formattedTime(milliseconds: mediaLength)
        } else if let remainingMilliseconds = player.remainingTime?.intValue, remainingMilliseconds < 0 {
            durationText = Self.formattedTime(milliseconds: player.time.intValue - remainingMilliseconds)
        }
    }

    private func applyInitialSeekIfNeeded() {
        guard didApplyInitialSeek == false, let pendingStartMilliseconds, pendingStartMilliseconds > 0 else {
            return
        }

        didApplyInitialSeek = true
        player.time = VLCTime(int: pendingStartMilliseconds)
    }

    private func playCurrentCandidate() {
        guard candidates.indices.contains(currentCandidateIndex) else {
            statusText = "没有可用的播放地址"
            isBuffering = false
            return
        }

        let candidate = candidates[currentCandidateIndex]
        routeText = candidate.routeDescription
        statusText = currentCandidateIndex == 0 ? "正在初始化" : "正在切换备用播放路线"
        isBuffering = true
        hasLoadedCandidate = true
        currentTimeText = "00:00"
        durationText = "--:--"
        didApplyInitialSeek = pendingStartMilliseconds == nil

        let media = VLCMedia(url: candidate.url)
        player.media = media
        if let drawableView {
            player.drawable = drawableView
        }
        player.play()
    }

    private func tryAdvanceToNextCandidateIfNeeded() -> Bool {
        guard isSwitchingCandidate == false else {
            return false
        }

        guard shouldFallbackToNextCandidate else {
            return false
        }

        let nextIndex = currentCandidateIndex + 1
        guard candidates.indices.contains(nextIndex) else {
            return false
        }

        isSwitchingCandidate = true
        currentCandidateIndex = nextIndex
        player.stop()
        player.media = nil
        playCurrentCandidate()
        isSwitchingCandidate = false
        return true
    }

    private var shouldFallbackToNextCandidate: Bool {
        let currentMilliseconds = player.time.intValue
        let mediaLength = player.media?.length.intValue ?? 0

        if currentMilliseconds <= 2_000 {
            return true
        }

        if mediaLength <= 0, currentMilliseconds <= 5_000 {
            return true
        }

        return false
    }

    private static func startMilliseconds(from ticks: Int64?) -> Int32? {
        guard let ticks, ticks > 0 else { return nil }

        let milliseconds = ticks / 10_000
        if milliseconds <= 0 {
            return nil
        }

        return Int32(clamping: milliseconds)
    }

    private static func formattedTime(milliseconds: Int32) -> String {
        guard milliseconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(milliseconds / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
