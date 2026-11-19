import Foundation

/// Eporner — ücretsiz, anahtarsız resmi JSON API (v2).
/// https://www.eporner.com/api/v2/video/search/
struct EpornerProvider: ContentProvider {
    let id = "eporner"
    let displayName = "Eporner"

    struct Response: Decodable { let videos: [Item] }
    struct Item: Decodable {
        let id: String
        let title: String
        let keywords: String?
        let views: LossyDouble?
        let rate: LossyDouble?
        let url: String?
        let added: String?
        let length_sec: LossyDouble?
        let embed: String?
        let default_thumb: Thumb?
    }
    struct Thumb: Decodable { let src: String }

    func search(_ q: SearchQuery) async throws -> [Video] {
        let order: String
        switch q.sort {
        case .newest: order = "latest"
        case .mostViewed: order = "most-popular"
        case .topRated: order = "top-rated"
        case .longest: order = "longest"
        case .shortest: order = "shortest"
        case .relevance: order = "most-popular"
        }
        let terms = q.terms.joined(separator: " ")
        var c = URLComponents(string: "https://www.eporner.com/api/v2/video/search/")!
        c.queryItems = [
            .init(name: "query", value: terms.isEmpty ? "all" : terms),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: "\(q.page)"),
            .init(name: "thumbsize", value: "big"),
            .init(name: "order", value: order),
            .init(name: "gay", value: "0"),
            .init(name: "lq", value: "1"),
            .init(name: "format", value: "json"),
        ]
        let r = try await HTTP.get(c.url!, as: Response.self)
        return Self.videos(from: r)
    }

    static func videos(from r: Response) -> [Video] {
        r.videos.map { v in
            Video(
                providerID: "eporner", remoteID: v.id, title: v.title,
                thumbnail: v.default_thumb.flatMap { URL(string: $0.src) },
                durationSec: Int(v.length_sec?.value ?? 0),
                views: Int(v.views?.value ?? 0),
                rating: (v.rate?.value ?? 0) * 20, // 0-5 -> 0-100
                addedAt: Fmt.sqlDate(v.added),
                tags: (v.keywords ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                embedURL: v.embed.flatMap(URL.init(string:)),
                pageURL: v.url.flatMap(URL.init(string:))
            )
        }
    }
}
