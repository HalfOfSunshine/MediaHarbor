import Foundation
import Observation

@MainActor
@Observable
final class BrowserStore {
    private enum Constants {
        static let enabledKey = "browser.enabled"
        static let sitesKey = "browser.sites"
        static let selectedSiteIDKey = "browser.selected-site-id"
        static let preferredCategoryKey = "browser.preferred-qb-category"
        static let preferredSavePathKey = "browser.preferred-qb-save-path"
    }

    var isEnabled: Bool
    var sites: [BrowserSite]
    var selectedSiteID: String
    var preferredCategoryName: String
    var preferredSavePath: String
    var errorMessage: String?

    @ObservationIgnored
    private let storage: CloudBackedDefaults

    @ObservationIgnored
    private let credentialStore: BrowserCredentialStore

    @ObservationIgnored
    private let encoder = JSONEncoder()

    @ObservationIgnored
    private let decoder = JSONDecoder()

    private var pageSnapshots: [String: BrowserPageSnapshot] = [:]

    @ObservationIgnored
    private var handles: [String: BrowserWebViewHandle] = [:]

    private var collapsedChromeSiteIDs: Set<String> = []

    @ObservationIgnored
    private var lastScrollOffsets: [String: CGFloat] = [:]

    @ObservationIgnored
    private var lastChromeToggleDates: [String: Date] = [:]

