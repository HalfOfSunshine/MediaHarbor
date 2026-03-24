import Foundation
import Observation

@MainActor
@Observable
final class JellyfinStore {
    var session: JellyfinSessionSnapshot?
    var savedSessions: [JellyfinSessionSnapshot] = []
    var libraries: [JellyfinLibrary] = []
    var managedLibraries: [JellyfinLibrary] = []
    var recentMovies: [JellyfinMovie] = []
    var libraryItems: [JellyfinLibraryItem] = []
    var scheduledTasks: [JellyfinTask] = []
    var selectedLibraryID: String?
    var consoleLibrarySource: JellyfinConsoleLibrarySource = .userVisible
    var errorMessage: String?
    var libraryErrorMessage: String?
    var libraryNoticeMessage: String?
    var consoleErrorMessage: String?
    var consoleNotice: String?
    var isConnecting = false
    var isRefreshing = false
    var isLoadingLibrary = false
    var isLoadingConsole = false
    var isStartingLibraryScan = false
    var isRefreshingSingleLibrary = false
    var isStoppingLibraryScan = false
    var refreshingLibraryID: String?

    @ObservationIgnored
    private let sessionStore: JellyfinSessionStore

    @ObservationIgnored
    private let apiClient: JellyfinAPIClient

    @ObservationIgnored
    private var lastLoadedLibraryKey: String?

    init(
        sessionStore: JellyfinSessionStore = JellyfinSessionStore(),
        apiClient: JellyfinAPIClient = JellyfinAPIClient()
    ) {
        self.sessionStore = sessionStore
        self.apiClient = apiClient
        reloadSavedSessions()
        self.session = sessionStore.loadActiveSession()

        if let session, sessionStore.loadAccessToken(for: session) != nil {
            Task {
                await refreshDashboard()
            }
        }
    }

    var isConnected: Bool {
        session != nil
    }

    var hasSavedSessions: Bool {
        savedSessions.isEmpty == false
    }

    var selectedLibrary: JellyfinLibrary? {
        guard let selectedLibraryID else {
            return nil
        }

        return libraries.first(where: { $0.id == selectedLibraryID })
    }

    var libraryScanTask: JellyfinTask? {
        scheduledTasks.first(where: \.isLibraryScanTask)
    }

