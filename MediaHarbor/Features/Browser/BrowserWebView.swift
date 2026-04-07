import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserWebViewHandle {
    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        guard webView?.canGoBack == true else {
            return
        }

        webView?.goBack()
    }

    func goForward() {
        guard webView?.canGoForward == true else {
            return
        }

        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func autofill(username: String, password: String) {
        guard username.isEmpty == false || password.isEmpty == false else {
            return
        }

        let usernameJS = username.jsEscapedLiteral
        let passwordJS = password.jsEscapedLiteral
        let script = """
        (function() {
          function fill(selectors, value) {
            if (!value) return;
            const field = document.querySelector(selectors);
            if (!field) return;
            field.focus();
            field.value = value;
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          }

          fill("input[autocomplete='username'], input[name*='user' i], input[id*='user' i], input[name*='email' i], input[type='email']", \(usernameJS));
          fill("input[autocomplete='current-password'], input[type='password'], input[name*='pass' i], input[id*='pass' i]", \(passwordJS));
        })();
        """

        webView?.evaluateJavaScript(script)
    }

    func cookieHeader(for url: URL) async -> String? {
        guard let webView else {
            return nil
        }

        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        guard let host = url.host?.lowercased() else {
            return nil
        }

        let matchedCookies = cookies.filter { cookie in
            let cookieDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
        }

        guard matchedCookies.isEmpty == false else {
            return nil
        }

        return matchedCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}

struct BrowserWebView: UIViewRepresentable {
    let site: BrowserSite
    let initialURL: URL?
    let credential: BrowserCredential
    let handle: BrowserWebViewHandle
    let onSnapshotChanged: @MainActor (BrowserPageSnapshot) -> Void
    let onScrollChanged: @MainActor (CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            site: site,
            credential: credential,
            handle: handle,
            onSnapshotChanged: onSnapshotChanged,
            onScrollChanged: onScrollChanged
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "mediaHarborLocation")
        userContentController.add(context.coordinator, name: "mediaHarborResources")
        userContentController.addUserScript(WKUserScript(source: browserInstrumentationScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        handle.attach(webView)

        if let initialURL {
            webView.load(URLRequest(url: initialURL))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        handle.attach(webView)
        context.coordinator.credential = credential

        if webView.url == nil, let initialURL {
            webView.load(URLRequest(url: initialURL))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.scrollView.delegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaHarborLocation")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaHarborResources")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        let site: BrowserSite
        let handle: BrowserWebViewHandle
        let onSnapshotChanged: @MainActor (BrowserPageSnapshot) -> Void
        let onScrollChanged: @MainActor (CGFloat, Bool) -> Void

        var credential: BrowserCredential
        private var latestSnapshot = BrowserPageSnapshot.empty
        private var isUserInteracting = false

        init(
            site: BrowserSite,
            credential: BrowserCredential,
            handle: BrowserWebViewHandle,
            onSnapshotChanged: @escaping @MainActor (BrowserPageSnapshot) -> Void,
            onScrollChanged: @escaping @MainActor (CGFloat, Bool) -> Void
        ) {
            self.site = site
            self.credential = credential
            self.handle = handle
            self.onSnapshotChanged = onSnapshotChanged
            self.onScrollChanged = onScrollChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publish(webView: webView)
            handle.autofill(username: credential.trimmedUsername, password: credential.trimmedPassword)
            syncCookiesToSharedStore(webView)
            webView.evaluateJavaScript("window.__mediaHarborEmitState && window.__mediaHarborEmitState();")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publish(webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mediaHarborLocation":
                if let payload = message.body as? [String: Any] {
                    latestSnapshot.currentURLString = payload["href"] as? String ?? latestSnapshot.currentURLString
                    latestSnapshot.pageTitle = payload["title"] as? String ?? latestSnapshot.pageTitle
                    pushSnapshot()
                }
            case "mediaHarborResources":
                if let payload = message.body as? [[String: Any]] {
                    latestSnapshot.resources = payload.compactMap(BrowserWebView.makeResource)
                    pushSnapshot()
                }
            default:
                break
            }
        }

        private func publish(webView: WKWebView) {
            latestSnapshot.currentURLString = webView.url?.absoluteString ?? latestSnapshot.currentURLString
            latestSnapshot.pageTitle = webView.title ?? latestSnapshot.pageTitle
            latestSnapshot.canGoBack = webView.canGoBack
            latestSnapshot.canGoForward = webView.canGoForward
            pushSnapshot()
        }

        private func syncCookiesToSharedStore(_ webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

            cookieStore.getAllCookies { cookies in
                let sharedStore = HTTPCookieStorage.shared
                cookies.forEach { sharedStore.setCookie($0) }
            }
        }

        private func pushSnapshot() {
            latestSnapshot.canGoBack = handle.webView?.canGoBack ?? latestSnapshot.canGoBack
            latestSnapshot.canGoForward = handle.webView?.canGoForward ?? latestSnapshot.canGoForward

            Task { @MainActor in
                onSnapshotChanged(latestSnapshot)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserInteracting = true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let offsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            Task { @MainActor in
                onScrollChanged(offsetY, isUserInteracting || scrollView.isDecelerating)
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            isUserInteracting = decelerate
            let offsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            Task { @MainActor in
                onScrollChanged(offsetY, decelerate)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = false
            let offsetY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            Task { @MainActor in
                onScrollChanged(offsetY, false)
            }
        }
    }
}

private func makeBrowserInstrumentationScript() -> String {
    #"""
    (function() {
      if (window.__mediaHarborInstalled) return;
      window.__mediaHarborInstalled = true;
      window.__mediaHarborMTeamListResources = [];
      window.__mediaHarborMTeamDetailResources = [];

      function safePost(name, payload) {
        try {
          window.webkit.messageHandlers[name].postMessage(payload);
        } catch (error) {}
      }

      function absoluteURL(value) {
        try { return new URL(value, location.href).href; } catch (error) { return ""; }
      }

      function textValue(value) {
        return typeof value === "string" ? value.trim() : "";
      }

      function elementText(node) {
        if (!node) return "";
        const ownText = textValue(node.getAttribute && (node.getAttribute("title") || node.getAttribute("aria-label")));
        if (ownText) return ownText;
        return textValue(node.textContent);
      }

      function extractTorrentId(value) {
        if (!value) return "";
        const patterns = [
          /(?:^|[/?])details?\.php\?[^#]*\bid=(\d+)/i,
          /\/detail\/(\d+)/i,
          /#\/detail\?[^#]*\bid=(\d+)/i,
          /#\/torrent\/(\d+)(?:[/?#].*)?$/i,
          /#\/(\d+)(?:\?.*)?$/i,
          /(?:^|[/?])download(?:_notice)?\.php\?[^#]*\bid=(\d+)/i
        ];
        for (const pattern of patterns) {
          const match = String(value).match(pattern);
          if (match && match[1]) return match[1];
        }
        return "";
      }

      function candidateContainer(node) {
        if (!node || !node.closest) return null;
        return node.closest("tr, li, article, .ant-card, .card, .ant-list-item, .torrent, .torrent-row, .list-item, .ant-table-row");
      }

      function imageURL(node) {
        const container = candidateContainer(node) || node;
        const image = container && container.querySelector ? container.querySelector("img") : null;
        if (!image) return "";
        return absoluteURL(image.currentSrc || image.src || image.getAttribute("data-src") || "");
      }

      function resourceTitle(node) {
        const container = candidateContainer(node);
        const titleCandidates = [
          node,
          container,
          container && container.querySelector && container.querySelector("[title], .title, .name, h1, h2, h3, h4, .torrentname")
        ];

        for (const candidate of titleCandidates) {
          const title = elementText(candidate);
          if (title) return title;
        }

        return "";
      }

      function normalizeResource(input) {
        const title = textValue(input.title);
        const detailsURLString = textValue(input.detailsURLString);
        const downloadURLString = textValue(input.downloadURLString);
        const torrentID = textValue(input.torrentID);

        if (!title) return null;
        if (!detailsURLString && !downloadURLString && !torrentID) return null;

        return {
          id: textValue(input.id) || torrentID || downloadURLString || detailsURLString || title,
          title: title,
          subtitle: textValue(input.subtitle),
          detailsURLString: detailsURLString,
          downloadURLString: downloadURLString,
          imageURLString: textValue(input.imageURLString),
          torrentID: torrentID
        };
      }

      function mergeResources(resources) {
        const indexByID = new Map();
        const normalized = [];

        function score(item) {
          let total = textValue(item.title).length;
          if (textValue(item.subtitle)) total += 40;
          if (textValue(item.imageURLString)) total += 20;
          if (textValue(item.detailsURLString)) total += 10;
          if (textValue(item.downloadURLString)) total += 10;
          return total;
        }

        for (const resource of resources) {
          const item = normalizeResource(resource);
          if (!item) continue;

          const existingIndex = indexByID.get(item.id);
          if (existingIndex !== undefined) {
            if (score(item) > score(normalized[existingIndex])) {
              normalized[existingIndex] = item;
            }
            continue;
          }

          indexByID.set(item.id, normalized.length);
          normalized.push(item);
        }
        return normalized.slice(0, 200);
      }

      function currentMTeamListResources() {
        return Array.isArray(window.__mediaHarborMTeamListResources) ? window.__mediaHarborMTeamListResources : [];
      }

      function currentMTeamDetailResources() {
        return Array.isArray(window.__mediaHarborMTeamDetailResources) ? window.__mediaHarborMTeamDetailResources : [];
      }

      function buildDetailURL(torrentID) {
        if (!torrentID) return location.href;
        if (/m-team/i.test(location.hostname)) {
          return absoluteURL("#/torrent/" + torrentID);
        }
        return location.href;
      }

      function currentMTeamTitle() {
        const candidates = [
          textValue(document.title).replace(/\s*-\s*M-Team.*$/i, ""),
          elementText(document.querySelector("h1, h2, h3, .title, .name, .ant-page-header-heading-title")),
          resourceTitle(document.body)
        ];

        for (const candidate of candidates) {
          if (candidate) return candidate;
        }

        return "";
      }

      function scanDOMResources() {
        const results = [];
        const nodes = Array.from(document.querySelectorAll("a[href], [data-id], [data-torrent-id], [data-row-key], [onclick]"));

        nodes.forEach(function(node) {
          const href = absoluteURL(node.getAttribute && node.getAttribute("href") || "");
          const dataset = node.dataset || {};
          const onclick = node.getAttribute && node.getAttribute("onclick") || "";
          const explicitTorrentID = textValue(dataset.torrentId || dataset.rowKey);
          const inferredTorrentID = extractTorrentId(explicitTorrentID || onclick || href);
          const torrentID = /m-team/i.test(location.hostname) ? (inferredTorrentID || textValue(dataset.id)) : (inferredTorrentID || textValue(dataset.id));
          const isDownload = /download|download\.php|dl\.php|\/download\//i.test(href);
          const isDetail = /(?:^|[\/#])details?\.php|\/detail\/|#\/detail\?|#\/torrent\/\d+|#\/\d+/i.test(href) || !!torrentID;
          if (!isDownload && !isDetail && !torrentID) return;

          const title = resourceTitle(node);
          if (!title) return;

          results.push({
            id: torrentID || href || title,
            title: title,
            subtitle: "",
            detailsURLString: isDetail ? (href || buildDetailURL(torrentID)) : buildDetailURL(torrentID),
            downloadURLString: isDownload ? href : "",
            imageURLString: imageURL(node),
            torrentID: torrentID
          });
        });

        if (/m-team/i.test(location.hostname)) {
          const currentTorrentID = extractTorrentId(location.href);
          if (currentTorrentID) {
            const detailResources = currentMTeamDetailResources().filter(function(item) {
              return item.torrentID === currentTorrentID;
            });
            if (detailResources.length) {
              return mergeResources(detailResources);
            }
            return mergeResources([{
              id: currentTorrentID,
              title: currentMTeamTitle(),
              subtitle: "",
              detailsURLString: location.href,
              downloadURLString: "",
              imageURLString: imageURL(document.body),
              torrentID: currentTorrentID
            }]);
          }

          const networkResources = currentMTeamListResources();
          if (networkResources.length) {
            return mergeResources(networkResources);
          }
        }

        return mergeResources(results);
      }

      function collectMTeamNetworkResources(payload, requestURL) {
        const results = [];

        function looksLikeTorrentItem(value, torrentID, title, subtitle) {
          if (!torrentID || !title) return false;
          const keyText = Object.keys(value || {}).join("|");
          return Boolean(
            subtitle ||
            /small_?descr|descr|seed|leech|discount|promotion|labels?|tag|status|size|category|imdb|douban|episode|codec|media|resolution|sale/i.test(keyText)
          );
        }

        function visit(value) {
          if (!value) return;

          if (Array.isArray(value)) {
            value.forEach(visit);
            return;
          }

          if (typeof value !== "object") return;

          const torrentID = textValue(value.id || value.tid || value.torrentId);
          const title = textValue(value.name || value.title);
          const subtitle = textValue(value.smallDescr || value.small_descr || value.subtitle || value.subTitle);
          const image = textValue(value.cover || value.poster || value.image || value.pic || value.smallPic || value.small_pic);

          if (looksLikeTorrentItem(value, torrentID, title, subtitle)) {
            results.push({
              id: torrentID,
              title: title,
              subtitle: subtitle,
              detailsURLString: buildDetailURL(torrentID),
              downloadURLString: "",
              imageURLString: absoluteURL(image),
              torrentID: torrentID
            });
          }

          Object.keys(value).forEach(function(key) {
            visit(value[key]);
          });
        }

        visit(payload);
        const normalized = mergeResources(results);
        if (/\/torrent\/detail\b|\/torrent\/\d+(?:\b|[/?#])/i.test(requestURL || "")) {
          window.__mediaHarborMTeamDetailResources = normalized;
        } else if (/\/torrent\/search\b/i.test(requestURL || "")) {
          window.__mediaHarborMTeamListResources = normalized;
        } else if (/\/torrent\//i.test(requestURL || "")) {
          window.__mediaHarborMTeamListResources = normalized;
        }
        emitState();
      }

      function observeMTeamNetwork() {
        if (!/m-team/i.test(location.hostname)) return;

        const originalFetch = window.fetch;
        window.fetch = function() {
          return originalFetch.apply(this, arguments).then(function(response) {
            try {
              const requestURL = response.url || "";
              if (/\/torrent\//i.test(requestURL)) {
                response.clone().json().then(function(payload) {
                  collectMTeamNetworkResources(payload, requestURL);
                }).catch(function(){});
              }
            } catch (error) {}
            return response;
          });
        };

        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__mediaHarborURL = url;
          return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          this.addEventListener("load", function() {
            try {
              const requestURL = this.responseURL || this.__mediaHarborURL || "";
              if (/\/torrent\//i.test(requestURL)) {
                collectMTeamNetworkResources(JSON.parse(this.responseText), requestURL);
              }
            } catch (error) {}
          });
          return originalSend.apply(this, arguments);
        };
      }

      function emitState() {
        safePost("mediaHarborLocation", { href: location.href, title: document.title || "" });
        safePost("mediaHarborResources", scanDOMResources());
      }

      window.__mediaHarborEmitState = emitState;

      const originalPushState = history.pushState;
      history.pushState = function() {
        const result = originalPushState.apply(this, arguments);
        setTimeout(emitState, 120);
        return result;
      };

      const originalReplaceState = history.replaceState;
      history.replaceState = function() {
        const result = originalReplaceState.apply(this, arguments);
        setTimeout(emitState, 120);
        return result;
      };

      observeMTeamNetwork();
      window.addEventListener("load", function() { setTimeout(emitState, 200); });
      window.addEventListener("hashchange", function() { setTimeout(emitState, 120); });
      window.addEventListener("popstate", function() { setTimeout(emitState, 120); });
      document.addEventListener("readystatechange", function() { setTimeout(emitState, 200); });
      setTimeout(emitState, 400);
    })();
    """#
}

private let browserInstrumentationScript = makeBrowserInstrumentationScript()

private extension String {
    var jsEscapedLiteral: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private extension BrowserWebView {
    static func makeResource(from payload: [String: Any]) -> BrowserResource? {
        guard let id = payload["id"] as? String,
              let title = payload["title"] as? String else {
            return nil
        }

        return BrowserResource(
            id: id,
            title: title,
            subtitle: payload["subtitle"] as? String,
            detailsURLString: payload["detailsURLString"] as? String,
            downloadURLString: payload["downloadURLString"] as? String,
            imageURLString: payload["imageURLString"] as? String,
            torrentID: payload["torrentID"] as? String
        )
    }
}