    @ObservationIgnored
    private var cloudObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore? = nil,
        credentialStore: BrowserCredentialStore = BrowserCredentialStore()
    ) {
        self.storage = CloudBackedDefaults(defaults: defaults, cloudStore: cloudStore)
        self.credentialStore = credentialStore
        self.isEnabled = storage.bool(forKey: Constants.enabledKey) ?? true
        self.sites = BrowserStore.loadSites(storage: storage)
        self.selectedSiteID = storage.string(forKey: Constants.selectedSiteIDKey) ?? BrowserSite.defaultSites().first?.id ?? ""
        self.preferredCategoryName = storage.string(forKey: Constants.preferredCategoryKey) ?? ""
        self.preferredSavePath = storage.string(forKey: Constants.preferredSavePathKey) ?? ""
        installCloudObserver()

        if sites.contains(where: { $0.id == selectedSiteID }) == false {
            selectedSiteID = sites.first?.id ?? ""
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    var visibleSites: [BrowserSite] {
        sites.filter(\.isVisible)
    }

    var selectedSite: BrowserSite? {
        visibleSites.first(where: { $0.id == selectedSiteID }) ?? visibleSites.first
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        storage.set(enabled, forKey: Constants.enabledKey)
    }

    func selectSite(_ siteID: String) {
        guard visibleSites.contains(where: { $0.id == siteID }) else {
            return
        }

        selectedSiteID = siteID
        storage.set(siteID, forKey: Constants.selectedSiteIDKey)
    }

    func pageSnapshot(for siteID: String) -> BrowserPageSnapshot {
        pageSnapshots[siteID] ?? .empty
    }

    func updatePageSnapshot(for siteID: String, snapshot: BrowserPageSnapshot) {
        pageSnapshots[siteID] = snapshot
    }

    func isChromeCollapsed(for siteID: String) -> Bool {
        collapsedChromeSiteIDs.contains(siteID)
    }

    func setChromeCollapsed(_ collapsed: Bool, for siteID: String) {
        if collapsed {
            collapsedChromeSiteIDs.insert(siteID)
        } else {
            collapsedChromeSiteIDs.remove(siteID)
        }

        lastChromeToggleDates[siteID] = Date()
    }

    func updateChromeVisibility(for siteID: String, offsetY: CGFloat, isUserInteracting: Bool) {
        let previousOffset = lastScrollOffsets[siteID] ?? offsetY
        lastScrollOffsets[siteID] = offsetY

        guard isUserInteracting else {
            if offsetY <= 18, isChromeCollapsed(for: siteID) {
                setChromeCollapsed(false, for: siteID)
            }
            return
        }

        let delta = offsetY - previousOffset
        let now = Date()
        let cooldownSatisfied: Bool
        if let lastToggleDate = lastChromeToggleDates[siteID] {
            cooldownSatisfied = now.timeIntervalSince(lastToggleDate) > 0.25
        } else {
            cooldownSatisfied = true
        }

        if offsetY <= 18 {
            if isChromeCollapsed(for: siteID) {
                setChromeCollapsed(false, for: siteID)
            }
            return
        }

        guard cooldownSatisfied else {
            return
        }

        if delta > 16, isChromeCollapsed(for: siteID) == false {
            setChromeCollapsed(true, for: siteID)
        } else if delta < -14, isChromeCollapsed(for: siteID) {
            setChromeCollapsed(false, for: siteID)
        }
    }

    func registerHandle(_ handle: BrowserWebViewHandle, for siteID: String) {
        handles[siteID] = handle
    }

    func handle(for siteID: String) -> BrowserWebViewHandle {
        if let handle = handles[siteID] {
            return handle
        }

        let handle = BrowserWebViewHandle()
        handles[siteID] = handle
        return handle
    }

    func reload() {
        selectedSite.map { handle(for: $0.id).reload() }
    }

    func goHome() {
        guard let site = selectedSite,
              let url = site.normalizedHomeURL else {
            return
        }

        handle(for: site.id).load(url)
    }

    func navigateCurrentSite(to rawAddress: String) {
        guard let site = selectedSite,
              let url = BrowserSite.normalizeAddress(rawAddress) else {
            errorMessage = "请输入有效的网址。"
            return
        }

        handle(for: site.id).load(url)
    }

    func autofillCurrentSite() {
        guard let site = selectedSite else {
            return
        }

        let credential = credential(for: site)
        handle(for: site.id).autofill(username: credential.trimmedUsername, password: credential.trimmedPassword)
    }

    func cookieHeader(for site: BrowserSite) async -> String? {
        guard let url = pageSnapshot(for: site.id).currentURLString.isEmpty == false
            ? URL(string: pageSnapshot(for: site.id).currentURLString)
            : site.normalizedHomeURL else {
            return nil
        }

        return await handle(for: site.id).cookieHeader(for: url)
    }

    func credential(for site: BrowserSite) -> BrowserCredential {
        credentialStore.loadCredential(for: site.id)
    }

    func saveSite(
        _ site: BrowserSite,
        title: String,
        homeURLString: String,
        isVisible: Bool,
        credential: BrowserCredential
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = site.isBuiltin ? site.title : trimmedTitle

        guard finalTitle.isEmpty == false else {
            errorMessage = "站点名称不能为空。"
            return false
        }

        guard let normalizedURL = BrowserSite.normalizeAddress(homeURLString) else {
            errorMessage = "请输入有效的站点地址。"
            return false
        }

        errorMessage = nil

        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index].title = finalTitle
            sites[index].homeURLString = normalizedURL.absoluteString
            sites[index].isVisible = isVisible
        } else {
            sites.append(
                BrowserSite(
                    id: site.id,
                    title: finalTitle,
                    homeURLString: normalizedURL.absoluteString,
                    kind: site.kind,
                    isBuiltin: site.isBuiltin,
                    isVisible: isVisible
                )
            )
        }

        persistSites()

        do {
            try credentialStore.saveCredential(credential, for: site.id)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        return true
    }

    func addCustomPTSite(title: String, homeURLString: String, credential: BrowserCredential) -> Bool {
        let site = BrowserSite(
            id: UUID().uuidString,
            title: title,
            homeURLString: homeURLString,
            kind: .customPT,
            isBuiltin: false,
            isVisible: true
        )

        let saved = saveSite(
            site,
            title: title,
            homeURLString: homeURLString,
            isVisible: true,
            credential: credential
        )

        if saved {
            selectSite(site.id)
        }

        return saved
    }

    func removeSite(_ site: BrowserSite) {
        guard site.isBuiltin == false else {
            return
        }

        sites.removeAll(where: { $0.id == site.id })
        credentialStore.deleteCredential(for: site.id)
        pageSnapshots.removeValue(forKey: site.id)
        handles.removeValue(forKey: site.id)
        collapsedChromeSiteIDs.remove(site.id)
        lastScrollOffsets.removeValue(forKey: site.id)
        lastChromeToggleDates.removeValue(forKey: site.id)
        persistSites()

        if selectedSiteID == site.id {
            selectSite(visibleSites.first?.id ?? "")
        }
    }

    func moveSites(fromOffsets: IndexSet, toOffset: Int) {
        let movingSites = fromOffsets.map { sites[$0] }
        var reorderedSites = sites.enumerated().compactMap { index, site in
            fromOffsets.contains(index) ? nil : site
        }

        let insertionIndex = min(max(toOffset - fromOffsets.filter { $0 < toOffset }.count, 0), reorderedSites.count)
        reorderedSites.insert(contentsOf: movingSites, at: insertionIndex)
        sites = reorderedSites
        persistSites()
    }

    func setPreferredDownloadOptions(categoryName: String, savePath: String) {
        preferredCategoryName = categoryName
        preferredSavePath = savePath
        storage.set(categoryName, forKey: Constants.preferredCategoryKey)
        storage.set(savePath, forKey: Constants.preferredSavePathKey)
    }

    private func persistSites() {
        let persistedSites = BrowserSite.mergedStoredSitesPreservingOrder(sites)
        sites = persistedSites

        if let data = try? encoder.encode(persistedSites) {
            storage.set(data, forKey: Constants.sitesKey)
        }
    }

    private static func loadSites(storage: CloudBackedDefaults) -> [BrowserSite] {
        guard let data = storage.data(forKey: Constants.sitesKey),
              let decodedSites = try? JSONDecoder().decode([BrowserSite].self, from: data) else {
            return BrowserSite.defaultSites()
        }

        return BrowserSite.mergedStoredSitesPreservingOrder(decodedSites)
    }

    private func installCloudObserver() {
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFromCloud()
            }
        }
    }

    private func syncFromCloud() {
        isEnabled = storage.bool(forKey: Constants.enabledKey) ?? true
        sites = BrowserStore.loadSites(storage: storage)
        preferredCategoryName = storage.string(forKey: Constants.preferredCategoryKey) ?? ""
        preferredSavePath = storage.string(forKey: Constants.preferredSavePathKey) ?? ""

        let persistedSelectedSiteID = storage.string(forKey: Constants.selectedSiteIDKey) ?? sites.first?.id ?? ""
        if sites.contains(where: { $0.id == persistedSelectedSiteID }) {
            selectedSiteID = persistedSelectedSiteID
        } else {
            selectedSiteID = visibleSites.first?.id ?? ""
        }

        let validSiteIDs = Set(sites.map(\.id))
        pageSnapshots = pageSnapshots.filter { validSiteIDs.contains($0.key) }
        handles = handles.filter { validSiteIDs.contains($0.key) }
        collapsedChromeSiteIDs = Set(collapsedChromeSiteIDs.filter { validSiteIDs.contains($0) })
        lastScrollOffsets = lastScrollOffsets.filter { validSiteIDs.contains($0.key) }
        lastChromeToggleDates = lastChromeToggleDates.filter { validSiteIDs.contains($0.key) }
    }
}
