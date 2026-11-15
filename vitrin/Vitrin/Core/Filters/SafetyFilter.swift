import Foundation

/// Reşit olmayanları çağrıştıran (ve hayvan içeren) içerikleri her zaman eler.
/// Ayarlardan kapatılamaz. Hem sonuçlara hem arama terimlerine uygulanır.
enum SafetyFilter {
    // Desenler ASCII'ye sadeleştirilmiş metne uygulanır (ç->c, ş->s, ı->i …).
    private static let always = [
        // İngilizce / Japonca
        #"\b(loli|lolicon|lolita|shota|shotacon|underage|under[- ]?age|preteen|pre[- ]teen|jailbait|toddler|child|children|kids?|minors?|little girl|young girl|pedo\w*)\b"#,
        #"\b(1[0-7]|[1-9])\s*(yo|y\.?o\.?|yrs?\s*old|years?\s*old)\b"#,
        // Türkçe
        #"\b(cocuk\w*|kucuk kiz\w*|kucuk yas\w*|yasi kucuk|resit olmayan|liseli\w*|lise|ortaokul\w*|ilkokul\w*|ergen\w*|yeniyetme\w*)\b"#,
        #"\b(1[0-7]|[1-9])\s*yas\w*"#,
        // Hayvan içeren içerik
        #"\b(bestiality|zoophil\w*|zoo ?porn|hayvanla)\b"#,
    ]
    /// Çizim içerikte okul teması çoğunlukla reşit olmayan karakter demektir.
    private static let hentaiOnly = [
        #"\b(school ?girl\w*|school ?boy\w*|high ?school\w*|middle ?school\w*|okullu\w*)\b"#,
    ]

    static func isBlocked(_ text: String, kind: ContentKind? = nil) -> Bool {
        let t = text.asciiFolded
        let patterns = kind == .hentai ? always + hentaiOnly : always
        return patterns.contains { Rx.first($0, in: t) != nil }
    }

    static func isAllowed(_ v: Video) -> Bool {
        !isBlocked(v.title, kind: v.kind) && !v.tags.contains { isBlocked($0, kind: v.kind) }
    }

    static func sanitize(_ terms: [String]) -> [String] {
        terms.filter { !isBlocked($0, kind: .hentai) }
    }
}

/// Bilinen reklam / pop-under ağları (WebView içerik engelleyicisi ve oynatıcı çerçevesi seçimi için).
enum AdHosts {
    static let all = [
        "trafficjunky.net", "trafficjunky.com", "exoclick.com", "exosrv.com", "juicyads.com",
        "tsyndicate.com", "realsrv.com", "magsrv.com", "popads.net", "popcash.net",
        "adsco.re", "adnxs.com", "doubleclick.net", "googlesyndication.com", "ad-maven.com",
        "clickadu.com", "hilltopads.net", "propellerads.com", "adspyglass.com", "a-ads.com",
        "trafficstars.com", "twinrdsrv.com", "contentabc.com", "ero-advertising.com",
        "adsterra.com", "onclickads.net", "bongacams.com", "chaturbate.com", "stripchat.com",
        "orbsrv.com", "afcdn.net", "tubecorporate.com", "wpadmngr.com",
    ]
}
