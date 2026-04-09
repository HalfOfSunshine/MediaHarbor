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
    var resumeItems: [JellyfinLibraryItem] = []
    var nextUpItems: [JellyfinLibraryItem] = []
    var favoriteItems: [JellyfinLibraryItem] = []
    var searchResults: [JellyfinLibraryItem] = []
    var libraryItems: [JellyfinLibraryItem] = []
    var scheduledTasks: [JellyfinTask] = []
    var selectedLibraryID: String?
    var consoleLibrarySource: JellyfinConsoleLibrarySource = .userVisible
    var errorMessage: String?
    var libraryErrorMessage: String?
    var libraryNoticeMessage: String?
    var searchErrorMessage: String?
    var consoleErrorMessage: String?
    var consoleNotice: String?
    var isConnecting = false
    var isRefreshing = false
    var isLoadingLibrary = false
    var isSearching = false
    var isLoadingConsole = false
    var isStartingLibraryScan = false
    var isRefreshingSingleLibrary = false
    var isStoppingLibraryScan = false
    var refreshingLibraryID: String?
    var favoriteActionItemID: String?

    @ObservationIgnored
    private let sessionStore: JellyfinSessionStore

    @ObservationIgnored
    private let apiClient: JellyfinAPIClient

    @ObservationIgnored
    private var lastLoadedLibraryKey: String?

    @ObservationIgnored
    private var lastSearchTerm: String = ""

    @ObservationIgnored
    private var cloudObserver: NSObjectProtocol?

    init(
        sessionStore: JellyfinSessionStore = JellyfinSessionStore(),
        apiClient: JellyfinAPIClient = JellyfinAPIClient()
    ) {
        self.sessionStore = sessionStore
        self.apiClient = apiClient
        reloadSavedSessions()
        self.session = sessionStore.loadActiveSession()
        installCloudObserver()

        if let session, sessionStore.loadAccessToken(for: session) != nil {
            Task {
                await refreshDashboard()
            }
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
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

    var refreshableManagedLibraries: [JellyfinLibrary] {
        JellyfinLibrary.refreshableConsoleLibraries(
            managedLibraries: managedLibraries,
            userVisibleLibraries: libraries,
            source: consoleLibrarySource
        )
    }

    var hiddenManagedLibraryCount: Int {
        max(managedLibraries.count - refreshableManagedLibraries.count, 0)
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

        guard trimmedUsername.isEmpty == false, password.isEmpty == false else {
            errorMessage = "用户名和密码不能为空。"
            return false
        }

        isConnecting = true
        errorMessage = nil

        defer {
            isConnecting = false
        }

        do {
            let authenticated = try await apiClient.authenticate(
                baseURL: baseURL,
                username: trimmedUsername,
                password: password
            )
            let publicInfo = try? await apiClient.publicInfo(baseURL: baseURL)

            let snapshot = JellyfinSessionSnapshot(
                serverURLString: baseURL.absoluteString,
                serverName: publicInfo?.serverName ?? baseURL.host ?? "Jellyfin",
                serverVersion: publicInfo?.version,
                username: authenticated.username,
                userID: authenticated.userID
            )

            try sessionStore.save(session: snapshot, accessToken: authenticated.accessToken)
            activateSession(snapshot)
            reloadSavedSessions()
            Task {
                await refreshDashboard(forceReloadLibrary: true, showErrors: false)
                await refreshConsole(showErrors: false)
            }
            return true
        } catch let apiError as JellyfinAPIClient.APIError {
            errorMessage = Self.connectionErrorMessage(for: apiError)
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

    func refreshDashboard(forceReloadLibrary: Bool = false, showErrors: Bool = true) async {
        guard isRefreshing == false else {
            return
        }

        guard let context = activeContext() else {
            handleMissingActiveContext()
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
            async let fetchedResumeItems = apiClient.resumeItems(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )
            async let fetchedNextUpItems = apiClient.nextUpItems(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )
            async let fetchedFavoriteItems = apiClient.favoriteItems(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken
            )

            let availableLibraries = JellyfinLibrary.mediaLibraries(from: try await fetchedLibraries)
            let latestMovies = try await fetchedRecentMovies
            let resumeItems = try await fetchedResumeItems
            let nextUpItems = try await fetchedNextUpItems
            let favoriteItems = try await fetchedFavoriteItems

            libraries = availableLibraries
            recentMovies = latestMovies
            self.resumeItems = resumeItems
            self.nextUpItems = nextUpItems
            self.favoriteItems = favoriteItems

            if availableLibraries.contains(where: { $0.id == selectedLibraryID }) == false {
                selectedLibraryID = availableLibraries.first?.id
            }

            if forceReloadLibrary {
                lastLoadedLibraryKey = nil
            }
        } catch {
            if showErrors {
                handle(error)
            }
        }
    }

    func refreshConsole(showErrors: Bool = true) async {
        guard isLoadingConsole == false else {
            return
        }

        guard let context = activeContext() else {
            handleMissingActiveContext()
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
            if showErrors {
                handleConsole(error)
            }
        }
    }

    func loadLibraryItems(for library: JellyfinLibrary, searchTerm: String, force: Bool = false) async {
        guard isLoadingLibrary == false else {
            return
        }

        guard let context = activeContext() else {
            handleMissingActiveContext(target: .library)
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

    func searchItems(_ term: String) async {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedTerm.isEmpty == false else {
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
            lastSearchTerm = ""
            return
        }

        guard let context = activeContext() else {
            handleMissingActiveContext(target: .search)
            return
        }

        lastSearchTerm = trimmedTerm
        isSearching = true
        searchErrorMessage = nil

        do {
            let results = try await apiClient.searchItems(
                baseURL: context.baseURL,
                userID: context.session.userID,
                token: context.accessToken,
                searchTerm: trimmedTerm
            )

            guard lastSearchTerm == trimmedTerm else {
                return
            }

            searchResults = results
        } catch {
            guard lastSearchTerm == trimmedTerm else {
                return
            }

            searchResults = []
            searchErrorMessage = error.localizedDescription
        }

        if lastSearchTerm == trimmedTerm {
            isSearching = false
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
            handleMissingActiveContext(target: .library)
            return
        }

        guard refreshableManagedLibraries.contains(where: { $0.id == library.id }) else {
            libraryErrorMessage = "这个媒体库当前不能单独刷新。请使用“扫描所有媒体库”。"
            libraryNoticeMessage = nil
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

    func setFavorite(itemID: String, isFavorite: Bool) async throws {
        guard let context = activeContext() else {
            handleMissingActiveContext()
            throw JellyfinAPIClient.APIError.unauthorized
        }

        favoriteActionItemID = itemID
        defer {
            if favoriteActionItemID == itemID {
                favoriteActionItemID = nil
            }
        }

        try await apiClient.setFavorite(
            baseURL: context.baseURL,
            userID: context.session.userID,
            token: context.accessToken,
            itemID: itemID,
            isFavorite: isFavorite
        )

        updateFavoriteState(itemID: itemID, isFavorite: isFavorite)
    }

    func webDetailsURL(for itemID: String) -> URL? {
        guard let context = activeContext() else {
            return nil
        }

        return apiClient.webDetailsURL(baseURL: context.baseURL, itemID: itemID)
    }

    func directVideoURL(for itemID: String) -> URL? {
        guard let context = activeContext() else {
            return nil
        }

        return apiClient.directVideoURL(baseURL: context.baseURL, itemID: itemID, token: context.accessToken)
    }

    func playbackStream(for itemID: String) async throws -> JellyfinPlaybackStream {
        guard let context = activeContext() else {
            handleMissingActiveContext()
            throw JellyfinAPIClient.APIError.unauthorized
        }

        return try await apiClient.playbackStream(
            baseURL: context.baseURL,
            userID: context.session.userID,
            token: context.accessToken,
            itemID: itemID
        )
    }

    func childItems(for item: JellyfinLibraryItem) async throws -> [JellyfinLibraryItem] {
        guard let context = activeContext() else {
            handleMissingActiveContext()
            throw JellyfinAPIClient.APIError.unauthorized
        }

        let includeItemTypes: String?
        let recursive: Bool

        switch item.kind {
        case .series:
            includeItemTypes = "Episode"
            recursive = true
        case .season:
            includeItemTypes = "Episode"
            recursive = false
        case .folder:
            includeItemTypes = "Series,Movie"
            recursive = false
        case .movie, .episode, .other:
            return []
        }

        return try await apiClient.childItems(
            baseURL: context.baseURL,
            userID: context.session.userID,
            token: context.accessToken,
            parentID: item.id,
            recursive: recursive,
            includeItemTypes: includeItemTypes
        )
    }

    func removeCurrentSession() {
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
            handleMissingActiveContext(target: .console)
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
            handleMissingActiveContext(target: .console)
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

    private func installCloudObserver() {
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                await self.syncFromCloud()
            }
        }
    }

    private func syncFromCloud() async {
        let previousSessionKey = session?.accountKey
        let reloadedSession = sessionStore.loadActiveSession()
        reloadSavedSessions()

        guard previousSessionKey != reloadedSession?.accountKey else {
            session = reloadedSession
            return
        }

        clearRuntimeState()
        session = reloadedSession

        if let reloadedSession, sessionStore.loadAccessToken(for: reloadedSession) != nil {
            await refreshDashboard(forceReloadLibrary: true, showErrors: false)
            await refreshConsole(showErrors: false)
        }
    }

    static func connectionErrorMessage(for apiError: JellyfinAPIClient.APIError) -> String {
        switch apiError {
        case .unauthorized, .forbidden:
            return "登录失败，请检查用户名和密码；如果账号本身没问题，也请确认它允许通过当前网络访问 Jellyfin。"
        case .invalidResponse:
            return "Jellyfin 服务器返回了无法识别的登录响应。请先确认这个账号在 Jellyfin 网页里能正常登录。"
        case .missingAuthentication:
            return "Jellyfin 登录成功了，但服务器没有返回有效的访问令牌。"
        case .serverMessage where apiError.isGenericServerProcessingMessage:
            return "Jellyfin 在处理登录请求时返回了服务器错误。请先在 Jellyfin 网页里确认这个账号能否正常登录；如果网页也失败，需要在服务器端排查该账号。"
        default:
            return apiError.localizedDescription
        }
    }

    private func clearRuntimeState() {
        libraries = []
        managedLibraries = []
        recentMovies = []
        resumeItems = []
        nextUpItems = []
        favoriteItems = []
        searchResults = []
        libraryItems = []
        scheduledTasks = []
        selectedLibraryID = nil
        consoleLibrarySource = .userVisible
        errorMessage = nil
        libraryErrorMessage = nil
        libraryNoticeMessage = nil
        searchErrorMessage = nil
        consoleErrorMessage = nil
        consoleNotice = nil
        lastLoadedLibraryKey = nil
        lastSearchTerm = ""
        refreshingLibraryID = nil
        favoriteActionItemID = nil
        isSearching = false
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
                invalidateActiveSession(message: "Jellyfin 登录状态已失效。已保存账号仍保留在本地，请重新选择账号或重新添加。")
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
                invalidateActiveSession(message: "Jellyfin 登录状态已失效。已保存账号仍保留在本地，请重新选择账号或重新添加。")
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

    private enum MissingContextTarget {
        case general
        case library
        case search
        case console
    }

    private func handleMissingActiveContext(target: MissingContextTarget = .general) {
        invalidateActiveSession()

        let message = "本地已保存的 Jellyfin 账号仍在，但当前登录凭证不可用。请重新选择账号，或重新添加这个账号。"
        switch target {
        case .general:
            errorMessage = message
        case .library:
            libraryErrorMessage = message
        case .search:
            searchErrorMessage = message
            isSearching = false
        case .console:
            consoleErrorMessage = message
        }
    }

    private func invalidateActiveSession(message: String? = nil) {
        clearRuntimeState()
        session = nil
        reloadSavedSessions()

        if let message {
            errorMessage = message
        }
    }

    private func updateFavoriteState(itemID: String, isFavorite: Bool) {
        recentMovies = recentMovies.map { movie in
            guard movie.id == itemID else { return movie }
            return movie.updatingFavorite(isFavorite)
        }
        libraryItems = libraryItems.map { item in
            guard item.id == itemID else { return item }
            return item.updatingFavorite(isFavorite)
        }
        resumeItems = resumeItems.map { item in
            guard item.id == itemID else { return item }
            return item.updatingFavorite(isFavorite)
        }
        nextUpItems = nextUpItems.map { item in
            guard item.id == itemID else { return item }
            return item.updatingFavorite(isFavorite)
        }
        favoriteItems = isFavorite
            ? favoriteItems
            : favoriteItems.filter { $0.id != itemID }

        if isFavorite, let inserted = libraryItems.first(where: { $0.id == itemID }) {
            if favoriteItems.contains(where: { $0.id == itemID }) == false {
                favoriteItems.insert(inserted.updatingFavorite(true), at: 0)
            }
        }
    }
}
