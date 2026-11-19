import Foundation

/// WordPress tabanlı bir video sitesi (Türk sitelerinin çoğu böyle).
struct WordPressSite: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// "https://www.ornek.com" (sonda / yok)
    var baseURL: String
    var language: Lang

    static let doeda = WordPressSite(id: "wp-doeda.com", name: "Doeda", baseURL: "http://www.doeda.com",
                                     language: .tr)
    static let doedaOne = WordPressSite(id: "wp-doeda.one", name: "Doeda One", baseURL: "https://www.doeda.one",
                                        language: .tr)

    /// Ayarlar'dan girilen alan adından site oluşturur ("ornek.com", "https://ornek.com/" ...).
    static func custom(name: String, address: String, language: Lang) -> WordPressSite? {
        var a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return nil }
        if !a.lowercased().hasPrefix("http") { a = "https://" + a }
        while a.hasSuffix("/") { a.removeLast() }
        guard let url = URL(string: a), let host = url.host, host.contains(".") else { return nil }
        let display = name.trimmingCharacters(in: .whitespaces)
        return WordPressSite(id: "wp-\(host.lowercased())", name: display.isEmpty ? host : display,
                             baseURL: a, language: language)
    }
}

/// WordPress'in standart JSON API'si (/wp-json/wp/v2/posts) üzerinden arama yapar.
/// Oynatma için yazı sayfasındaki gömülü oynatıcıyı bulur; doğrudan akış çıkarabiliyorsa
/// yerel oynatıcıda, çıkaramıyorsa sadece oynatıcı çerçevesini kilitli WebView'da açar.
struct WordPressProvider: ContentProvider {
    let site: WordPressSite
    var id: String { site.id }
    var displayName: String { site.name }
    var language: Lang { site.language }

    // MARK: Arama

    struct Post: Decodable {
        let id: Int
        let date_gmt: String?
        let link: String
        let title: String
        let views: Int
        let classList: [String]
        let thumbnail: String?

        private enum Keys: String, CodingKey { case id, date_gmt, link, title, views, class_list, _embedded }
        private struct Rendered: Decodable { let rendered: String }
        private struct Embedded: Decodable {
            let media: [Media]?
            private enum K: String, CodingKey { case media = "wp:featuredmedia" }
            init(from d: Decoder) throws {
                media = try? d.container(keyedBy: K.self).decode([Media].self, forKey: .media)
            }
        }
        private struct Media: Decodable {
            let source_url: String?
            let sizes: [String: Size]
            private enum K: String, CodingKey { case source_url, media_details }
            private struct Details: Decodable { let sizes: [String: Size]? }
            struct Size: Decodable { let source_url: String? }
            init(from d: Decoder) throws {
                let c = try? d.container(keyedBy: K.self)
                source_url = try? c?.decode(String.self, forKey: .source_url)
                sizes = (try? c?.decode(Details.self, forKey: .media_details))?.sizes ?? [:]
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(Int.self, forKey: .id)
            link = try c.decode(String.self, forKey: .link)
            title = ((try? c.decode(Rendered.self, forKey: .title))?.rendered ?? "").strippingTags
                .trimmingCharacters(in: .whitespacesAndNewlines)
            date_gmt = try? c.decode(String.self, forKey: .date_gmt)
            views = Int((try? c.decode(LossyDouble.self, forKey: .views))?.value ?? 0)
            classList = (try? c.decode([String].self, forKey: .class_list)) ?? []
            let media = (try? c.decode(Embedded.self, forKey: ._embedded))?.media?.first
            // Doeda gibi sitelerde tam boy görsel zaten küçük (≈900px); "medium" ise fazla küçük.
            thumbnail = media?.sizes["medium_large"]?.source_url ?? media?.sizes["large"]?.source_url
                ?? media?.source_url ?? media?.sizes["medium"]?.source_url
        }
    }

