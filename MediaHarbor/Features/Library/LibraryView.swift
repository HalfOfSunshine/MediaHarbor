import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingConnectSheet = false

    var body: some View {
        NavigationStack {
            let jellyfin = appState.jellyfin

            Group {
                if jellyfin.isConnected == false {
                    EmptyStateCard(
                        title: "还没有连接媒体库",
                        message: "先连接 Jellyfin，这个标签页就会变成你的电影架。",
                        buttonTitle: "连接 Jellyfin",
                        action: { isPresentingConnectSheet = true }
                    )
                    .padding()
                } else if jellyfin.libraries.isEmpty {
                    ContentUnavailableView(
                        "没有找到媒体库",
                        systemImage: "rectangle.stack.badge.person.crop",
                        description: Text("MediaHarbor 还没有找到可展示的媒体库。可以尝试刷新，或者检查 Jellyfin 用户权限。")
                    )
                    .padding()
                } else {
                    ScrollView {
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
                        .padding()
                    }
                }
            }
            .navigationTitle("媒体库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if jellyfin.isConnected {
                        Button {
                            Task {
                                await jellyfin.refreshDashboard(forceReloadLibrary: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    } else {
                        Button("连接") {
                            isPresentingConnectSheet = true
                        }
                    }
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
        }
    }
}
