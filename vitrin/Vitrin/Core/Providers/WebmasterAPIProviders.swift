import Foundation

/// Pornhub ve RedTube aynı "webmaster" API biçimini kullanır (anahtarsız, ücretsiz).
enum WebmasterAPI {
    struct Response: Decodable {
        let videos: [Entry]?
    }

    /// Pornhub videoyu doğrudan, RedTube ise {"video": {...}} içinde döndürür.
    struct Entry: Decodable {
        let item: Item
        init(from decoder: Decoder) throws {
            struct Wrapped: Decodable { let video: Item }
            if let w = try? Wrapped(from: decoder) { item = w.video } else { item = try Item(from: decoder) }
        }
    }

    struct Item: Decodable {
        let video_id: String
        let title: String
        let duration: String?
        let views: LossyDouble?
        let rating: LossyDouble?
        let url: String?
        let embed_url: String?
        let publish_date: String?
        let default_thumb: String?
        let thumb: String?
        let tags: [Tag]?
        struct Tag: Decodable { let tag_name: String }

        func toVideo(provider: String, embed: URL?) -> Video {
            Video(
                providerID: provider, remoteID: video_id, title: title,
                thumbnail: URL(string: default_thumb ?? thumb ?? ""),
                durationSec: Fmt.seconds(fromClock: duration),
                views: Int(views?.value ?? 0),
                rating: rating?.value ?? 0,
                addedAt: Fmt.sqlDate(publish_date),
                tags: tags?.map(\.tag_name) ?? [],
                embedURL: embed_url.flatMap(URL.init(string:)) ?? embed,
                pageURL: url.flatMap(URL.init(string:))
            )
        }
    }

    static func ordering(_ s: SortOption) -> String {
        switch s {
        case .newest: return "newest"
        case .topRated: return "rating"
        default: return "mostviewed"   // uzun/kısa istemci tarafında sıralanır
        }
    }

    static func videos(from data: Data, provider: String, embed: (String) -> URL?) throws -> [Video] {
        let r = try JSONDecoder().decode(Response.self, from: data)
        return (r.videos ?? []).map { $0.item.toVideo(provider: provider, embed: embed($0.item.video_id)) }
    }
}

struct PornhubProvider: ContentProvider {
    let id = "pornhub"
    let displayName = "Pornhub"

    func search(_ q: SearchQuery) async throws -> [Video] {
        var c = URLComponents(string: "https://www.pornhub.com/webmasters/search")!
        c.queryItems = [
            .init(name: "search", value: q.terms.joined(separator: " ")),
            .init(name: "ordering", value: WebmasterAPI.ordering(q.sort)),
            .init(name: "page", value: "\(q.page)"),
            .init(name: "thumbsize", value: "large_hd"),
        ]
        let data = try await HTTP.data(c.url!)
        return try WebmasterAPI.videos(from: data, provider: id) {
            URL(string: "https://www.pornhub.com/embed/\($0)")
        }
    }
}

struct RedTubeProvider: ContentProvider {
    let id = "redtube"
    let displayName = "RedTube"

    func search(_ q: SearchQuery) async throws -> [Video] {
        var c = URLComponents(string: "https://api.redtube.com/")!
        c.queryItems = [
            .init(name: "data", value: "redtube.Videos.searchVideos"),
            .init(name: "output", value: "json"),
            .init(name: "search", value: q.terms.joined(separator: " ")),
            .init(name: "ordering", value: WebmasterAPI.ordering(q.sort)),
            .init(name: "page", value: "\(q.page)"),
            .init(name: "thumbsize", value: "big"),
        ]
        let data = try await HTTP.data(c.url!)
        return try WebmasterAPI.videos(from: data, provider: id) {
            URL(string: "https://embed.redtube.com/?id=\($0)")
        }
    }
}
