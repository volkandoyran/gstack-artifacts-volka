import Foundation

/// XVideos ve XNXX aynı altyapıyı kullanır. Herkese açık API'leri yok; arama sayfasının
/// HTML'i ayrıştırılır. Video sayfası doğrudan HLS adresi verdiği için video uygulamanın
/// kendi oynatıcısında, gerçek kalite seçimiyle oynatılır (site hiç açılmaz).
struct XVideosProvider: ContentProvider {
    struct Site: Sendable {
        let id: String
        let name: String
        let host: String
        /// (terimler, sayfa[1..], sıralama) -> arama adresi; nil = bu sorgu desteklenmiyor
        let searchURL: @Sendable (_ terms: String, _ page: Int, _ sort: SortOption) -> URL?

        static let xvideos = Site(id: "xvideos", name: "XVideos", host: "www.xvideos.com") { terms, page, sort in
            if terms.isEmpty {
                return URL(string: page <= 1 ? "https://www.xvideos.com/" : "https://www.xvideos.com/new/\(page - 1)")
            }
            var c = URLComponents(string: "https://www.xvideos.com/")!
            c.queryItems = [.init(name: "k", value: terms), .init(name: "p", value: "\(page - 1)")]
            switch sort {
            case .newest: c.queryItems?.append(.init(name: "sort", value: "uploaddate"))
            case .topRated: c.queryItems?.append(.init(name: "sort", value: "rating"))
            case .longest: c.queryItems?.append(.init(name: "sort", value: "length"))
            case .mostViewed: c.queryItems?.append(.init(name: "sort", value: "views"))
            case .relevance, .shortest: break
            }
            return c.url
        }

        static let xnxx = Site(id: "xnxx", name: "XNXX", host: "www.xnxx.com") { terms, page, _ in
            guard !terms.isEmpty else { return nil }
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-_")
            let q = terms.replacingOccurrences(of: " ", with: "+")
                .addingPercentEncoding(withAllowedCharacters: allowed.union(CharacterSet(charactersIn: "+"))) ?? terms
            return URL(string: "https://www.xnxx.com/search/\(q)" + (page > 1 ? "/\(page - 1)" : ""))
        }
    }

    let site: Site
    var id: String { site.id }
    var displayName: String { site.name }
    var nativeQuality: Bool { true }

    func search(_ q: SearchQuery) async throws -> [Video] {
        guard let url = site.searchURL(q.terms.joined(separator: " "), q.page, q.sort) else { return [] }
        let html = try await HTTP.text(url)
        return Self.parseSearch(html: html, site: site)
    }

    // MARK: Arama sayfası

    static func parseSearch(html: String, site: Site) -> [Video] {
        let starts = Rx.ranges(#"<div[^>]*\bid="video_[^"]*"[^>]*>"#, in: html)
        var out: [Video] = []
        for (i, r) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].lowerBound : (html.index(r.lowerBound, offsetBy: 6000, limitedBy: html.endIndex) ?? html.endIndex)
            let openTag = String(html[r])
            let block = String(html[r.lowerBound..<end])

            let eid = Rx.first(#"data-eid="([0-9a-z]+)""#, in: openTag)?[1]
            guard let numericID = Rx.first(#"data-id="(\d+)""#, in: openTag)?[1],
                  let href = Rx.first(#"href="([^"]*/video[.\-][^"]+)""#, in: block)?[1],
                  let page = URL(string: href.htmlDecoded, relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL
            else { continue }

            let title = (Rx.first(#"<a[^>]*\btitle="([^"]+)""#, in: block)?[1] ?? "").htmlDecoded
            guard !title.isEmpty else { continue }

            // Küçük resim: tembel yüklemede data-src, yoksa src
            var thumb = Rx.first(#"<img[^>]*\bdata-src="(https?://[^"]+)""#, in: block)?[1]
            if thumb == nil, let src = Rx.first(#"<img[^>]*\bsrc="(https?://[^"]+)""#, in: block)?[1], !src.contains("blank") {
                thumb = src
            }

            let meta = (Rx.first(#"<p class="metadata">(.*?)</p>"#, in: block)?[1] ?? "").strippingTags
            var duration = Fmt.seconds(fromLoose: Rx.first(#"class="duration">([^<]+)<"#, in: block)?[1] ?? "")
            if duration == 0 { duration = Fmt.seconds(fromLoose: meta) }

            let viewsText = Rx.first(#"([\d.,]+\s*[kKmM]?)\s*Views"#, in: meta)?[1]      // XVideos: "7M Views"
                ?? Rx.first(#"^\s*([\d.,]+[kKmM]?)\s"#, in: meta)?[1]                       // XNXX: "876.1k 100% 6min"
            let rating = Double(Rx.first(#"(\d{1,3})\s*%"#, in: meta)?[1] ?? "") ?? 0
            let height = Int(Rx.first(#">\s*(\d{3,4})p\s*<"#, in: block)?[1] ?? "")

            out.append(Video(
                providerID: site.id, remoteID: numericID, title: title,
                thumbnail: thumb.flatMap { URL(string: $0.htmlDecoded) },
                durationSec: duration,
                views: viewsText.map(Fmt.count(fromCompact:)) ?? 0,
                rating: rating,
                embedURL: URL(string: "https://\(site.host)/embedframe/\(eid ?? numericID)"),
                pageURL: page,
                maxHeight: height
            ))
        }
        return out
    }

    // MARK: Oynatma

    struct PageStreams: Equatable {
        var hls: URL?
        var high: URL?   // 360p mp4
        var low: URL?    // 240p mp4
    }

    static func parseStreams(html: String) -> PageStreams {
        func url(_ name: String) -> URL? {
            Rx.first("html5player\\.\(name)\\('([^']+)'\\)", in: html).flatMap { URL(string: $0[1]) }
        }
        return PageStreams(hls: url("setVideoHLS"), high: url("setVideoUrlHigh"), low: url("setVideoUrlLow"))
    }

    func playback(for video: Video) async throws -> PlaybackSource {
        guard let page = video.pageURL else { throw HTTPError.empty }
        let headers = ["Referer": "https://\(site.host)/"]
        if let html = try? await HTTP.text(page) {
            let s = Self.parseStreams(html: html)
            if let hls = s.hls {
                return .streams(await HLS.variants(master: hls, headers: headers), headers: headers)
            }
            var mp4: [StreamVariant] = []
            if let u = s.high { mp4.append(StreamVariant(height: 360, url: u)) }
            if let u = s.low { mp4.append(StreamVariant(height: 240, url: u)) }
            if !mp4.isEmpty { return .streams(mp4, headers: headers) }
        }
        // Akış bulunamazsa sitenin gömülü oynatıcısına düş (kilitli WebView).
        guard let embed = video.embedURL else { throw HTTPError.empty }
        return .embed(embed, referer: nil)
    }
}
