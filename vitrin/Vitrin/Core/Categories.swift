import Foundation

struct AppCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String    // Türkçe görünen ad
    let term: String     // yabancı sitelerde aranan İngilizce terim
    let termTR: String   // Türk sitelerinde aranan Türkçe terim

    func term(for lang: Lang) -> String { lang == .tr ? termTR : term }
}

enum CategoryCatalog {
    private static func r(_ title: String, _ en: String, _ tr: String? = nil) -> AppCategory {
        AppCategory(id: "r-\(en)", title: title, term: en, termTR: tr ?? title.lowercased())
    }
    static let real: [AppCategory] = [
        r("Türk", "turkish", "türk"), r("Türkçe altyazılı", "turkish subtitles", "türkçe altyazılı"),
        r("Amatör", "amateur", "amatör"), r("Ev yapımı", "homemade", "ev yapımı"),
        r("Sarışın", "blonde", "sarışın"), r("Esmer", "brunette", "esmer"), r("Kızıl", "redhead", "kızıl"),
        r("Olgun", "milf", "olgun"), r("Asyalı", "asian", "asyalı"), r("Japon", "japanese", "japon"),
        r("Latin", "latina", "latin"), r("Siyahi", "ebony", "zenci"), r("Lezbiyen", "lesbian", "lezbiyen"),
        r("Üçlü", "threesome", "grup"), r("POV", "pov", "pov"), r("Anal", "anal", "anal"),
        r("Oral", "blowjob", "oral"), r("Büyük göğüs", "big tits", "büyük memeli"), r("Masaj", "massage", "masaj"),
        r("Dış mekan", "outdoor", "dışarıda"), r("Çift", "couple", "çift"), r("Romantik", "romantic", "romantik"),
        r("Sert", "rough", "sert"), r("Solo", "solo", "mastürbasyon"), r("Konulu", "story", "konulu"),
        r("4K", "4k", "full hd"),
    ]

    static let all: [AppCategory] = real
}
