import Foundation

/// Küçük NSRegularExpression sarmalayıcısı (HTML ayrıştırma için).
enum Rx {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        cache[pattern] = r
        return r
    }

    private static func groups(_ m: NSTextCheckingResult, in s: String) -> [String] {
        (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    /// İlk eşleşmenin grupları ([0] = tüm eşleşme). Eşleşmeyen gruplar boş string.
    static func first(_ pattern: String, in s: String) -> [String]? {
        guard let re = regex(pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return groups(m, in: s)
    }

    static func all(_ pattern: String, in s: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { groups($0, in: s) }
    }

    /// Eşleşmelerin metin içindeki aralıkları (blok blok bölmek için).
    static func ranges(_ pattern: String, in s: String) -> [Range<String.Index>] {
        guard let re = regex(pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s) }
    }
}

extension String {
    /// &amp; &#8217; &#x27; gibi HTML varlıklarını çözer.
    var htmlDecoded: String {
        guard contains("&") else { return self }
        var out = self
        for m in Rx.all(#"&#(x?)([0-9a-f]+);"#, in: self) {
            let code = m[1].isEmpty ? UInt32(m[2], radix: 10) : UInt32(m[2], radix: 16)
            if let code, let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        let named = ["&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                     "&hellip;": "…", "&ndash;": "–", "&mdash;": "—", "&amp;": "&"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    var strippingTags: String {
        guard let re = try? NSRegularExpression(pattern: "<[^>]+>") else { return self }
        let s = re.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: " ")
        return s.htmlDecoded
    }

    /// Karşılaştırma için sadeleştirme: küçük harf, Türkçe karakterler ve aksanlar ASCII'ye.
    var asciiFolded: String {
        var s = self
        for (a, b) in [("İ", "i"), ("I", "i"), ("ı", "i"), ("Ş", "s"), ("ş", "s"), ("Ğ", "g"), ("ğ", "g"),
                       ("Ü", "u"), ("ü", "u"), ("Ö", "o"), ("ö", "o"), ("Ç", "c"), ("ç", "c")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// Harf/rakam dışındaki her şeyi ayırıcı sayarak kelimelere böler.
    var wordTokens: [String] {
        split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }
}
