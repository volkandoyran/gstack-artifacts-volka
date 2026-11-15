import Foundation

/// İki dilli arama terimleri: yabancı siteler için İngilizce, Türk siteleri için Türkçe.
struct BilingualTerms: Equatable, Sendable {
    var en: [String]
    var tr: [String]

    func terms(for lang: Lang) -> [String] { lang == .tr ? tr : en }
    var isEmpty: Bool { en.isEmpty && tr.isEmpty }
}

/// Anahtar ve internet gerektirmeyen çevrimdışı TR <-> EN etiket sözlüğü.
/// Kullanıcı hangi dilde yazarsa yazsın, her site kendi dilindeki terimi alır.
enum TagTranslator {
    /// (Türkçe, İngilizce)
    static let pairs: [(String, String)] = [
        ("türkçe altyazılı", "turkish subtitles"), ("büyük göğüs", "big tits"), ("büyük memeli", "big tits"),
        ("ev yapımı", "homemade"), ("dış mekan", "outdoor"), ("gizli çekim", "hidden cam"),
        ("canavar kız", "monster girl"), ("üvey anne", "stepmom"), ("üvey kardeş", "stepsister"),
        ("sarışın", "blonde"), ("esmer", "brunette"), ("kızıl", "redhead"), ("olgun", "milf"),
        ("amatör", "amateur"), ("türk", "turkish"), ("asyalı", "asian"), ("japon", "japanese"),
        ("koreli", "korean"), ("rus", "russian"), ("latin", "latina"), ("zenci", "ebony"), ("siyahi", "ebony"),
        ("lezbiyen", "lesbian"), ("üçlü", "threesome"), ("grup", "group"), ("masaj", "massage"),
        ("çift", "couple"), ("romantik", "romantic"), ("sert", "rough"), ("oral", "blowjob"),
        ("hemşire", "nurse"), ("hizmetçi", "maid"), ("dokunaç", "tentacle"), ("sansürsüz", "uncensored"),
        ("komedi", "comedy"), ("fantastik", "fantasy"), ("sekreter", "secretary"), ("öğretmen", "teacher"),
        ("duş", "shower"), ("plaj", "beach"), ("dövmeli", "tattoo"), ("şişman", "bbw"), ("tombul", "chubby"),
        ("zayıf", "skinny"), ("dışarıda", "outdoor"), ("ofis", "office"), ("konulu", "story"),
        ("aldatma", "cheating"), ("altyazılı", "subtitles"), ("mastürbasyon", "masturbation"),
        ("evli", "married"), ("komşu", "neighbor"), ("patron", "boss"), ("doktor", "doctor"),
    ]

    private static let table: (trToEn: [String: String], enToTr: [String: String], maxWords: Int) = {
        var a: [String: String] = [:], b: [String: String] = [:], longest = 1
        for (tr, en) in pairs {
            let ft = tr.asciiFolded, fe = en.asciiFolded
            if a[ft] == nil { a[ft] = en }
            if b[fe] == nil { b[fe] = tr }
            longest = max(longest, ft.wordTokens.count, fe.wordTokens.count)
        }
        return (a, b, longest)
    }()

    /// Serbest metni her iki dile çevirir. Sözlükte olmayan kelimeler iki listeye de olduğu gibi girer.
    static func bilingual(_ text: String) -> BilingualTerms {
        let original = text.lowercased().wordTokens
        let folded = original.map(\.asciiFolded)
        var en: [String] = [], tr: [String] = []
        var i = 0
        while i < folded.count {
            var matched = false
            for n in stride(from: min(table.maxWords, folded.count - i), through: 1, by: -1) {
                let phrase = folded[i..<(i + n)].joined(separator: " ")
                let typed = original[i..<(i + n)].joined(separator: " ")
                if let e = table.trToEn[phrase] {            // Türkçe yazılmış
                    en.append(e); tr.append(typed)
                } else if let t = table.enToTr[phrase] {     // İngilizce yazılmış
                    en.append(typed); tr.append(t)
                } else { continue }
                i += n
                matched = true
                break
            }
            if !matched {
                en.append(original[i]); tr.append(original[i])
                i += 1
            }
        }
        return BilingualTerms(en: en, tr: tr)
    }
}
