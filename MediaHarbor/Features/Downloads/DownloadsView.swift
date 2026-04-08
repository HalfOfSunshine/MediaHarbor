import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingConnectSheet = false
    @State private var searchText = ""
    @State private var pendingDeleteTorrent: QBTorrent?
    @State private var currentPage = 0
    @State private var pageSize: QBTorrentPageSize = .twenty

    var body: some View {
        NavigationStack {
            let qbittorrent = appState.qbittorrent

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let session = qbittorrent.session {
                        QBittorrentServerCard(
                            session: session,
                            isRefreshing: qbittorrent.isRefreshing
                        ) {
                            Task {
                                await qbittorrent.refresh()
                            }
                        }

                        if let transferInfo = qbittorrent.transferInfo {
                            QBittorrentTransferOverviewCard(
                                info: transferInfo,
                                torrentCount: qbittorrent.torrents.count,
                                activeTorrentCount: qbittorrent.torrents.filter { $0.downloadSpeed > 0 || $0.uploadSpeed > 0 }.count
                            )
                        }

                        if let noticeMessage = qbittorrent.noticeMessage {
                            JellyfinInfoNote(title: "最近操作", message: noticeMessage)
                        }

                        if filteredTorrents.isEmpty {
                            EmptyStateCard(
                                title: qbittorrent.isRefreshing ? "正在同步 qBittorrent" : "当前没有下载任务",
                                message: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "已经连上 qBittorrent 了，但当前队列里没有可显示的任务。"
                                : "没有找到和当前搜索词匹配的任务。",
                                buttonTitle: "重新加载",
                                action: {
                                    Task {
                                        await qbittorrent.refresh()
                                    }
                                }
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("下载队列")
                                    .font(.title3.weight(.bold))

                                QBTorrentPaginationCard(
                                    pageSize: $pageSize,
                                    sortKey: Binding(
                                        get: { qbittorrent.sortKey },
                                        set: { newValue in
                                            currentPage = 0
                                            qbittorrent.sortKey = newValue
                                            Task {
                                                await qbittorrent.refresh()
                                            }
                                        }
                                    ),
                                    sortDirection: Binding(
                                        get: { qbittorrent.sortDirection },
                                        set: { newValue in
                                            currentPage = 0
                                            qbittorrent.sortDirection = newValue
                                            Task {
                                                await qbittorrent.refresh()
                                            }
                                        }
                                    ),
                                    currentPage: normalizedPageIndex,
                                    totalPages: totalPages,
                                    itemRangeText: itemRangeText
                                ) {
                                    currentPage = max(normalizedPageIndex - 1, 0)
                                } nextAction: {
                                    currentPage = min(normalizedPageIndex + 1, totalPages - 1)
                                }

                                LazyVStack(spacing: 12) {
                                    ForEach(pagedTorrents) { torrent in
                                        QBTorrentRow(
                                            torrent: torrent,
                                            isBusy: qbittorrent.actingTorrentHash == torrent.hash || qbittorrent.deletingTorrentHash == torrent.hash
                                        ) {
                                            Task {
                                                await qbittorrent.togglePause(for: torrent)
                                            }
                                        } deleteAction: {
                                            pendingDeleteTorrent = torrent
                                        }
                                    }
                                }

                                if totalPages > 1 {
                                    QBTorrentPaginationControls(
                                        currentPage: normalizedPageIndex,
                                        totalPages: totalPages
                                    ) {
                                        currentPage = max(normalizedPageIndex - 1, 0)
                                    } nextAction: {
                                        currentPage = min(normalizedPageIndex + 1, totalPages - 1)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    } else {
                        EmptyStateCard(
                            title: "连接 qBittorrent",
                            message: "接入之后，这里会显示下载队列、实时上传下载速度，以及暂停、继续、删任务这些基础控制。",
                            buttonTitle: "添加下载器",
                            action: {
                                isPresentingConnectSheet = true
                            }
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("这一版先做到")
                                .font(.headline)

                            Label("连接 qBittorrent WebUI", systemImage: "link.circle")
                            Label("查看当前任务、下载速度和上传速度", systemImage: "speedometer")
                            Label("暂停、继续和删除任务", systemImage: "pause.circle")
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding()
            }
            .navigationTitle("下载")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索任务名、分类或标签")
            .refreshable {
                await qbittorrent.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(qbittorrent.session == nil ? "连接" : "管理") {
                        isPresentingConnectSheet = true
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await qbittorrent.refresh()
                        }
                    } label: {
                        if qbittorrent.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(qbittorrent.session == nil || qbittorrent.isRefreshing)
                    .accessibilityLabel("刷新")
                }
            }
            .task {
                await qbittorrent.refreshIfNeeded()
            }
            .onChange(of: searchText) { _, _ in
                currentPage = 0
            }
            .onChange(of: pageSize) { _, _ in
                currentPage = 0
            }
            .onChange(of: appState.qbittorrent.torrents.count) { _, _ in
                currentPage = normalizedPageIndex
            }
            .sheet(isPresented: $isPresentingConnectSheet) {
                QBittorrentConnectView()
            }
            .confirmationDialog(
                "删除任务",
                isPresented: Binding(
                    get: { pendingDeleteTorrent != nil },
                    set: { isPresented in
                        if isPresented == false {
                            pendingDeleteTorrent = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let torrent = pendingDeleteTorrent {
                    Button("仅删除任务", role: .destructive) {
                        Task {
                            await qbittorrent.delete(torrent, deleteFiles: false)
                            pendingDeleteTorrent = nil
                        }
                    }

                    Button("删除任务和文件", role: .destructive) {
                        Task {
                            await qbittorrent.delete(torrent, deleteFiles: true)
                            pendingDeleteTorrent = nil
                        }
                    }
                }

                Button("取消", role: .cancel) {
                    pendingDeleteTorrent = nil
                }
            } message: {
                if let torrent = pendingDeleteTorrent {
                    Text("要删除“\(torrent.name)”吗？")
                }
            }
            .alert(
                "qBittorrent 操作失败",
                isPresented: Binding(
                    get: { qbittorrent.errorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            qbittorrent.errorMessage = nil
                        }
                    }
                ),
                actions: {
                    Button("确定", role: .cancel) {}
                },
                message: {
                    Text(qbittorrent.errorMessage ?? "未知错误。")
                }
            )
        }
    }

    private var filteredTorrents: [QBTorrent] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let torrents = appState.qbittorrent.torrents

        guard trimmedSearch.isEmpty == false else {
            return torrents
        }

        return torrents.filter { $0.matches(searchTerm: trimmedSearch) }
    }

    private var totalPages: Int {
        QBTorrentPagination.totalPages(itemCount: filteredTorrents.count, pageSize: pageSize.rawValue)
    }

    private var normalizedPageIndex: Int {
        QBTorrentPagination.normalizedPageIndex(currentPage, itemCount: filteredTorrents.count, pageSize: pageSize.rawValue)
    }

    private var pagedTorrents: [QBTorrent] {
        Array(QBTorrentPagination.items(filteredTorrents, pageIndex: currentPage, pageSize: pageSize.rawValue))
    }

    private var itemRangeText: String {
        QBTorrentPagination.rangeText(itemCount: filteredTorrents.count, pageIndex: currentPage, pageSize: pageSize.rawValue)
    }
}
