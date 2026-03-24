import SwiftUI

struct JellyfinConnectView: View {
    private enum Field: Hashable {
        case serverURL
        case username
        case password
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            let jellyfin = appState.jellyfin

            Form {
                Section("已保存账号") {
                    if jellyfin.savedSessions.isEmpty {
                        Text("还没有已保存的 Jellyfin 账号。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(jellyfin.savedSessions) { savedSession in
                            Button {
                                Task {
                                    let switched = await jellyfin.switchSession(to: savedSession)
                                    if switched {
                                        dismiss()
                                    }
                                }
                            } label: {
                                JellyfinSavedSessionRow(
                                    session: savedSession,
                                    isActive: jellyfin.session?.accountKey == savedSession.accountKey
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(jellyfin.session?.accountKey == savedSession.accountKey)
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    Task {
                                        await jellyfin.removeSession(savedSession)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("添加账号") {
                    TextField("http://192.168.1.10:8096", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .serverURL)

                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)

                    SecureField("密码", text: $password)
                        .focused($focusedField, equals: .password)

                    Text("支持 `http://` 和 `https://`。如果你没有填写协议头，MediaHarbor 会默认补成 `https://`。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("说明") {
                    Text("同一台 Jellyfin 服务器可以保存多个账号；不同服务器使用同一个用户名也没问题。只有“服务器地址 + Jellyfin 用户”完全相同的时候，MediaHarbor 才会把它当成同一个已保存账号并更新。")
                    Text("新增成功后会自动切换到这个账号，并立刻重新加载媒体库和最近新增内容。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Jellyfin 账号")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        focusedField = nil
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(jellyfin.isConnecting ? "添加中..." : "添加") {
                        Task {
                            focusedField = nil
                            let connected = await jellyfin.connect(
                                serverURLString: serverURL,
                                username: username,
                                password: password
                            )

                            if connected {
                                password = ""
                                dismiss()
                            }
                        }
                    }
                    .disabled(jellyfin.isConnecting || formIsInvalid)
                }
            }
            .task {
                guard serverURL.isEmpty, username.isEmpty, let session = jellyfin.session else {
                    return
                }

                serverURL = session.serverURLString
                username = session.username
            }
            .alert(
                "Jellyfin 操作失败",
                isPresented: Binding(
                    get: { jellyfin.errorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            jellyfin.errorMessage = nil
                        }
                    }
                ),
                actions: {
                    Button("确定", role: .cancel) {}
                },
                message: {
                    Text(jellyfin.errorMessage ?? "未知错误。")
                }
            )
        }
    }

    private var formIsInvalid: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
