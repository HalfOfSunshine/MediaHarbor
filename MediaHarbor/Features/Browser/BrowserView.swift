import SwiftUI

struct BrowserView: View {
    @Environment(AppState.self) private var appState

    @State private var isPresentingSettings = false
    @State private var isPresentingResourceAssistant = false

    var body: some View {
        let browser = appState.browser

        NavigationStack {
            Group {
                if browser.visibleSites.isEmpty {
                    ContentUnavailableView(
                        "还没有可用站点",
                        systemImage: "globe",
                        description: Text("先到浏览器设置里启用内置站点，或者添加一个自定义 PT 站点。")
                    )
                } else {
                    VStack(spacing: 0) {
                        if let selectedSite = browser.selectedSite {
                            if browser.isChromeCollapsed(for: selectedSite.id) == false {
                                BrowserSiteStrip(
                                    sites: browser.visibleSites,
                                    selectedSiteID: selectedSite.id,
                                    onSelect: { browser.selectSite($0) }
                                )

                                BrowserAddressToolbar(
                                    displayedURLString: displayedURLString(for: selectedSite),
                                    canGoBack: browser.pageSnapshot(for: selectedSite.id).canGoBack,
                                    canGoForward: browser.pageSnapshot(for: selectedSite.id).canGoForward,
                                    onBack: { browser.goBack() },
                                    onForward: { browser.goForward() },
                                    onHome: { browser.goHome() },
                                    onReload: { browser.reload() },
                                    onAutofill: { browser.autofillCurrentSite() },
                                    onOpenSettings: { isPresentingSettings = true },
                                    onSubmitAddress: { browser.navigateCurrentSite(to: $0) }
                                )

                                Divider()
                            }

                            ZStack {
                                ForEach(browser.visibleSites) { site in
                                    BrowserWebView(
                                        site: site,
                                        initialURL: initialURL(for: site),
                                        credential: browser.credential(for: site),
                                        handle: browser.handle(for: site.id)
                                    ) { snapshot in
                                        browser.updatePageSnapshot(for: site.id, snapshot: snapshot)
                                    } onScrollChanged: { offsetY, isUserInteracting in
                                        browser.updateChromeVisibility(
                                            for: site.id,
                                            offsetY: offsetY,
                                            isUserInteracting: isUserInteracting
                                        )
                                    }
                                    .opacity(site.id == selectedSite.id ? 1 : 0)
                                    .allowsHitTesting(site.id == selectedSite.id)
                                }
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        if let selectedSite = browser.selectedSite,
                           browser.isChromeCollapsed(for: selectedSite.id) {
                            BrowserCollapsedChromeCapsule(
                                title: selectedSite.title,
                                subtitle: compactHost(for: selectedSite),
                                onExpand: { browser.setChromeCollapsed(false, for: selectedSite.id) },
                                onOpenSettings: { isPresentingSettings = true }
                            )
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let selectedSite = browser.selectedSite,
                           selectedSite.supportsResourceAssistant {
                            BrowserFloatingResourceButton(
                                resourceCount: browser.pageSnapshot(for: selectedSite.id).resources.count,
                                action: { isPresentingResourceAssistant = true }
                            )
                            .padding(.trailing, 18)
                            .padding(.bottom, 22)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.22), value: browser.selectedSite?.id)
                    .animation(.easeInOut(duration: 0.22), value: browser.selectedSite.map { browser.isChromeCollapsed(for: $0.id) } ?? false)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $isPresentingSettings) {
            BrowserSettingsView()
        }
        .sheet(isPresented: $isPresentingResourceAssistant) {
            if let selectedSite = appState.browser.selectedSite {
                BrowserResourceAssistantView(
                    site: selectedSite,
                    resources: appState.browser.pageSnapshot(for: selectedSite.id).resources
                )
            }
        }
    }

    private func initialURL(for site: BrowserSite) -> URL? {
        let currentURLString = appState.browser.pageSnapshot(for: site.id).currentURLString
        return URL(string: currentURLString).flatMap { _ in URL(string: currentURLString) } ?? site.normalizedHomeURL
    }

    private func displayedURLString(for site: BrowserSite) -> String {
        let snapshot = appState.browser.pageSnapshot(for: site.id)
        if snapshot.currentURLString.isEmpty == false {
            return snapshot.currentURLString
        }

        return site.homeURLString
    }

    private func compactHost(for site: BrowserSite) -> String {
        let currentURLString = appState.browser.pageSnapshot(for: site.id).currentURLString
        if let host = URL(string: currentURLString)?.host, host.isEmpty == false {
            return host
        }

        return site.host ?? site.homeURLString
    }
}

private struct BrowserSiteStrip: View {
    let sites: [BrowserSite]
    let selectedSiteID: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sites) { site in
                    Button {
                        onSelect(site.id)
                    } label: {
                        Text(site.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(site.id == selectedSiteID ? .white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(site.id == selectedSiteID ? MediaHarborTheme.tabSelectedColor : Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }
}

private struct BrowserAddressToolbar: View {
    let displayedURLString: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onHome: () -> Void
    let onReload: () -> Void
    let onAutofill: () -> Void
    let onOpenSettings: () -> Void
    let onSubmitAddress: (String) -> Void

    @State private var addressText = ""
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isAddressFocused == false {
                BrowserToolbarIconButton(systemName: "chevron.left", isEnabled: canGoBack, action: onBack)
                BrowserToolbarIconButton(systemName: "chevron.right", isEnabled: canGoForward, action: onForward)
                BrowserToolbarIconButton(systemName: "house", isEnabled: true, action: onHome)
            }

            addressField

            if isAddressFocused {
                Button("取消") {
                    addressText = displayedURLString
                    isAddressFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MediaHarborTheme.tabSelectedColor)
                .buttonStyle(.plain)
            } else {
                BrowserToolbarIconButton(systemName: "arrow.clockwise", isEnabled: true, action: onReload)
                BrowserToolbarIconButton(systemName: "person.text.rectangle", isEnabled: true, action: onAutofill)
                BrowserToolbarIconButton(systemName: "gearshape", isEnabled: true, action: onOpenSettings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onAppear {
            addressText = displayedURLString
        }
        .onChange(of: displayedURLString) { _, newValue in
            if isAddressFocused == false {
                addressText = newValue
            }
        }
        .onChange(of: isAddressFocused) { _, focused in
            if focused {
                addressText = displayedURLString
            }
        }
    }

    private var addressField: some View {
        TextField("输入网址", text: $addressText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .textContentType(.URL)
            .focused($isAddressFocused)
            .submitLabel(.go)
            .onSubmit {
                onSubmitAddress(addressText)
                isAddressFocused = false
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
    }
}

private struct BrowserToolbarIconButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }
}

private struct BrowserCollapsedChromeCapsule: View {
    let title: String
    let subtitle: String
    let onExpand: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 310)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct BrowserFloatingResourceButton: View {
    let resourceCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("资源助手")
                        .font(.subheadline.weight(.semibold))
                    Text(resourceCount > 0 ? "已识别 \(resourceCount) 个资源" : "当前页暂未识别到资源")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        MediaHarborTheme.tabSelectedColor.opacity(0.98),
                        MediaHarborTheme.tabSelectedColor.opacity(0.84),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .shadow(color: MediaHarborTheme.tabSelectedColor.opacity(0.28), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct BrowserSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var editingSite: BrowserSite?
    @State private var isPresentingAddSite = false

    var body: some View {
        NavigationStack {
            List {
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
                }

                Section("站点") {
                    ForEach(appState.browser.sites) { site in
                        Button {
                            editingSite = site
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(site.title)
                                        .font(.headline)
                                    if site.isBuiltin {
                                        Text("内置")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(site.homeURLString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { indexSet, newOffset in
                        appState.browser.moveSites(fromOffsets: indexSet, toOffset: newOffset)
                    }
                    .onDelete { indexSet in
                        let removableSites = indexSet.compactMap { index in
                            let site = appState.browser.sites[index]
                            return site.isBuiltin ? nil : site
                        }

                        removableSites.forEach { appState.browser.removeSite($0) }
                    }

                    Button("添加自定义 PT 站点") {
                        isPresentingAddSite = true
                    }

                    Text("长按拖动可以调整浏览器顶部站点页的顺序。内置站点也可以参与排序。")
                        .foregroundStyle(.secondary)
                }

                Section("默认下载选项") {
                    Picker(
                        "默认分类",
                        selection: Binding(
                            get: { appState.browser.preferredCategoryName },
                            set: {
                                appState.browser.setPreferredDownloadOptions(
                                    categoryName: $0,
                                    savePath: appState.browser.preferredSavePath
                                )
                            }
                        )
                    ) {
                        Text("不使用分类").tag("")
                        ForEach(appState.qbittorrent.categories) { category in
                            Text(category.displayTitle)
                                .tag(category.name)
                        }
                    }

                    TextField(
                        "默认保存路径",
                        text: Binding(
                            get: { appState.browser.preferredSavePath },
                            set: {
                                appState.browser.setPreferredDownloadOptions(
                                    categoryName: appState.browser.preferredCategoryName,
                                    savePath: $0
                                )
                            }
                        )
                    )
                    .disabled(appState.browser.preferredCategoryName.isEmpty == false)

                    if appState.browser.preferredCategoryName.isEmpty == false {
                        Text("已选默认分类。资源助手发送到 qBittorrent 时会沿用该分类自己的保存路径。")
                            .foregroundStyle(.secondary)
                    }

                    Button("刷新 qB 分类") {
                        Task {
                            await appState.qbittorrent.refreshCategories()
                        }
                    }
                }

                if let errorMessage = appState.browser.errorMessage {
                    Section("错误") {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("浏览器设置")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(item: $editingSite) { site in
                BrowserSiteEditorView(site: site)
            }
            .sheet(isPresented: $isPresentingAddSite) {
                BrowserCustomSiteCreateView()
            }
            .task {
                if appState.qbittorrent.session != nil, appState.qbittorrent.categories.isEmpty {
                    await appState.qbittorrent.refreshCategories()
                }
            }
        }
    }
}

private struct BrowserSiteEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let site: BrowserSite

    @State private var homeURLString = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiToken = ""
    @State private var isVisible = true
    @State private var localErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("站点") {
                    if site.isBuiltin == false {
                        LabeledContent("名称", value: site.title)
                    }

                    TextField("地址", text: $homeURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("显示在浏览器顶部", isOn: $isVisible)
                }

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("密码", text: $password)

                    if site.requiresAPIToken {
                        SecureField("API Token", text: $apiToken)
                    }
                }

                if let localErrorMessage {
                    Section("错误") {
                        Text(localErrorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(site.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                    }
                }
            }
            .onAppear {
                let credential = appState.browser.credential(for: site)
                homeURLString = site.homeURLString
                username = credential.username
                password = credential.password
                apiToken = credential.apiToken
                isVisible = site.isVisible
            }
        }
    }

    private func save() {
        let credential = BrowserCredential(username: username, password: password, apiToken: apiToken)
        let saved = appState.browser.saveSite(
            site,
            title: site.title,
            homeURLString: homeURLString,
            isVisible: isVisible,
            credential: credential
        )

        if saved {
            dismiss()
        } else {
            localErrorMessage = appState.browser.errorMessage
        }
    }
}

private struct BrowserCustomSiteCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var homeURLString = ""
    @State private var username = ""
    @State private var password = ""
    @State private var localErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("站点") {
                    TextField("名称", text: $title)
                    TextField("域名或地址", text: $homeURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }

                if let localErrorMessage {
                    Section("错误") {
                        Text(localErrorMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("添加 PT 站点")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let saved = appState.browser.addCustomPTSite(
            title: title,
            homeURLString: homeURLString,
            credential: BrowserCredential(username: username, password: password, apiToken: "")
        )

        if saved {
            dismiss()
        } else {
            localErrorMessage = appState.browser.errorMessage
        }
    }
}

private struct BrowserResourceAssistantView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let site: BrowserSite
    let resources: [BrowserResource]

    @State private var selectedResourceIDs = Set<String>()
    @State private var statusMessage: String?
    @State private var isSending = false
    @State private var selectedCategoryName = ""
    @State private var savePath = ""

    private let resolver = BrowserPTResourceResolver()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemBackground))
                }

                if resources.isEmpty {
                    ContentUnavailableView(
                        "没有识别到资源",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("当前页面没有识别到可发送到 qBittorrent 的 PT 资源。")
                    )
                } else {
                    List {
                        Section("选择") {
                            HStack {
                                Text("已选 \(selectedResourceIDs.count) / \(resources.count)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("全选") {
                                    selectedResourceIDs = Set(resources.map(\.id))
                                }
                                Button("全不选") {
                                    selectedResourceIDs.removeAll()
                                }
                            }

                            if resources.count == 1 {
                                Text("当前只有 1 个资源。点右上角“发送到 qB”后才会真正投递。")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("资源") {
                            ForEach(resources) { resource in
                                BrowserResourceRow(
                                    resource: resource,
                                    isSelected: selectedResourceIDs.contains(resource.id),
                                    onToggleSelection: {
                                        toggleSelection(for: resource)
                                    },
                                    onOpenDetails: {
                                        openDetails(for: resource)
                                    }
                                )
                            }
                        }

                        Section("qBittorrent") {
                            Picker("分类", selection: $selectedCategoryName) {
                                Text("不使用分类").tag("")
                                ForEach(appState.qbittorrent.categories) { category in
                                    Text(category.displayTitle)
                                        .tag(category.name)
                                }
                            }

                            TextField("保存路径", text: $savePath)
                                .disabled(selectedCategoryName.isEmpty == false)

                            if selectedCategoryName.isEmpty == false {
                                Text("已选分类，发送到 qBittorrent 时会沿用这个分类自己的保存路径。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("资源助手")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSending ? "发送中..." : "发送到 qB") {
                        Task {
                            await sendSelectedResources()
                        }
                    }
                    .disabled(isSending || resources.isEmpty)
                }
            }
            .task {
                if resources.count == 1, let onlyResource = resources.first {
                    selectedResourceIDs = [onlyResource.id]
                }

                selectedCategoryName = appState.browser.preferredCategoryName
                savePath = appState.browser.preferredSavePath

                if appState.qbittorrent.session != nil, appState.qbittorrent.categories.isEmpty {
                    await appState.qbittorrent.refreshCategories()
                }
            }
        }
    }

    private func toggleSelection(for resource: BrowserResource) {
        if selectedResourceIDs.contains(resource.id) {
            selectedResourceIDs.remove(resource.id)
        } else {
            selectedResourceIDs.insert(resource.id)
        }
    }

    private func openDetails(for resource: BrowserResource) {
        guard let detailsURLString = resource.detailsURLString,
              let url = URL(string: detailsURLString) else {
            statusMessage = "当前资源没有可打开的详情页。"
            return
        }

        appState.browser.handle(for: site.id).load(url)
        dismiss()
    }

    private func sendSelectedResources() async {
        let selectedResources = resources.filter { selectedResourceIDs.contains($0.id) }
        guard selectedResources.isEmpty == false else {
            statusMessage = "先选中要发送到 qBittorrent 的资源。"
            return
        }

        guard appState.qbittorrent.session != nil else {
            statusMessage = "还没有连接 qBittorrent，先去下载页登录。"
            return
        }

        isSending = true
        defer {
            isSending = false
        }

        do {
            let credential = appState.browser.credential(for: site)
            var urls: [URL] = []
            for resource in selectedResources {
                let url = try await resolver.resolveDownloadURL(for: resource, site: site, credential: credential)
                urls.append(url)
            }

            let trimmedSavePath = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalCategoryName = selectedCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalSavePath = finalCategoryName.isEmpty ? (trimmedSavePath.isEmpty ? nil : trimmedSavePath) : nil
            let cookieHeader = await appState.browser.cookieHeader(for: site)

            appState.browser.setPreferredDownloadOptions(categoryName: finalCategoryName, savePath: trimmedSavePath)
            let outcome = await appState.qbittorrent.addRemoteDownloads(
                urls: urls,
                category: finalCategoryName.isEmpty ? nil : finalCategoryName,
                savePath: finalSavePath,
                cookieHeader: cookieHeader
            )
            statusMessage = outcome.message
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct BrowserResourceRow: View {
    let resource: BrowserResource
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? MediaHarborTheme.tabSelectedColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            if let imageURLString = resource.imageURLString,
               let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                }
                .frame(width: 66, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(resource.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                if let subtitle = resource.subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if resource.canSendToDownloader == false {
                    Text("当前只识别到了详情入口，暂时不能直接投递到 qBittorrent。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if resource.detailsURLString != nil {
                    Button("打开详情", action: onOpenDetails)
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
    }
}
