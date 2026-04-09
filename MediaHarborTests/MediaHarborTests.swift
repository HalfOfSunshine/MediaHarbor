//
//  MediaHarborTests.swift
//  MediaHarborTests
//
//  Created by mamingkang on 2026/3/24.
//

import Foundation
import Testing
@testable import MediaHarbor

struct MediaHarborTests {

    @Test
    func jellyfinURLNormalizationAddsSchemeDefaultPortAndTrimsTrailingSlash() async throws {
        let url = JellyfinServerURL.normalize("demo.local/")

        #expect(url?.absoluteString == "https://demo.local:8096")
    }

    @Test
    func jellyfinURLNormalizationPreservesExplicitHTTPAndBasePath() async throws {
        let url = JellyfinServerURL.normalize("http://192.168.50.20/jellyfin/")

        #expect(url?.absoluteString == "http://192.168.50.20:8096/jellyfin")
    }

    @Test
    func qbittorrentURLNormalizationAddsDefaultHTTPPortAndTrimsTrailingSlash() async throws {
        let url = QBittorrentServerURL.normalize("router.mingkang.uk/")

        #expect(url?.absoluteString == "http://router.mingkang.uk:8899")
    }

    @Test
    func qbittorrentPaginationClampsOutOfRangePageIndex() async throws {
        let normalizedPage = QBTorrentPagination.normalizedPageIndex(9, itemCount: 36, pageSize: 20)
        let totalPages = QBTorrentPagination.totalPages(itemCount: 36, pageSize: 20)

        #expect(totalPages == 2)
        #expect(normalizedPage == 1)
    }

    @Test
    func qbittorrentPaginationReturnsExpectedSliceAndRangeText() async throws {
        let values = Array(1 ... 45)
        let pagedValues = Array(QBTorrentPagination.items(values, pageIndex: 1, pageSize: 20))
        let rangeText = QBTorrentPagination.rangeText(itemCount: values.count, pageIndex: 1, pageSize: 20)

        #expect(pagedValues == Array(21 ... 40))
        #expect(rangeText == "第 21-40 项，共 45 项")
    }

    @Test
    func qbittorrentSortOptionsUseExpectedRequestValues() async throws {
        #expect(QBittorrentTorrentSortKey.addedOn.requestValue == "added_on")
        #expect(QBittorrentTorrentSortKey.downloadSpeed.requestValue == "dlspeed")
        #expect(QBittorrentTorrentSortKey.uploadSpeed.requestValue == "upspeed")
        #expect(QBittorrentTorrentSortDirection.descending.reverseValue == true)
        #expect(QBittorrentTorrentSortDirection.ascending.reverseValue == false)
    }

    @Test
    func mediaLibrariesKeepMediaFoldersAndSortAlphabetically() async throws {
        let libraries = [
            JellyfinLibrary(
                id: "shows",
                name: "TV Shows",
                collectionType: "tvshows",
                itemCount: 42,
                type: "CollectionFolder",
                isFolder: true
            ),
            JellyfinLibrary(
                id: "movies",
                name: "Movies",
                collectionType: "movies",
                itemCount: 128,
                type: "CollectionFolder",
                isFolder: true
            ),
        ]

        let preferred = JellyfinLibrary.mediaLibraries(from: libraries)

        #expect(preferred.map(\.id) == ["movies", "shows"])
    }

    @Test
    func mediaLibrariesExcludePlaylistsAndKeepAdminCollectionFolders() async throws {
        let libraries = [
            JellyfinLibrary(
                id: "hidden-library",
                name: "小姐姐之家1",
                collectionType: nil,
                itemCount: nil,
                type: "CollectionFolder",
                isFolder: true
            ),
            JellyfinLibrary(
                id: "playlists",
                name: "Playlists",
                collectionType: "playlists",
                itemCount: nil,
                type: "ManualPlaylistsFolder",
                isFolder: true
            ),
            JellyfinLibrary(
                id: "movies",
                name: "电影",
                collectionType: "movies",
                itemCount: 12,
                type: "CollectionFolder",
                isFolder: true
            ),
        ]

        let preferred = JellyfinLibrary.mediaLibraries(from: libraries)

        #expect(preferred.count == 2)
        #expect(preferred.contains(where: { $0.id == "hidden-library" }))
        #expect(preferred.contains(where: { $0.id == "movies" }))
        #expect(preferred.contains(where: { $0.id == "playlists" }) == false)
    }

