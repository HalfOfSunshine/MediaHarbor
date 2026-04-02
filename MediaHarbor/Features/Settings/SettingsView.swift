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

                Section("qBittorrent") {
                    if let session = appState.qbittorrent.session {
                        LabeledContent("地址", value: session.serverURLString)
                        LabeledContent("用户", value: session.username)

                        if let version = session.version {
                            LabeledContent("版本", value: version)
                        }

                        Button("打开下载管理") {
                            appState.selectedTab = .downloads
                        }
                    } else {
                        Text("还没有连接 qBittorrent。下载页现在已经可以直接接入 WebUI 做基础管理。")
                            .foregroundStyle(.secondary)

                        Button("前往下载页") {
                            appState.selectedTab = .downloads
                        }
                    }
                }

                Section("浏览器") {
                    Toggle(
                        "显示浏览器 Tab",
                        isOn: Binding(
                            get: { appState.browser.isEnabled },
                            set: {
                                appState.browser.setEnabled($0)
                                if $0 == false, appState.selectedTab == .browser {
                                    appState.selectedTab = .library
                                }
                            }
                        )
                    )

                    NavigationLink("浏览器与 PT 站点") {
                        BrowserSettingsView()
                    }

                    Button("打开浏览器") {
                        appState.selectedTab = .browser
                    }
                    .disabled(appState.browser.isEnabled == false)
                }

                Section("外部播放") {
                    Picker("默认打开方式", selection: Binding(
                        get: { appState.jellyfinPlaybackPreferences.preferredOpenTarget },
                        set: { appState.jellyfinPlaybackPreferences.preferredOpenTarget = $0 }
                    )) {
                        ForEach(JellyfinPlaybackOpenTarget.allCases) { target in
                            Text(target.title)
                                .tag(target)
                        }
                    }

                    Text("默认值现在是 App 内播放。电影和可播放剧集会按这里的默认方式显示主操作卡片；电视剧本身会优先保留应用内选集，再把网页、Infuse、VidHub 作为备选。切换默认方式只会更新卡片样式，不会立即跳转或播放。")
                        .foregroundStyle(.secondary)
                }

                Section("构建说明") {
                    Text("当前这版已经把 Jellyfin 和 qBittorrent 的基础链路接起来了，目标是先让 NAS 上最常用的管理动作都能在 iPhone 上跑通。")
                    Text("Debug 构建对本地网络测试更友好。等准备公开发布前，我们再继续收紧 ATS、补播放入口，并把下载器能力继续做细。")
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
