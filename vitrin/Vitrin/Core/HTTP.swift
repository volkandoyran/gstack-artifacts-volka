import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HTTPError: LocalizedError {
    case status(Int, host: String)
    case empty
    var errorDescription: String? {
        switch self {
        case let .status(code, host):
            if code == 403 || code == 451 {
                return "\(host) erişimi engelledi (HTTP \(code)). VPN/DNS açık mı?"
            }
            return "\(host) hata döndürdü (HTTP \(code))."
        case .empty: return "Oynatılabilir kaynak bulunamadı."
        }
    }
}

/// Tüm ağ trafiği buradan geçer.
///
/// ÖNEMLİ: Bilerek `URLSessionConfiguration.default` kullanılıyor ve kendi DNS'imiz
/// (DoH vb.) ya da proxy'miz YOK. Böylece iOS'ta ayarladığın DNS profili (1.1.1.1,
/// NextDNS, AdGuard…) ve aktif VPN tüneli olduğu gibi kullanılır; uygulama bunları
/// ne engeller ne de atlar. Bir site ülkende engelliyse ama VPN/DNS ile açılıyorsa,
/// uygulama da aynı şekilde açar.
enum HTTP {
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9,tr;q=0.8",
        ]
        return URLSession(configuration: c)
    }()

    static func data(_ request: URLRequest) async throws -> Data {
        // dataTask + continuation: hem iOS'ta hem (testler için) Linux'ta çalışır.
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: request) { data, response, error in
                if let error { cont.resume(throwing: error) }
                else if let data, let response { cont.resume(returning: (data, response)) }
                else { cont.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, host: request.url?.host ?? "?")
        }
        return data
    }

    private static func request(_ url: URL, headers: [String: String]) -> URLRequest {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    static func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        try await data(request(url, headers: headers))
    }

    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], as: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(request(url, headers: headers)))
    }

    /// Sayfa HTML'i ya da düz metin (m3u8 vb.).
    static func text(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        let d = try await data(request(url, headers: headers))
        return String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
    }

    static func postJSON<B: Encodable>(_ url: URL, body: B, headers: [String: String] = [:]) async throws -> Data {
        var req = request(url, headers: headers)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await data(req)
    }

    static func postJSON<B: Encodable, T: Decodable>(_ url: URL, body: B, headers: [String: String] = [:], as: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await postJSON(url, body: body, headers: headers))
    }

    /// application/x-www-form-urlencoded POST
    static func postForm(_ url: URL, fields: [(String, String)], headers: [String: String] = [:]) async throws -> Data {
        var req = request(url, headers: headers)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = Data(fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").utf8)
        return try await data(req)
    }

    /// Kullanıcıya gösterilecek Türkçe hata metni.
    static func describe(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Alan adı çözülemedi — site DNS ile engelli olabilir. DNS/VPN'ini kontrol et."
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .secureConnectionFailed:
                return "Bağlantı kurulamadı — site engelli olabilir. VPN açıkken tekrar dene."
            case .notConnectedToInternet:
                return "İnternet bağlantısı yok."
            default:
                return e.localizedDescription
            }
        }
        if error is DecodingError { return "Site yanıt biçimini değiştirmiş; kaynak güncellenmeli." }
        return error.localizedDescription
    }
}
