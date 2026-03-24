import SwiftUI

struct LibraryDetailView: View {
    @Environment(AppState.self) private var appState

    let library: JellyfinLibrary

    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let jellyfin = appState.jellyfin
        let isCurrentLibrary = jellyfin.selectedLibraryID == library.id

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                JellyfinLibraryHeroCard(library: library)

                if let notice = jellyfin.libraryNoticeMessage, isCurrentLibrary {
                    JellyfinInfoNote(title: "当前媒体库", message: notice)
                }

                if let error = jellyfin.libraryErrorMessage, isCurrentLibrary {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isCurrentLibrary == false || (jellyfin.isLoadingLibrary && isCurrentLibrary) {
                    ProgressView("正在加载 \(library.name)...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else if jellyfin.libraryItems.isEmpty {
                    ContentUnavailableView(
                        "这个媒体库里还没有可展示的内容",
                        systemImage: "film.stack",
                        description: Text("可以尝试刷新当前媒体库，或者检查 Jellyfin 是否已经识别出电影和电视剧条目。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(jellyfin.libraryItems) { item in
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
            .padding()
        }
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await jellyfin.refreshLibrary(library)
                        }
                    } label: {
                        Label("刷新当前媒体库", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(jellyfin.isRefreshingSingleLibrary)

                    Button {
                        Task {
                            await jellyfin.startLibraryScan()
                        }
                    } label: {
                        Label("扫描所有媒体库", systemImage: "externaldrive.badge.timemachine")
                    }
                    .disabled(jellyfin.isStartingLibraryScan)
                } label: {
                    if jellyfin.isRefreshingSingleLibrary || jellyfin.isStartingLibraryScan {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索 \(library.kind.title)")
        .task {
            await jellyfin.loadLibraryItems(for: library, searchTerm: searchText, force: jellyfin.selectedLibraryID != library.id)
        }
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard Task.isCancelled == false else {
                    return
                }

                await jellyfin.loadLibraryItems(for: library, searchTerm: searchText, force: true)
            }
        }
        .refreshable {
            await jellyfin.loadLibraryItems(for: library, searchTerm: searchText, force: true)
        }
    }
}
