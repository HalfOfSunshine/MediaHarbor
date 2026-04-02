import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingConnectSheet = false
    @State private var selectedMovie: JellyfinMovie?
    @State private var selectedLibraryItem: JellyfinLibraryItem?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            let jellyfin = appState.jellyfin

            Group {
                if jellyfin.isConnected == false {
                    EmptyStateCard(
                        title: "连接你的 Jellyfin 服务器",
                        message: "先把 Jellyfin 连起来，这里会直接展示媒体库、最近新增、继续播放和收藏内容。",
                        buttonTitle: "连接 Jellyfin",
                        action: { isPresentingConnectSheet = true }
                    )
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let session = jellyfin.session {
                                JellyfinServerCard(
                                    session: session,
                                    isRefreshing: jellyfin.isRefreshing,
                                    showsServerURL: false,
                                    refreshAction: {
                                        Task {
                                            await jellyfin.refreshDashboard(forceReloadLibrary: true)
                                        }
                                    }
                                )

                                NavigationLink {
                                    JellyfinConsoleView()
                                } label: {
                                    Label("打开 Jellyfin 控制台", systemImage: "switch.2")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                searchSection
                            } else {
                                librarySection
                                latestSection
                                resumeSection
                                nextUpSection
                                favoritesSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("媒体库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appState.jellyfin.isConnected ? "管理" : "连接") {
                        isPresentingConnectSheet = true
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索电影、剧集、单集")
            .onChange(of: searchText) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard Task.isCancelled == false else {
                        return
                    }

                    await jellyfin.searchItems(searchText)
                }
            }
            .task {
                if jellyfin.isConnected && jellyfin.libraries.isEmpty && jellyfin.isRefreshing == false {
                    await jellyfin.refreshDashboard(forceReloadLibrary: true)
                }
            }
            .refreshable {
                await jellyfin.refreshDashboard(forceReloadLibrary: true)
            }
            .sheet(isPresented: $isPresentingConnectSheet) {
                JellyfinConnectView()
            }
            .sheet(item: $selectedMovie) { movie in
                NavigationStack {
                    JellyfinMovieDetailView(movie: movie)
                }
            }
            .sheet(item: $selectedLibraryItem) { item in
                NavigationStack {
                    JellyfinLibraryItemDetailView(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("媒体库")

        if jellyfin.libraries.isEmpty {
            ContentUnavailableView(
                "没有找到媒体库",
                systemImage: "rectangle.stack.badge.person.crop",
                description: Text("MediaHarbor 还没有找到可展示的媒体库。可以尝试刷新，或者检查 Jellyfin 用户权限。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(jellyfin.libraries) { library in
                    NavigationLink {
                        LibraryDetailView(library: library)
                    } label: {
                        JellyfinLibraryListCard(
                            library: library,
                            isSelected: library.id == jellyfin.selectedLibraryID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var latestSection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("最近新增")

        if jellyfin.recentMovies.isEmpty {
            ContentUnavailableView(
                "还没有电影",
                systemImage: "film",
                description: Text("等 Jellyfin 返回数据后，这里会展示最近新增的电影。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(jellyfin.recentMovies) { movie in
                        Button {
                            selectedMovie = movie
                        } label: {
                            JellyfinMovieCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var resumeSection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("继续播放")

        if jellyfin.resumeItems.isEmpty {
            JellyfinInfoNote(title: "继续播放", message: "Jellyfin 还没有返回带播放进度的条目。等你开始观看后，这里会显示续播入口。")
        } else {
            horizontalLibraryItems(jellyfin.resumeItems)
        }
    }

    @ViewBuilder
    private var nextUpSection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("接下来观看")

        if jellyfin.nextUpItems.isEmpty {
            JellyfinInfoNote(title: "接下来观看", message: "如果你在追剧，Jellyfin 会在这里返回下一集。")
        } else {
            horizontalLibraryItems(jellyfin.nextUpItems)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("喜欢 / 收藏")

        if jellyfin.favoriteItems.isEmpty {
            JellyfinInfoNote(title: "喜欢 / 收藏", message: "你在详情页点过心形按钮后，这里会聚合显示喜欢的电影、剧集或单集。")
        } else {
            horizontalLibraryItems(jellyfin.favoriteItems)
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let jellyfin = appState.jellyfin

        sectionHeader("搜索结果")

        if jellyfin.isSearching {
            ProgressView("正在搜索...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else if let searchErrorMessage = jellyfin.searchErrorMessage {
            Text(searchErrorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if jellyfin.searchResults.isEmpty {
            ContentUnavailableView(
                "没有找到结果",
                systemImage: "magnifyingglass",
                description: Text("换个关键词再试。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(jellyfin.searchResults) { item in
                    NavigationLink {
                        JellyfinLibraryItemDetailView(item: item)
                    } label: {
                        JellyfinLibraryItemGridCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func horizontalLibraryItems(_ items: [JellyfinLibraryItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    Button {
                        selectedLibraryItem = item
                    } label: {
                        JellyfinLibraryItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.bottom, -6)
    }
}
