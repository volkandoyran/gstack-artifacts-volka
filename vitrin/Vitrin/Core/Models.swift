import Foundation

// MARK: - Dil

/// Bir kaynağın arama dili. Türk sitelerine Türkçe, diğerlerine İngilizce terim gönderilir.
enum Lang: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case en, tr
    var id: String { rawValue }
    var title: String { self == .tr ? "Türkçe" : "İngilizce" }
}

// MARK: - Sıralama / birleştirme / kalite

enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case relevance, newest, mostViewed, topRated, longest, shortest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance: return "İlgili"
        case .newest: return "En yeni"
        case .mostViewed: return "En çok izlenen"
        case .topRated: return "En yüksek puan"
        case .longest: return "En uzun"
        case .shortest: return "En kısa"
        }
    }
    var systemImage: String {
        switch self {
        case .relevance: return "sparkle.magnifyingglass"
        case .newest: return "clock"
        case .mostViewed: return "eye"
        case .topRated: return "star"
        case .longest: return "arrow.up.right"
        case .shortest: return "arrow.down.right"
        }
    }
}

/// Birden çok kategori seçildiğinde nasıl aranacağı.
enum CombineMode: String, CaseIterable, Identifiable, Sendable {
    case all   // Hepsi birlikte (VE): tek arama, tüm etiketler
    case any   // Herhangi biri (VEYA): her etiket ayrı aranır, sonuçlar birleştirilir
    var id: String { rawValue }
    var title: String { self == .all ? "Hepsi birlikte (VE)" : "Herhangi biri (VEYA)" }
}

enum QualityPreference: Int, CaseIterable, Identifiable, Sendable {
    case auto = 0, p2160 = 2160, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360
    var id: Int { rawValue }
    var title: String { self == .auto ? "Otomatik" : "\(rawValue)p" }
}

// MARK: - Video

struct Video: Identifiable, Hashable, Sendable, Codable {
    let providerID: String
    let remoteID: String
    var id: String { "\(providerID):\(remoteID)" }
    let title: String
    let thumbnail: URL?
    /// 0 = bilinmiyor
    let durationSec: Int
    let views: Int
    /// 0...100 (0 = bilinmiyor)
    let rating: Double
    let addedAt: Date?
    let tags: [String]
    /// Sitenin gömülü oynatıcı adresi (varsa)
    let embedURL: URL?
    /// Videonun sitedeki sayfası. Hiçbir zaman kullanıcıya açılmaz; sadece akış adresini
    /// çıkarmak ve gömülü oynatıcıya "Referer" olarak vermek için kullanılır.
    let pageURL: URL?
    /// Listede görünen en yüksek çözünürlük (örn. 1080), bilinmiyorsa nil
    let maxHeight: Int?
    /// Sağlayıcıya özel ek bilgi (gerekirse)
    let extra: String?

    init(providerID: String, remoteID: String, title: String,
         thumbnail: URL? = nil, durationSec: Int = 0, views: Int = 0, rating: Double = 0,
         addedAt: Date? = nil, tags: [String] = [], embedURL: URL? = nil, pageURL: URL? = nil,
         maxHeight: Int? = nil, extra: String? = nil) {
        self.providerID = providerID
        self.remoteID = remoteID
        self.title = title
        self.thumbnail = thumbnail
        self.durationSec = durationSec
        self.views = views
        self.rating = rating
        self.addedAt = addedAt
        self.tags = tags
        self.embedURL = embedURL
        self.pageURL = pageURL
        self.maxHeight = maxHeight
        self.extra = extra
    }
}

struct StreamVariant: Hashable, Identifiable, Sendable {
    /// 0 = uyarlanabilir (HLS ana listesi, "Otomatik")
    let height: Int
    let url: URL
    var id: String { "\(height)|\(url.absoluteString)" }
    var label: String { height == 0 ? "Otomatik" : "\(height)p" }
}

enum PlaybackSource: Sendable {
    /// Doğrudan akış (HLS/MP4) — yerel oynatıcıda, kalite seçimiyle oynatılır.
    case streams([StreamVariant], headers: [String: String])
    /// Sadece gömülü oynatıcı — kilitli WebView içinde, siteye gitmeden oynatılır.
    case embed(URL, referer: URL?)
}

struct SearchQuery: Sendable {
    /// Sağlayıcının diline göre hazırlanmış arama terimleri
    var terms: [String]
    var sort: SortOption
    var page: Int   // 1'den başlar
}

// MARK: - Yardımcılar

/// Sayı ya da string olarak gelen sayısal alanları tolere eder ("4.5", 4.5, "1,234").
struct LossyDouble: Decodable, Hashable, Sendable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = Double(s.replacingOccurrences(of: ",", with: "")) ?? 0
        } else {
            value = 0
        }
    }
}

enum Fmt {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    /// "2026-11-13 22:22:15"
    static func sqlDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return formatter("yyyy-MM-dd HH:mm:ss").date(from: s)
    }

    /// "2026-11-14T10:10:22" (WordPress date_gmt)
    static func isoDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return formatter("yyyy-MM-dd'T'HH:mm:ss").date(from: String(s.prefix(19)))
    }

    /// "12:34" veya "1:02:03" -> saniye
    static func seconds(fromClock s: String?) -> Int {
        guard let s else { return 0 }
        return s.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    /// "12 min", "1 h 5 min", "6min", "1h 12min", "45 sec" -> saniye
    static func seconds(fromLoose s: String) -> Int {
        var total = 0
        for m in Rx.all(#"(\d+)\s*(h|min|sec)"#, in: s.lowercased()) {
            let n = Int(m[1]) ?? 0
            switch m[2] {
            case "h": total += n * 3600
            case "min": total += n * 60
            default: total += n
            }
        }
        return total
    }

    /// "7M", "876.1k", "1,234", "18.5K" -> sayı
    static func count(fromCompact s: String) -> Int {
        guard let m = Rx.first(#"([\d.,]+)\s*([kKmMbB])?"#, in: s) else { return 0 }
        let suffix = m[2].lowercased()
        var num = m[1]
        if suffix.isEmpty { num = num.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "") }
        else { num = num.replacingOccurrences(of: ",", with: ".") }
        let v = Double(num) ?? 0
        switch suffix {
        case "k": return Int(v * 1_000)
        case "m": return Int(v * 1_000_000)
        case "b": return Int(v * 1_000_000_000)
        default: return Int(v)
        }
    }

    static func clock(_ sec: Int) -> String {
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fB", Double(n) / 1_000)   // B = bin
        default: return "\(n)"
        }
    }
}
