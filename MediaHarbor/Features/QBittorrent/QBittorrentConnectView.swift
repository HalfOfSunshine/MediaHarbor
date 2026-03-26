import SwiftUI

struct QBittorrentConnectView: View {
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
            let qbittorrent = appState.qbittorrent

            Form {
                if let session = qbittorrent.session {
                    Section("当前连接") {
                        LabeledContent("地址", value: session.serverURLString)
                        LabeledContent("用户", value: session.username)

                        if let version = session.version {
                            LabeledContent("版本", value: version)
                        }

                        Button("移除当前连接", role: .destructive) {
                            qbittorrent.disconnect()
                            dismiss()
                        }
                    }
                }

                Section("连接 qBittorrent") {
                    TextField("http://192.168.1.10:8899", text: $serverURL)
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

                    Text("支持 `http://` 和 `https://`。如果你只输入域名或 IP，MediaHarbor 会默认补成 `http://`，没填端口时自动补成 `:8899`；末尾带 `/` 也会自动兼容。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("说明") {
                    Text("这一版先接 qBittorrent 的基础管理能力：连接测试、传输速度、任务列表、暂停/继续和删除任务。")
                    Text("连接成功后，下载页会自动刷新并加载当前队列。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("qBittorrent")
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
                    Button(qbittorrent.isConnecting ? "连接中..." : "保存") {
                        Task {
                            focusedField = nil
                            let connected = await qbittorrent.connect(
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
                    .disabled(qbittorrent.isConnecting || formIsInvalid)
                }
            }
            .task {
                guard serverURL.isEmpty, username.isEmpty, let session = qbittorrent.session else {
                    return
                }

                serverURL = session.serverURLString
                username = session.username
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

    private var formIsInvalid: Bool {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