    func connect(serverURLString: String, username: String, password: String) async -> Bool {
        guard isConnecting == false else {
            return false
        }

        guard let baseURL = JellyfinServerURL.normalize(serverURLString) else {
            errorMessage = "请输入有效的 Jellyfin 服务器地址。"
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
            let publicInfo = try await apiClient.publicInfo(baseURL: baseURL)
            let authenticated = try await apiClient.authenticate(
                baseURL: baseURL,
                username: trimmedUsername,
                password: trimmedPassword
            )

            let snapshot = JellyfinSessionSnapshot(
                serverURLString: baseURL.absoluteString,
                serverName: publicInfo.serverName,
                serverVersion: publicInfo.version,
                username: authenticated.username,
                userID: authenticated.userID
            )

            try sessionStore.save(session: snapshot, accessToken: authenticated.accessToken)
            activateSession(snapshot)
            reloadSavedSessions()
            await refreshDashboard(forceReloadLibrary: true)
            await refreshConsole()
            return true
        } catch let apiError as JellyfinAPIClient.APIError {
            switch apiError {
            case .unauthorized, .forbidden:
                errorMessage = "登录失败，请检查用户名和密码；如果账号本身没问题，也请确认它允许通过当前网络访问 Jellyfin。"
            default:
                errorMessage = apiError.localizedDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func switchSession(to session: JellyfinSessionSnapshot) async -> Bool {
        guard self.session?.accountKey != session.accountKey else {
            return true
        }

        guard sessionStore.loadAccessToken(for: session) != nil else {
            errorMessage = "这个账号的登录信息已经失效，请重新添加一次。"
            return false
        }

        sessionStore.activate(session: session)
        activateSession(session)
        reloadSavedSessions()
        await refreshDashboard(forceReloadLibrary: true)
        await refreshConsole()
        return true
    }

    func removeSession(_ session: JellyfinSessionSnapshot) async {
        let wasActiveSession = self.session?.accountKey == session.accountKey
        let nextSession = sessionStore.remove(session: session)

        reloadSavedSessions()

        guard wasActiveSession else {
            return
        }

        clearRuntimeState()
        self.session = nextSession

        if let nextSession, sessionStore.loadAccessToken(for: nextSession) != nil {
            await refreshDashboard(forceReloadLibrary: true)
            await refreshConsole()
        }
    }

    func refreshDashboard(forceReloadLibrary: Bool = false) async {
        guard isRefreshing == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        isRefreshing = true
        errorMessage = nil

        defer {
            isRefreshing = false
        }

        do {
            async let fetchedLibraries = apiClient.libraries(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )
            async let fetchedRecentMovies = apiClient.latestMovies(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )

            let availableLibraries = JellyfinLibrary.mediaLibraries(from: try await fetchedLibraries)
            let latestMovies = try await fetchedRecentMovies

            libraries = availableLibraries
            recentMovies = latestMovies

            if availableLibraries.contains(where: { $0.id == selectedLibraryID }) == false {
                selectedLibraryID = availableLibraries.first?.id
            }

            if forceReloadLibrary {
                lastLoadedLibraryKey = nil
            }
        } catch {
            handle(error)
        }
    }

    func refreshConsole() async {
        guard isLoadingConsole == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        isLoadingConsole = true
        consoleErrorMessage = nil

        defer {
            isLoadingConsole = false
        }

        do {
            async let fetchedTasks = apiClient.scheduledTasks(
                baseURL: context.baseURL,
                token: context.accessToken
            )
            async let fetchedConsoleLibraries = apiClient.consoleLibraries(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )

            scheduledTasks = try await fetchedTasks
            let consoleLibraries = try await fetchedConsoleLibraries
            managedLibraries = consoleLibraries.libraries
            consoleLibrarySource = consoleLibraries.source
        } catch {
            handleConsole(error)
        }
    }

    func loadLibraryItems(for library: JellyfinLibrary, searchTerm: String, force: Bool = false) async {
        guard isLoadingLibrary == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        let trimmedSearchTerm = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryChanged = selectedLibraryID != library.id
        let libraryKey = "\(library.id)|\(trimmedSearchTerm)"

        guard force || libraryKey != lastLoadedLibraryKey else {
            return
        }

        if libraryChanged {
            selectedLibraryID = library.id
            libraryItems = []
            lastLoadedLibraryKey = nil
        }

        isLoadingLibrary = true
        libraryErrorMessage = nil
        libraryNoticeMessage = nil

        defer {
            isLoadingLibrary = false
        }

        do {
            libraryItems = try await apiClient.libraryItems(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken,
                library: library,
                searchTerm: trimmedSearchTerm
            )
            lastLoadedLibraryKey = libraryKey
        } catch {
            handle(error, isLibraryAction: true)
        }
    }

    func selectLibrary(_ identifier: String) {
        guard selectedLibraryID != identifier else {
            return
        }

        selectedLibraryID = identifier
        lastLoadedLibraryKey = nil
    }

    func refreshLibrary(_ library: JellyfinLibrary) async {
        guard isRefreshingSingleLibrary == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        isRefreshingSingleLibrary = true
        refreshingLibraryID = library.id
        libraryErrorMessage = nil
        libraryNoticeMessage = nil

        defer {
            isRefreshingSingleLibrary = false
            refreshingLibraryID = nil
        }

        do {
            try await apiClient.refreshLibraryItem(baseURL: context.baseURL, token: context.accessToken, itemID: library.id)
            if libraries.contains(where: { $0.id == library.id }) {
                selectedLibraryID = library.id
            }
            libraryNoticeMessage = "已提交“\(library.name)”的单库刷新请求。Jellyfin 官方对单个媒体库提供的是当前库项目刷新接口，全库文件扫描仍然由“扫描所有媒体库”负责。"
            await refreshConsole()
        } catch {
            handle(error, isLibraryAction: true)
        }
    }

    func primaryImageURL(for movie: JellyfinMovie, maxWidth: Int = 720, maxHeight: Int = 1080) -> URL? {
        primaryImageURL(itemID: movie.id, tag: movie.primaryImageTag, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    func primaryImageURL(for item: JellyfinLibraryItem, maxWidth: Int = 720, maxHeight: Int = 1080) -> URL? {
        primaryImageURL(itemID: item.id, tag: item.primaryImageTag, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    func disconnect() {
        guard let session else {
            clearRuntimeState()
            reloadSavedSessions()
            return
        }

        let nextSession = sessionStore.remove(session: session)
        clearRuntimeState()
        self.session = nextSession
        reloadSavedSessions()

        if let nextSession, sessionStore.loadAccessToken(for: nextSession) != nil {
            Task {
                await refreshDashboard(forceReloadLibrary: true)
                await refreshConsole()
            }
        }
    }

    func startLibraryScan() async {
        guard isStartingLibraryScan == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        isStartingLibraryScan = true
        consoleErrorMessage = nil
        consoleNotice = nil

        defer {
            isStartingLibraryScan = false
        }

        do {
            try await apiClient.startLibraryScan(baseURL: context.baseURL, token: context.accessToken)
            consoleNotice = "Jellyfin 已经加入“扫描所有媒体库”的任务。"
            await refreshConsole()
        } catch {
            handleConsole(error)
        }
    }

    func stopLibraryScan() async {
        guard isStoppingLibraryScan == false else {
            return
        }

        guard let context = activeContext() else {
            disconnect()
            return
        }

        guard let task = libraryScanTask else {
            consoleErrorMessage = "当前没有可停止的媒体库扫描任务。"
            return
        }

        isStoppingLibraryScan = true
        consoleErrorMessage = nil
        consoleNotice = nil

        defer {
            isStoppingLibraryScan = false
        }

        do {
            try await apiClient.stopTask(baseURL: context.baseURL, token: context.accessToken, taskID: task.id)
            consoleNotice = "Jellyfin 已收到停止当前扫描任务的请求。"
            await refreshConsole()
        } catch {
            handleConsole(error)
        }
    }

    private func activeContext() -> (session: JellyfinSessionSnapshot, baseURL: URL, accessToken: String)? {
        guard let session,
              let baseURL = URL(string: session.serverURLString),
              let accessToken = sessionStore.loadAccessToken(for: session) else {
            return nil
        }

        return (session, baseURL, accessToken)
    }

    private func activateSession(_ session: JellyfinSessionSnapshot) {
        clearRuntimeState()
        self.session = session
    }

    private func reloadSavedSessions() {
        savedSessions = sessionStore.loadSessions()
    }

    private func clearRuntimeState() {
        libraries = []
        managedLibraries = []
        recentMovies = []
        libraryItems = []
        scheduledTasks = []
        selectedLibraryID = nil
        consoleLibrarySource = .userVisible
        errorMessage = nil
        libraryErrorMessage = nil
        libraryNoticeMessage = nil
        consoleErrorMessage = nil
        consoleNotice = nil
        lastLoadedLibraryKey = nil
        refreshingLibraryID = nil
    }

    private func primaryImageURL(itemID: String, tag: String?, maxWidth: Int, maxHeight: Int) -> URL? {
        guard let context = activeContext() else {
            return nil
        }

        return apiClient.primaryImageURL(
            baseURL: context.baseURL,
            itemID: itemID,
            token: context.accessToken,
            tag: tag,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )
    }

    private func handle(_ error: Error, isLibraryAction: Bool = false) {
        if let apiError = error as? JellyfinAPIClient.APIError {
            switch apiError {
            case .unauthorized:
                disconnect()
                errorMessage = "Jellyfin 登录状态已失效，请重新连接。"
                return
            case .forbidden:
                let message = "当前账号没有权限访问这个 Jellyfin 功能。"
                if isLibraryAction {
                    libraryErrorMessage = message
                } else {
                    errorMessage = message
                }
                return
            default:
                break
            }
        }

        let message = error.localizedDescription
        if isLibraryAction {
            libraryErrorMessage = message
        } else {
            errorMessage = message
        }
    }

    private func handleConsole(_ error: Error) {
        if let apiError = error as? JellyfinAPIClient.APIError {
            switch apiError {
            case .unauthorized:
                disconnect()
                errorMessage = "Jellyfin 登录状态已失效，请重新连接。"
                return
            case .forbidden:
                consoleErrorMessage = "当前账号没有 Jellyfin 管理权限，无法查看控制台或执行扫描。"
                return
            default:
                break
            }
        }

        consoleErrorMessage = error.localizedDescription
    }
}
