import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingConnectSheet = false
    @State private var selectedMovie: JellyfinMovie?

    var body: some View {
        NavigationStack {
            let jellyfin = appState.jellyfin

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let session = jellyfin.session {
                        JellyfinServerCard(
                            session: session,
                            isRefreshing: jellyfin.isRefreshing,
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

                        if jellyfin.libraries.isEmpty == false {
                            sectionHeader("电影库")

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(jellyfin.libraries) { library in
                                    Button {
                                        appState.selectedTab = .library
                                        jellyfin.selectLibrary(library.id)
                                    } label: {
                                        JellyfinLibraryChip(
                                            library: library,
                                            isSelected: library.id == jellyfin.selectedLibraryID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

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
                    } else {
                        EmptyStateCard(
                            title: "连接你的 Jellyfin 服务器",
                            message: "先把最容易马上用起来的部分做通：登录 Jellyfin 后，我们会立刻展示电影库和最近新增内容。",
                            buttonTitle: "连接 Jellyfin",
                            action: { isPresentingConnectSheet = true }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("MediaHarbor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appState.jellyfin.isConnected ? "管理" : "连接") {
                        isPresentingConnectSheet = true
                    }
                }
            }
            .refreshable {
                await jellyfin.refreshDashboard(forceReloadLibrary: true)
            }
            .task {
                if jellyfin.isConnected && jellyfin.libraries.isEmpty && jellyfin.isRefreshing == false {
                    await jellyfin.refreshDashboard(forceReloadLibrary: true)
                }
            }
            .sheet(isPresented: $isPresentingConnectSheet) {
                JellyfinConnectView()
            }
            .sheet(item: $selectedMovie) { movie in
                NavigationStack {
                    JellyfinMovieDetailView(movie: movie)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.bottom, -6)
    }
}
