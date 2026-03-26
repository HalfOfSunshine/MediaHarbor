//
//  MediaHarborTests.swift
//  MediaHarborTests
//
//  Created by mamingkang on 2026/3/24.
//

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

}
