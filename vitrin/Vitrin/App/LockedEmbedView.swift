import SwiftUI
import WebKit

/// Yalnızca gömülü oynatıcı çerçevesini gösteren, siteye gitmeyi engelleyen WebView.
///
/// Sitenin kendisi hiç yüklenmez: oynatıcı, uygulamanın ürettiği boş bir sayfanın içindeki
/// tek bir <iframe> olarak açılır. Sayfanın "adresi" olarak videonun site sayfası verilir ki
/// oynatıcı kendini kendi sitesinde gömülü sansın (Referer/başlangıç kontrolü) — ama o adrese
/// hiçbir istek yapılmaz.
/// - Ana çerçeve asla başka yere gidemez (logo/başlık tıklamaları iptal).
/// - Yeni pencere / pop-up / window.open tamamen kapalı.
/// - Bilinen reklam ağları içerik kuralıyla bloklanır.
/// - Çerez/oturum saklanmaz (kalıcı olmayan veri deposu).
struct LockedEmbedView: UIViewRepresentable {
    let url: URL
    var referer: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.addUserScript(WKUserScript(
            source: "window.open = function(){ return null; };",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.customUserAgent = HTTP.userAgent

        let src = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="\(src)" allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
        allowfullscreen referrerpolicy="unsafe-url"></iframe></body></html>
        """
        // Referer yoksa oynatıcının kendi alan adının kökü kullanılır.
        let base = referer ?? URL(string: "\(url.scheme ?? "https")://\(url.host ?? "localhost")/")

        AdBlock.apply(to: cfg.userContentController) {
            web.loadHTMLString(html, baseURL: base)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        // Oynatıcı çerçevesini kaldır ki ses arkada devam etmesin.
        uiView.evaluateJavaScript("document.body.innerHTML = ''", completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var initialLoadDone = false

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let frame = action.targetFrame else {
                decisionHandler(.cancel); return            // yeni pencere girişimi
            }
            if frame.isMainFrame {
                // Ana çerçeve yalnızca uygulamanın ürettiği sarmalayıcı sayfayı yükler; sonrası yasak.
                if initialLoadDone {
                    decisionHandler(.cancel)
                } else {
                    initialLoadDone = true
                    decisionHandler(.allow)
                }
                return
            }
            // Oynatıcının iç çerçeveleri: kullanıcı tıklamasıyla başka sayfaya gitmek yasak.
            decisionHandler(action.navigationType == .linkActivated ? .cancel : .allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}

/// WebKit içerik kuralları ile basit reklam/pop-under engelleyici.
enum AdBlock {
    private static var cached: WKContentRuleList?

    static func apply(to controller: WKUserContentController, then done: @escaping () -> Void) {
        if let cached { controller.add(cached); done(); return }
        let rules = AdHosts.all.map { d -> [String: Any] in
            let escaped = d.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^https?://([^/]+\\.)?\(escaped)"], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { done(); return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "vitrin-adblock-v2", encodedContentRuleList: json
        ) { list, _ in
            DispatchQueue.main.async {
                if let list { cached = list; controller.add(list) }
                done()
            }
        }
    }
}
