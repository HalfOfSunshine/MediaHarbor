import SwiftUI

struct JellyfinConsoleView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let jellyfin = appState.jellyfin

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                    actionSection

                    if let notice = jellyfin.consoleNotice {
                        JellyfinInfoNote(
                            title: "控制台提示",
                            message: notice
                        )
                    }

                    if let error = jellyfin.consoleErrorMessage {
                        JellyfinInfoNote(
                            title: "控制台错误",
                            message: error
                        )
                    }

                    librariesSection
                    scanStatusSection
                    tasksSection
                } else {
                    EmptyStateCard(
                        title: "请先连接 Jellyfin",
                        message: "MediaHarbor 登录到你的 Jellyfin 服务器后，管理控制台才会可用。",
                        buttonTitle: "回到媒体库",
                        action: {
                            appState.selectedTab = .library
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Jellyfin 控制台")
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageStyle()
        .task {
            guard jellyfin.isConnected else {
                return
            }

            if jellyfin.libraries.isEmpty {
                await jellyfin.refreshDashboard()
            }

            await jellyfin.refreshConsole()
        }
        .task(id: jellyfin.libraryScanTask?.state == .running ? jellyfin.libraryScanTask?.id : nil) {
            guard jellyfin.libraryScanTask?.isRunning == true else {
                return
            }

            while Task.isCancelled == false && jellyfin.libraryScanTask?.isRunning == true {
                try? await Task.sleep(for: .seconds(4))
                guard Task.isCancelled == false else {
                    return
                }

                await jellyfin.refreshConsole()
            }
        }
        .refreshable {
            await jellyfin.refreshDashboard(forceReloadLibrary: true)
            await jellyfin.refreshConsole()
        }
    }

    private var actionSection: some View {
        let jellyfin = appState.jellyfin

        return VStack(alignment: .leading, spacing: 14) {
            Text("操作")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task {
                        await jellyfin.refreshDashboard(forceReloadLibrary: true)
                        await jellyfin.refreshConsole()
                    }
                } label: {
                    Label("重新加载应用数据", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(jellyfin.isRefreshing || jellyfin.isLoadingConsole)

                Button {
                    Task {
                        await jellyfin.startLibraryScan()
                    }
                } label: {
                    HStack {
                        Label("扫描所有媒体库", systemImage: "externaldrive.badge.timemachine")
                        Spacer()

                        if jellyfin.isStartingLibraryScan {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(jellyfin.isStartingLibraryScan)

                if jellyfin.libraryScanTask?.isRunning == true {
                    Button(role: .destructive) {
                        Task {
                            await jellyfin.stopLibraryScan()
                        }
                    } label: {
                        HStack {
                            Label("停止当前扫描", systemImage: "stop.circle")
                            Spacer()

                            if jellyfin.isStoppingLibraryScan {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(jellyfin.isStoppingLibraryScan)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var librariesSection: some View {
        let jellyfin = appState.jellyfin

        return VStack(alignment: .leading, spacing: 14) {
            Text("媒体库")
                .font(.title3.weight(.semibold))

            JellyfinInfoNote(
                title: jellyfin.consoleLibrarySource.noticeTitle,
                message: jellyfin.consoleLibrarySource.noticeMessage
            )

            if let notice = jellyfin.libraryNoticeMessage {
                JellyfinInfoNote(
                    title: "媒体库提示",
                    message: notice
                )
            }

            if let error = jellyfin.libraryErrorMessage {
                JellyfinInfoNote(
                    title: "媒体库错误",
                    message: error
                )
            }

            if jellyfin.hiddenManagedLibraryCount > 0 {
                JellyfinInfoNote(
                    title: "已隐藏的后台媒体库",
                    message: "有 \(jellyfin.hiddenManagedLibraryCount) 个后台媒体库当前账号可以做全库扫描，但不能稳定单独刷新，所以这里不再列出。需要处理它们时，请使用“扫描所有媒体库”。"
                )
            }

            if jellyfin.refreshableManagedLibraries.isEmpty {
                if jellyfin.isRefreshing || jellyfin.isLoadingConsole {
                    ProgressView("正在载入媒体库...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                } else {
                    JellyfinInfoNote(
                        title: "没有找到媒体库",
                        message: "Jellyfin 当前没有返回可管理的媒体库。可以先重新加载应用数据；如果你本来期望看到后台全部媒体库，也可以确认当前账号是否有管理员权限。"
                    )
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(jellyfin.refreshableManagedLibraries) { library in
                        JellyfinManagedLibraryRow(
                            library: library,
                            isRefreshing: jellyfin.refreshingLibraryID == library.id,
                            isActionDisabled: jellyfin.isRefreshingSingleLibrary,
                            action: {
                                Task {
                                    await jellyfin.refreshLibrary(library)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var scanStatusSection: some View {
        let jellyfin = appState.jellyfin

        return VStack(alignment: .leading, spacing: 14) {
            Text("扫描状态")
                .font(.title3.weight(.semibold))

            if let scanTask = jellyfin.libraryScanTask {
                JellyfinTaskRow(task: scanTask)
            } else {
                JellyfinInfoNote(
                    title: "没有找到扫描任务",
                    message: "MediaHarbor 还没有找到 Jellyfin 的扫描媒体库任务。如果服务器任务刚创建出来，或者名称本地化不同，可以下拉再刷新一次。"
                )
            }
        }
    }

    private var tasksSection: some View {
        let jellyfin = appState.jellyfin

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("计划任务")
                    .font(.title3.weight(.semibold))

                Spacer()

                if jellyfin.isLoadingConsole {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            LazyVStack(spacing: 12) {
                ForEach(jellyfin.scheduledTasks.prefix(8)) { task in
                    JellyfinTaskRow(task: task)
                }
            }
        }
    }
}
