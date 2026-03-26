import Foundation
import Observation

@MainActor
@Observable
final class QBittorrentStore {
    var session: QBittorrentSessionSnapshot?
    var transferInfo: QBittorrentTransferInfo?
    var torrents: [QBTorrent] = []
    var errorMessage: String?
    var noticeMessage: String?
    var isConnecting = false
    var isRefreshing = false
    var actingTorrentHash: String?
    var deletingTorrentHash: String?

    @ObservationIgnored
    private let sessionStore: QBittorrentSessionStore

    @ObservationIgnored
    private let apiClient: QBittorrentAPIClient

    init(
        sessionStore: QBittorrentSessionStore = QBittorrentSessionStore(),
        apiClient: QBittorrentAPIClient = QBittorrentAPIClient()
    ) {
        self.sessionStore = sessionStore
        self.apiClient = apiClient
        self.session = sessionStore.loadSession()

        if let session, sessionStore.loadPassword(for: session) != nil {
            Task {
                await refresh()
            }
        }
    }

    var isConnected: Bool {
        session != nil
    }

    func connect(serverURLString: String, username: String, password: String) async -> Bool {
        guard isConnecting == false else {
            return false
        }

        guard let baseURL = QBittorrentServerURL.normalize(serverURLString) else {
            errorMessage = "请输入有效的 qBittorrent WebUI 地址。"
            return false
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedUsername.isEmpty == false, trimmedPassword.isEmpty == false else {
            errorMessage = "用户名和密码不能为空。"
            return false
        }

        isConnecting = true
        errorMessage = nil

        defer {
            isConnecting = false
        }

        do {
            let version = try await apiClient.connect(baseURL: baseURL, username: trimmedUsername, password: trimmedPassword)
            let snapshot = QBittorrentSessionSnapshot(
                serverURLString: baseURL.absoluteString,
                username: trimmedUsername,
                version: version
            )

            try sessionStore.save(session: snapshot, password: trimmedPassword)
            session = snapshot
            noticeMessage = "已连接 qBittorrent。"
            await refresh()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func refresh() async {
        guard isRefreshing == false else {
            return
        }

        guard let context = activeContext() else {
            errorMessage = "还没有保存 qBittorrent 登录信息。"
            return
        }

        isRefreshing = true
        errorMessage = nil

        defer {
            isRefreshing = false
        }

        do {
            let dashboard = try await apiClient.dashboard(
                baseURL: context.baseURL,
                username: context.session.username,
                password: context.password
            )

            transferInfo = dashboard.transferInfo
            torrents = dashboard.torrents
        } catch {
            handle(error)
        }
    }

    func refreshIfNeeded() async {
        guard session != nil else {
            return
        }

        if transferInfo == nil || torrents.isEmpty {
            await refresh()
        }
    }

    func togglePause(for torrent: QBTorrent) async {
        guard actingTorrentHash == nil else {
            return
        }

        guard let context = activeContext() else {
            errorMessage = "还没有保存 qBittorrent 登录信息。"
            return
        }

        actingTorrentHash = torrent.hash
        noticeMessage = nil

        defer {
            actingTorrentHash = nil
        }

        do {
            if torrent.canResume {
                try await apiClient.resume(
                    baseURL: context.baseURL,
                    username: context.session.username,
                    password: context.password,
                    hash: torrent.hash
                )
                noticeMessage = "已继续“\(torrent.name)”。"
            } else {
                try await apiClient.pause(
                    baseURL: context.baseURL,
                    username: context.session.username,
                    password: context.password,
                    hash: torrent.hash
                )
                noticeMessage = "已暂停“\(torrent.name)”。"
            }

            await refresh()
        } catch {
            handle(error)
        }
    }

    func delete(_ torrent: QBTorrent, deleteFiles: Bool) async {
        guard deletingTorrentHash == nil else {
            return
        }

        guard let context = activeContext() else {
            errorMessage = "还没有保存 qBittorrent 登录信息。"
            return
        }

        deletingTorrentHash = torrent.hash
        noticeMessage = nil

        defer {
            deletingTorrentHash = nil
        }

        do {
            try await apiClient.delete(
                baseURL: context.baseURL,
                username: context.session.username,
                password: context.password,
                hash: torrent.hash,
                deleteFiles: deleteFiles
            )
            noticeMessage = deleteFiles ? "已删除任务和文件“\(torrent.name)”。" : "已删除任务“\(torrent.name)”，并保留文件。"
            await refresh()
        } catch {
            handle(error)
        }
    }

    func disconnect() {
        sessionStore.clear()
        clearRuntimeState()
    }

    private func activeContext() -> (session: QBittorrentSessionSnapshot, baseURL: URL, password: String)? {
        guard let session,
              let baseURL = URL(string: session.serverURLString),
              let password = sessionStore.loadPassword(for: session) else {
            return nil
        }

        return (session, baseURL, password)
    }

    private func clearRuntimeState() {
        session = nil
        transferInfo = nil
        torrents = []
        errorMessage = nil
        noticeMessage = nil
        actingTorrentHash = nil
        deletingTorrentHash = nil
    }

    private func handle(_ error: Error) {
        if let apiError = error as? QBittorrentAPIClient.APIError {
            switch apiError {
            case .unauthorized:
                errorMessage = "qBittorrent 登录失败，请检查 WebUI 的账号密码。"
                return
            default:
                break
            }
        }

        errorMessage = error.localizedDescription
    }
}
