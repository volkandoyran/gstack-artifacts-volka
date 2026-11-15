import Foundation

/// Yinelenen video filtresinin sıkılığı.
enum DedupeLevel: Int, CaseIterable, Identifiable, Sendable {
    case off = 0, normal = 1, strict = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .normal: return "Normal"
        case .strict: return "Sıkı"
        }
    }
    var detail: String {
        switch self {
        case .off: return "Aynı video farklı sitelerden tekrar tekrar görünebilir."
        case .normal: return "Başlığı neredeyse aynı ve süresi tutan videolar tek kart olur."
        case .strict: return "Başlığı kısmen benzeyen ve süresi tutan videolar da birleştirilir (nadiren farklı videoları da birleştirebilir)."
        }
    }
}

/// Bir videonun karşılaştırma imzası: sadeleştirilmiş başlık kelimeleri + süre.
struct VideoSignature: Hashable, Sendable {
    let tokens: Set<String>
    /// Sıralı kelimeler; "aynı başlık" karşılaştırması için
    let key: String
    let duration: Int

    /// Başlıklarda bilgi taşımayan kelimeler
    static let noise: Set<String> = [
        "hd", "fhd", "uhd", "4k", "2k", "1080p", "720p", "480p", "360p", "60fps", "full", "video", "videos", "clip",
        "porn", "porno", "porna", "sex", "seks", "sikis", "xxx", "izle", "seyret", "film", "filmi", "free", "new",
        "the", "a", "an", "and", "of", "in", "on", "with", "to", "for", "her", "his", "by", "at", "is",
        "ve", "ile", "bir", "bu", "icin", "com", "www",
    ]

    init(title: String, duration: Int) {
        let words = title.asciiFolded.wordTokens.filter { w in
            !Self.noise.contains(w) && (w.count > 1 || w.first?.isNumber == true)
        }
        tokens = Set(words)
        key = tokens.sorted().joined(separator: " ")
        self.duration = max(0, duration)
    }

    init(_ v: Video) { self.init(title: v.title, duration: v.durationSec) }

    /// İzleme geçmişinde saklanan kısa anahtar (süre 5 sn'lik dilimlere yuvarlanır).
    var historyKey: String { "\(key)|\(duration > 0 ? (duration + 2) / 5 : 0)" }
}

/// Aynı videonun (aynı siteden ya da farklı sitelerden) birden fazla kez listelenmesini engeller.
///
/// Kural (özet):
/// - Başlık kelimeleri birebir aynıysa ve süreler tutuyorsa (ya da biri bilinmiyorsa) → aynı video.
/// - Başlıklar büyük ölçüde örtüşüyor ve süreler birkaç saniye içinde aynıysa → aynı video.
/// Gizlenen kopyalar atılmaz; tutulan videonun "diğer kaynakları" olarak saklanır.
struct DuplicateFilter {
    var level: DedupeLevel

    private struct Entry {
        var video: Video
        var sig: VideoSignature
    }

    private var kept: [Entry] = []
    private var byKey: [String: [Int]] = [:]
    private var byDuration: [Int: [Int]] = [:]
    private(set) var hiddenCount = 0
    /// Tutulan video kimliği -> aynı videonun diğer sitelerdeki kopyaları
    private(set) var alternates: [String: [Video]] = [:]

    init(level: DedupeLevel = .normal) { self.level = level }

    // MARK: Karşılaştırma

    private func tolerance(_ a: Int, _ b: Int) -> Int {
        let longer = Double(max(a, b))
        return level == .strict ? max(5, Int(longer * 0.03)) : max(2, Int(longer * 0.01))
    }

    func isSame(_ a: VideoSignature, _ b: VideoSignature) -> Bool {
        guard level != .off, !a.tokens.isEmpty, !b.tokens.isEmpty else { return false }
        let bothTimed = a.duration > 0 && b.duration > 0
        let diff = abs(a.duration - b.duration)
        let shared = a.tokens.intersection(b.tokens).count
        let jaccard = Double(shared) / Double(a.tokens.union(b.tokens).count)

        if a.key == b.key {
            if bothTimed { return diff <= tolerance(a.duration, b.duration) }
            // Süre bilinmiyorsa (ör. Türk siteleri) yalnızca yeterince ayırt edici başlıklar eşleşir.
            return a.tokens.count >= (level == .strict ? 2 : 3)
        }
        guard bothTimed, diff <= tolerance(a.duration, b.duration), shared >= 2 else { return false }
        if jaccard >= (level == .strict ? 0.5 : 0.75) { return true }
        // Sıkı modda: süre saniyesi saniyesine aynı ve başlıklar kısmen örtüşüyorsa
        return level == .strict && diff <= 1 && a.duration >= 120 && jaccard >= 0.3
    }

    private func candidates(for sig: VideoSignature) -> Set<Int> {
        var out = Set(byKey[sig.key] ?? [])
        if sig.duration > 0 {
            let tol = tolerance(sig.duration, sig.duration) + 2
            for d in max(1, sig.duration - tol)...(sig.duration + tol) {
                if let list = byDuration[d] { out.formUnion(list) }
            }
        }
        return out
    }

    // MARK: Kabul

    /// Yeni bir sonuç grubunu süzer. Daha önce gösterilenlerle ya da grubun kendi içinde
    /// yinelenenler gizlenir. Grup içinde yinelenenlerden `prefer(a, b)` true dönen (a) tutulur.
    /// - Returns: Gösterilecek videolar.
    mutating func admit(_ batch: [Video], prefer: (Video, Video) -> Bool = { _, _ in false }) -> [Video] {
        guard level != .off else { return batch }
        let batchStart = kept.count
        for video in batch {
            let sig = VideoSignature(video)
            if let i = candidates(for: sig).sorted().first(where: { isSame(kept[$0].sig, sig) }) {
                hiddenCount += 1
                let existing = kept[i].video
                if i >= batchStart && prefer(video, existing) {
                    // Henüz gösterilmemiş bir kopyadan daha iyisi geldi: yer değiştir.
                    unindex(i)
                    kept[i] = Entry(video: video, sig: sig)
                    index(i)
                    alternates[video.id] = (alternates.removeValue(forKey: existing.id) ?? []) + [existing]
                } else {
                    alternates[existing.id, default: []].append(video)
                }
            } else {
                kept.append(Entry(video: video, sig: sig))
                index(kept.count - 1)
            }
        }
        return kept[batchStart...].map(\.video)
    }

    private mutating func index(_ i: Int) {
        let sig = kept[i].sig
        byKey[sig.key, default: []].append(i)
        if sig.duration > 0 { byDuration[sig.duration, default: []].append(i) }
    }

    private mutating func unindex(_ i: Int) {
        let sig = kept[i].sig
        byKey[sig.key]?.removeAll { $0 == i }
        if sig.duration > 0 { byDuration[sig.duration]?.removeAll { $0 == i } }
    }
}