    @Test
    func jellyfinRefreshableConsoleLibrariesHideAdminOnlyLibrariesWithoutUserAccess() async throws {
        let adminLibraries = [
            JellyfinLibrary(
                id: "hidden-library",
                name: "小姐姐之家1",
                collectionType: nil,
                itemCount: nil,
                type: "CollectionFolder",
                isFolder: true
            ),
            JellyfinLibrary(
                id: "movies",
                name: "电影",
                collectionType: "movies",
                itemCount: 12,
                type: "CollectionFolder",
                isFolder: true
            ),
        ]
        let userVisibleLibraries = [
            JellyfinLibrary(
                id: "movies",
                name: "电影",
                collectionType: "movies",
                itemCount: 12,
                type: "CollectionFolder",
                isFolder: true
            ),
        ]

        let filtered = JellyfinLibrary.refreshableConsoleLibraries(
            managedLibraries: adminLibraries,
            userVisibleLibraries: userVisibleLibraries,
            source: .administrator
        )

        #expect(filtered.map(\.id) == ["movies"])
    }

    @Test
    func jellyfinSessionAccountKeyOnlyDeduplicatesSameServerAndSameUser() async throws {
        let sameServerDifferentUser = JellyfinSessionSnapshot(
            serverURLString: "http://media.example:8096",
            serverName: "Home",
            serverVersion: "10.11.6",
            username: "guest",
            userID: "user-2"
        )
        let differentServerSameUser = JellyfinSessionSnapshot(
            serverURLString: "http://backup.example:8096",
            serverName: "Backup",
            serverVersion: "10.11.6",
            username: "media-admin",
            userID: "user-1"
        )
        let sameServerSameUser = JellyfinSessionSnapshot(
            serverURLString: "http://media.example:8096",
            serverName: "Home",
            serverVersion: "10.11.6",
            username: "media-admin",
            userID: "user-1"
        )
        let reference = JellyfinSessionSnapshot(
            serverURLString: "http://media.example:8096",
            serverName: "Home",
            serverVersion: "10.11.6",
            username: "media-admin",
            userID: "user-1"
        )

        #expect(reference.accountKey != sameServerDifferentUser.accountKey)
        #expect(reference.accountKey != differentServerSameUser.accountKey)
        #expect(reference.accountKey == sameServerSameUser.accountKey)
    }

