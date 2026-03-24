import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingConnectSheet = false

    var body: some View {
        NavigationStack {
            let jellyfin = appState.jellyfin

            List {
                Section("Jellyfin") {
                    if let session = jellyfin.session {
                        LabeledContent("服务器", value: session.serverName)
                        LabeledContent("用户", value: session.username)
                        LabeledContent("地址", value: session.serverURLString)
                        LabeledContent("已保存账号", value: "\(jellyfin.savedSessions.count)")

                        if let version = session.serverVersion {
                            LabeledContent("版本", value: version)
                        }

                        NavigationLink("打开 Jellyfin 控制台") {
                            JellyfinConsoleView()
                        }

                        Button("管理账号") {
                            isPresentingConnectSheet = true
                        }

                        Button("刷新概览") {
                            Task {
                                await jellyfin.refreshDashboard(forceReloadLibrary: true)
                            }
                        }

                        Button("移除当前账号", role: .destructive) {
                            jellyfin.disconnect()
                        }
                    } else {
                        if jellyfin.savedSessions.isEmpty {
                            Text("还没有连接 Jellyfin 服务器。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("当前没有激活账号，可以从已保存账号里重新切换。")
                                .foregroundStyle(.secondary)
                            LabeledContent("已保存账号", value: "\(jellyfin.savedSessions.count)")
                        }

                        Button("管理账号") {
                            isPresentingConnectSheet = true
                        }
                    }
                }

                if jellyfin.savedSessions.isEmpty == false {
                    Section("已保存账号") {
                        ForEach(jellyfin.savedSessions) { savedSession in
                            JellyfinSavedSessionRow(
                                session: savedSession,
                                isActive: jellyfin.session?.accountKey == savedSession.accountKey
                            )
                        }
                    }
                }

                Section("构建说明") {
                    Text("当前这版 app 优先让 Jellyfin 尽快达到可用状态。")
                    Text("Debug 构建对本地网络测试更友好。等准备公开发布前，我们再继续收紧 ATS、完善凭据存储，并补完下载器模块。")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("设置")
            .sheet(isPresented: $isPresentingConnectSheet) {
                JellyfinConnectView()
            }
        }
    }
}