    func searchURL(_ q: SearchQuery) -> URL? {
        let terms = q.terms.joined(separator: " ")
        guard var c = URLComponents(string: site.baseURL + "/wp-json/wp/v2/posts") else { return nil }
        c.queryItems = [
            .init(name: "per_page", value: "20"),
            .init(name: "page", value: "\(q.page)"),
            .init(name: "_embed", value: "wp:featuredmedia"),
            .init(name: "_fields", value: "id,date_gmt,link,title,views,class_list,_links,_embedded"),
        ]
        if !terms.isEmpty {
            c.queryItems?.append(.init(name: "search", value: terms))
            c.queryItems?.append(.init(name: "orderby", value: q.sort == .newest ? "date" : "relevance"))
        }
        return c.url
    }

    func search(_ q: SearchQuery) async throws -> [Video] {
        guard let url = searchURL(q) else { return [] }
        do {
            let data = try await HTTP.data(url)
            return try Self.videos(from: data, site: site)
        } catch HTTPError.status(400, _) {
            return []   // WordPress son sayfadan sonrasında 400 döndürür
        }
    }

    static func videos(from data: Data, site: WordPressSite) throws -> [Video] {
        let posts = try JSONDecoder().decode([Post].self, from: data)
        return posts.compactMap { p in
            guard !p.title.isEmpty, let page = URL(string: p.link) else { return nil }
            // class_list: ["post-1", "category-amator", "category-masaj-1", ...] -> etiketler
            let tags = p.classList.compactMap { cls -> String? in
                guard cls.hasPrefix("category-") || cls.hasPrefix("tag-") else { return nil }
                var t = String(cls.drop(while: { $0 != "-" }).dropFirst())
                if let m = Rx.first(#"^(.*?)-(\d+|x|p)$"#, in: t) { t = m[1] }
                return t.replacingOccurrences(of: "-", with: " ")
            }
            return Video(
                providerID: site.id, remoteID: String(p.id), title: p.title,
                thumbnail: p.thumbnail.flatMap(URL.init(string:)),
                views: p.views,
                addedAt: Fmt.isoDate(p.date_gmt),
                tags: tags,
                pageURL: page
            )
        }
    }

    // MARK: Oynatma

    /// Yazı sayfasının HTML'inden çıkarılan oynatıcı bilgisi.
    enum PagePlayer: Equatable {
        case direct(URL)                       // sayfada doğrudan .m3u8/.mp4
        case jetPlayer(base: URL, vid: String, frame: URL)   // …/player/play.php?vid=HASH
        case iframe(URL)
    }

    private static let ignoredFrameHosts = AdHosts.all + ["facebook.com", "twitter.com", "google.com", "googletagmanager.com", "youtube.com", "histats.com", "yandex.ru"]

    static func findPlayer(html: String, pageURL: URL) -> PagePlayer? {
        // 1) <video>/<source> ya da JSON-LD içinde doğrudan dosya
        let direct = Rx.first(#"<(?:video|source)[^>]*\bsrc="(https?:[^"]+\.(?:m3u8|mp4)[^"]*)""#, in: html)?[1]
            ?? Rx.first(#""contentUrl"\s*:\s*"(https?:[^"]+\.(?:m3u8|mp4)[^"]*)""#, in: html)?[1]
        if let direct, let u = URL(string: direct.htmlDecoded.replacingOccurrences(of: "\\/", with: "/")) {
            return .direct(u)
        }
        // 2) Oynatıcı çerçeveleri
        for m in Rx.all(#"<iframe[^>]*\b(?:data-lazy-src|data-src|src)="([^"]+)""#, in: html) {
            var raw = m[1].htmlDecoded
            if raw.hasPrefix("//") { raw = "https:" + raw }
            guard raw.lowercased().hasPrefix("http") || raw.hasPrefix("/"),
                  let u = URL(string: raw, relativeTo: pageURL)?.absoluteURL, let host = u.host?.lowercased(),
                  !ignoredFrameHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
            if let vid = Rx.first(#"/play\.php\?(?:.*&)?vid=([0-9a-z]+)"#, in: u.absoluteString)?[1] {
                return .jetPlayer(base: directory(of: u), vid: vid, frame: u)
            }
            return .iframe(u)
        }
        return nil
    }

    /// "https://h/player/play.php?vid=x" -> "https://h/player/"
    static func directory(of url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        c.query = nil
        c.fragment = nil
        if let slash = c.path.lastIndex(of: "/") { c.path = String(c.path[...slash]) } else { c.path = "/" }
        return c.url ?? url
    }

    /// "Jet Player" (doeda vb.) kaynak yanıtı: {"status":…, "source":[{"file":…, "label":"720p"}], "iframe":…, "alternative":…}
    struct JetSources: Equatable {
        var variants: [StreamVariant] = []
        var iframe: URL?
        var failed = false
        var alternative: String?
    }

    static func parseJetSources(_ data: Data) -> JetSources {
        var out = JetSources()
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            out.failed = true
            return out
        }
        if let s = obj["status"] { out.failed = "\(s)" == "false" || "\(s)" == "0" }
        out.alternative = obj["alternative"] as? String
        if let f = obj["iframe"] as? String, !f.isEmpty { out.iframe = URL(string: f.hasPrefix("//") ? "https:" + f : f) }
        var files: [(String, String)] = []
        if let list = obj["source"] as? [[String: Any]] {
            for s in list {
                if let file = s["file"] as? String { files.append((file, "\(s["label"] ?? "")")) }
            }
        } else if let file = obj["source"] as? String {
            files.append((file, ""))
        }
        var seen = Set<Int>()
        for (file, label) in files {
            guard let u = URL(string: file.hasPrefix("//") ? "https:" + file : file), u.scheme != nil else { continue }
            let height = Int(Rx.first(#"(\d{3,4})"#, in: label)?[1] ?? "") ?? 0
            if seen.insert(height).inserted { out.variants.append(StreamVariant(height: height, url: u)) }
        }
        out.variants.sort { $0.height > $1.height }
        return out
    }

    func playback(for video: Video) async throws -> PlaybackSource {
        guard let page = video.pageURL else { throw HTTPError.empty }
        let html = try await HTTP.text(page)
        guard let player = Self.findPlayer(html: html, pageURL: page) else { throw HTTPError.empty }

        switch player {
        case .direct(let url):
            return .streams(await Self.expand([StreamVariant(height: 0, url: url)], headers: [:]), headers: [:])

        case .iframe(let url):
            return .embed(url, referer: page)

        case .jetPlayer(let base, let vid, let frame):
            let headers = ["Referer": frame.absoluteString,
                           "Origin": "\(frame.scheme ?? "https")://\(frame.host ?? "")",
                           "X-Requested-With": "XMLHttpRequest"]
            var alternative = "ankacdn"
            for order in 0..<4 {
                guard let data = try? await HTTP.postForm(URL(string: "ajax_sources.php", relativeTo: base)?.absoluteURL ?? base,
                                                          fields: [("vid", vid), ("alternative", alternative), ("ord", "\(order)")],
                                                          headers: headers) else { break }
                let s = Self.parseJetSources(data)
                if let inner = s.iframe { return .embed(inner, referer: frame) }
                if !s.variants.isEmpty {
                    let media = ["Referer": frame.absoluteString]
                    return .streams(await Self.expand(s.variants, headers: media), headers: media)
                }
                guard s.failed, let next = s.alternative else { break }
                alternative = next
            }
            // Kaynak çıkarılamadıysa oynatıcı çerçevesini (siteyi değil) kilitli WebView'da aç.
            return .embed(frame, referer: page)
        }
    }

    /// Tek bir HLS ana listesi geldiyse kalite seçeneklerine aç.
    private static func expand(_ variants: [StreamVariant], headers: [String: String]) async -> [StreamVariant] {
        guard variants.count == 1, let only = variants.first, only.url.pathExtension.lowercased() == "m3u8" else { return variants }
        return await HLS.variants(master: only.url, headers: headers)
    }
}