    @Test
    func jellyfinSessionStoreCanKeepSavedAccountsWithoutAnActiveSession() async throws {
        let suiteName = "MediaHarborTests.JellyfinSessionStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = JellyfinSessionStore(defaults: defaults)
        let session = JellyfinSessionSnapshot(
            serverURLString: "http://media.example:8096",
            serverName: "Home",
            serverVersion: "10.11.6",
            username: "media-admin",
            userID: "user-1"
        )

        try store.save(session: session, accessToken: "token-1")
        store.clearActiveSession()

        #expect(store.loadSessions().map(\.accountKey) == [session.accountKey])
        #expect(store.loadActiveSession() == nil)

        store.clear()
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func playbackOrientationModesMatchExpectedMasksAndDefaultRequests() async throws {
        #expect(AppOrientationController.PlaybackOrientationMode.portrait.supportedMask == .portrait)
        #expect(AppOrientationController.PlaybackOrientationMode.portrait.requestedOrientation == .portrait)
        #expect(AppOrientationController.PlaybackOrientationMode.portrait.toggleTarget == .landscape)

        #expect(AppOrientationController.PlaybackOrientationMode.landscape.supportedMask == .landscape)
        #expect(AppOrientationController.PlaybackOrientationMode.landscape.requestedOrientation == .landscapeRight)
        #expect(AppOrientationController.PlaybackOrientationMode.landscape.toggleTarget == .portrait)
    }

    @Test
    func jellyfinTaskProgressTextIgnoresNonFiniteValues() async throws {
        let runningTask = JellyfinTask(
            id: "scan",
            name: "扫描媒体库",
            state: .running,
            progress: .infinity,
            category: nil,
            key: "RefreshLibrary",
            summary: nil,
            lastRunDateText: nil,
            lastRunStatus: nil
        )
        let clampedTask = JellyfinTask(
            id: "scan-2",
            name: "扫描媒体库",
            state: .running,
            progress: 132.7,
            category: nil,
            key: "RefreshLibrary",
            summary: nil,
            lastRunDateText: nil,
            lastRunStatus: nil
        )

        #expect(runningTask.progressText == nil)
        #expect(clampedTask.progressText == "100%")
    }

    @Test
    func jellyfinWebDetailsURLUsesCurrentWebRoute() async throws {
        let client = JellyfinAPIClient()
        let baseURL = try #require(URL(string: "http://router.mingkang.uk:8096"))
        let url = client.webDetailsURL(baseURL: baseURL, itemID: "12345")

        #expect(url?.absoluteString == "http://router.mingkang.uk:8096/web/index.html#/details?id=12345")
    }

    @Test
    func jellyfinDirectVideoURLIncludesStaticFlagAndToken() async throws {
        let client = JellyfinAPIClient()
        let baseURL = try #require(URL(string: "http://router.mingkang.uk:8096"))
        let url = client.directVideoURL(baseURL: baseURL, itemID: "abc", token: "token-1")

        #expect(url?.absoluteString == "http://router.mingkang.uk:8096/Videos/abc/stream?static=true&api_key=token-1")
    }

    @Test
    func jellyfinDirectVideoURLIncludesPlaySessionAndMediaSourceWhenProvided() async throws {
        let client = JellyfinAPIClient()
        let baseURL = try #require(URL(string: "http://router.mingkang.uk:8096"))
        let url = client.directVideoURL(
            baseURL: baseURL,
            itemID: "abc",
            token: "token-1",
            playSessionID: "session-1",
            mediaSourceID: "source-1",
            tag: "etag-1"
        )

        #expect(
            url?.absoluteString ==
            "http://router.mingkang.uk:8096/Videos/abc/stream?static=true&api_key=token-1&playSessionId=session-1&mediaSourceId=source-1&tag=etag-1"
        )
    }

    @Test
    func jellyfinPlaybackStreamUsesFirstCandidateAsPrimaryRoute() async throws {
        let directURL = try #require(URL(string: "http://router.mingkang.uk:8096/Videos/abc/stream?static=true&api_key=token-1"))
        let transcodeURL = try #require(URL(string: "http://router.mingkang.uk:8096/videos/abc/master.m3u8?api_key=token-1"))
        let stream = JellyfinPlaybackStream(
            candidates: [
                JellyfinPlaybackCandidate(url: directURL, routeDescription: "直接播放"),
                JellyfinPlaybackCandidate(url: transcodeURL, routeDescription: "服务器转码"),
            ]
        )

        #expect(stream.url == directURL)
        #expect(stream.routeDescription == "直接播放")
    }

    @Test
    func jellyfinPlaybackPreferencesDefaultToAppPlayback() async throws {
        let suiteName = "MediaHarborTests.JellyfinPlaybackPreferences"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = await MainActor.run {
            let isolatedDefaults = UserDefaults(suiteName: suiteName)!
            return JellyfinPlaybackPreferences(defaults: isolatedDefaults)
        }

        #expect(await MainActor.run { preferences.preferredOpenTarget } == .app)
    }

    @Test
    func jellyfinLibraryItemKindRecognizesSeasonAndEpisodeTypes() async throws {
        #expect(JellyfinLibraryItemKind(type: "Season", isFolder: true) == .season)
        #expect(JellyfinLibraryItemKind(type: "Episode", isFolder: false) == .episode)
    }

    @Test
    func jellyfinGenericServerProcessingMessageMapsToActionableLoginError() async throws {
        let apiError = JellyfinAPIClient.APIError.serverMessage("Error processing request.")
        let message = await MainActor.run {
            JellyfinStore.connectionErrorMessage(for: apiError)
        }

        #expect(apiError.isGenericServerProcessingMessage)
        #expect(message.contains("登录请求"))
        #expect(message.contains("Jellyfin 网页"))
    }

