import Foundation

/// hanime.tv — resmi olmayan ama herkese açık arama + video manifest uç noktaları.
/// Doğrudan HLS akışı verdiği için yerel oynatıcıda gerçek kalite seçimi yapılabilir.
/// Not: Resmi olmayan API'dir; site değiştirirse bu dosyanın güncellenmesi gerekir.
struct HanimeProvider: ContentProvider {
    let id = "hanime"
    let displayName = "hanime.tv"
    let kinds: Set<ContentKind> = [.hentai]
    var nativeQuality: Bool { true }

    private struct Body: Encodable {
        let search_text: String
        let tags: [String]
        let tags_mode: String
        let brands: [String]
        let blacklist: [String]
        let order_by: String
        let ordering: String
        let page: Int
    }
    struct Response: Decodable { let hits: String }
    struct Hit: Decodable {
        let id: Int
        let name: String
        let slug: String
        let views: LossyDouble?
        let likes: LossyDouble?
        let dislikes: LossyDouble?
        let cover_url: String?
        let poster_url: String?
        let tags: [String]?
        let created_at: LossyDouble?
        let duration_in_ms: LossyDouble?
    }

    func search(_ q: SearchQuery) async throws -> [Video] {
        let order: (String, String)
        switch q.sort {
        case .mostViewed: order = ("views", "desc")
        case .topRated: order = ("likes", "desc")
        default: order = ("created_at_unix", "desc")
        }
        let body = Body(
            search_text: q.terms.joined(separator: " "),
            tags: [], tags_mode: "AND", brands: [],
            blacklist: SafetyFilter.hardBlockedTags,   // sunucu tarafında da hariç tut
            order_by: order.0, ordering: order.1,
            page: max(0, q.page - 1)
        )
        let r = try await HTTP.postJSON(URL(string: "https://search.htv-services.com/")!,
                                        body: body,
                                        headers: ["Origin": "https://hanime.tv"],
                                        as: Response.self)
        return try Self.videos(fromHits: r.hits)
    }

    static func videos(fromHits json: String) throws -> [Video] {
        let hits = try JSONDecoder().decode([Hit].self, from: Data(json.utf8))
        return hits.map { h in
            let likes = h.likes?.value ?? 0, dislikes = h.dislikes?.value ?? 0
            return Video(
                providerID: "hanime", remoteID: String(h.id), kind: .hentai, title: h.name,
                thumbnail: URL(string: h.cover_url ?? h.poster_url ?? ""),
                durationSec: Int((h.duration_in_ms?.value ?? 0) / 1000),
                views: Int(h.views?.value ?? 0),
                rating: likes + dislikes > 0 ? likes / (likes + dislikes) * 100 : 0,
                addedAt: h.created_at.map { Date(timeIntervalSince1970: $0.value) },
                tags: h.tags ?? [],
                pageURL: URL(string: "https://hanime.tv/videos/hentai/\(h.slug)"),
                extra: h.slug
            )
        }
    }

    private struct VideoResponse: Decodable { let videos_manifest: Manifest }
    private struct Manifest: Decodable { let servers: [Server] }
    private struct Server: Decodable { let streams: [Stream] }
    private struct Stream: Decodable { let height: LossyDouble?; let url: String? }

    func playback(for video: Video) async throws -> PlaybackSource {
        guard let slug = video.extra,
              let url = URL(string: "https://hanime.tv/api/v8/video?id=\(slug)") else { throw HTTPError.empty }
        let headers = ["Referer": "https://hanime.tv/", "Origin": "https://hanime.tv"]
        let r = try await HTTP.get(url, headers: headers, as: VideoResponse.self)
        var byHeight: [Int: StreamVariant] = [:]
        for s in r.videos_manifest.servers.flatMap(\.streams) {
            guard let str = s.url, !str.isEmpty, let u = URL(string: str) else { continue }
            let h = Int(s.height?.value ?? 0)
            if h > 0, byHeight[h] == nil { byHeight[h] = StreamVariant(height: h, url: u) }
        }
        let variants = byHeight.values.sorted { $0.height > $1.height }
        guard !variants.isEmpty else { throw HTTPError.empty }
        return .streams(variants, headers: headers)
    }
}