    @Test
    func browserDefaultSitesKeepMoviePilotMTeamAndHDKyl() async throws {
        let sites = BrowserSite.defaultSites()

        #expect(sites.map(\.id) == [
            BrowserSite.moviePilotID,
            BrowserSite.mTeamID,
            BrowserSite.hdkylID,
        ])
        #expect(sites.allSatisfy { $0.isVisible })
        #expect(sites.first(where: { $0.id == BrowserSite.mTeamID })?.homeURLString == "https://h5.m-team.cc/")
    }

    @Test
    func browserStoredSitesPreserveCustomOrderAndAppendMissingBuiltins() async throws {
        let customSite = BrowserSite(
            id: "custom-1",
            title: "自定义站点",
            homeURLString: "https://example.com",
            kind: .customPT,
            isBuiltin: false,
            isVisible: true
        )
        let storedSites = [
            BrowserSite(
                id: BrowserSite.hdkylID,
                title: "HDKyl",
                homeURLString: "https://www.hdkyl.in/",
                kind: .hdkyl,
                isBuiltin: true,
                isVisible: true
            ),
            customSite,
            BrowserSite(
                id: BrowserSite.mTeamID,
                title: "M-Team",
                homeURLString: "https://h5.m-team.cc/",
                kind: .mTeam,
                isBuiltin: true,
                isVisible: true
            ),
        ]

        let merged = BrowserSite.mergedStoredSitesPreservingOrder(storedSites)

        #expect(merged.map(\.id) == [
            BrowserSite.hdkylID,
            "custom-1",
            BrowserSite.mTeamID,
            BrowserSite.moviePilotID,
        ])
    }

    @Test
    func browserNormalizeAddressAddsHTTPSWhenSchemeMissing() async throws {
        let url = BrowserSite.normalizeAddress("www.hdkyl.in")

        #expect(url?.absoluteString == "https://www.hdkyl.in")
    }

    @Test
    func browserMTeamTorrentIdentifierParsingSupportsCommonURLShapes() async throws {
        let resolver = BrowserPTResourceResolver()
        let detailsPHPResource = BrowserResource(
            id: "1",
            title: "A",
            subtitle: nil,
            detailsURLString: "https://kp.m-team.cc/details.php?id=349061",
            downloadURLString: nil,
            imageURLString: nil,
            torrentID: nil,
            isFree: false
        )
        let hashRouteResource = BrowserResource(
            id: "2",
            title: "B",
            subtitle: nil,
            detailsURLString: "https://h5.m-team.cc/#/349061",
            downloadURLString: nil,
            imageURLString: nil,
            torrentID: nil,
            isFree: false
        )

        #expect(resolver.extractTorrentID(from: detailsPHPResource) == "349061")
        #expect(resolver.extractTorrentID(from: hashRouteResource) == "349061")
    }

    @Test
    func browserMTeamTorrentIdentifierParsingRejectsUserProfileLikeURLs() async throws {
        let resolver = BrowserPTResourceResolver()
        let userProfileResource = BrowserResource(
            id: "1",
            title: "mmk",
            subtitle: nil,
            detailsURLString: "https://kp.m-team.cc/userdetails.php?id=123456",
            downloadURLString: nil,
            imageURLString: nil,
            torrentID: nil,
            isFree: false
        )
        let genericProfileRoute = BrowserResource(
            id: "2",
            title: "profile",
            subtitle: nil,
            detailsURLString: "https://h5.m-team.cc/#/profile?id=123456",
            downloadURLString: nil,
            imageURLString: nil,
            torrentID: nil,
            isFree: false
        )

        #expect(resolver.extractTorrentID(from: userProfileResource) == nil)
        #expect(resolver.extractTorrentID(from: genericProfileRoute) == nil)
    }

    @Test
    func qbRemoteAddOutcomeMessagesMatchOutcomeKind() async throws {
        let duplicateOutcome = QBittorrentRemoteAddOutcome(kind: .duplicateLike, attemptedCount: 2, addedCount: 0)
        let partialOutcome = QBittorrentRemoteAddOutcome(kind: .partial, attemptedCount: 3, addedCount: 1)

        #expect(duplicateOutcome.message == "qBittorrent 没有新增任务，这些资源可能已经存在。")
        #expect(partialOutcome.message == "qBittorrent 只新增了 1/3 个任务，其余资源可能已存在。")
    }

}
