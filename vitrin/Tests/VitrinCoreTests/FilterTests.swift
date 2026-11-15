import XCTest
@testable import VitrinCore

private func video(_ provider: String, _ id: String, _ title: String, _ duration: Int = 0,
                   views: Int = 0, height: Int? = nil, kind: ContentKind = .real, tags: [String] = []) -> Video {
    Video(providerID: provider, remoteID: id, kind: kind, title: title, durationSec: duration,
          views: views, tags: tags, maxHeight: height)
}

final class DuplicateFilterTests: XCTestCase {

    func testSameVideoAcrossSitesIsMerged() {
        var f = DuplicateFilter(level: .normal)
        let out = f.admit([
            video("eporner", "1", "Relaxing Massage Turns Into Something More", 725),
            video("pornhub", "2", "Relaxing massage turns into something more - HD", 726),
            video("redtube", "3", "RELAXING MASSAGE TURNS INTO SOMETHING MORE (Full Video)", 724),
            video("xvideos", "4", "Completely different title here", 725),
        ])
        XCTAssertEqual(out.map(\.id), ["eporner:1", "xvideos:4"])
        XCTAssertEqual(f.hiddenCount, 2)
        XCTAssertEqual(f.alternates["eporner:1"]?.map(\.id), ["pornhub:2", "redtube:3"])
    }

    func testSameTitleDifferentLengthIsKept() {
        var f = DuplicateFilter(level: .normal)
        let out = f.admit([
            video("a", "1", "Hot blonde massage", 600),
            video("b", "2", "Hot blonde massage", 1900),   // aynı ad, başka video
            video("c", "3", "Office story part 1", 900),
            video("c", "4", "Office story part 2", 900),   // bölüm numarası farklı
        ])
        XCTAssertEqual(out.count, 4)
        XCTAssertEqual(f.hiddenCount, 0)
    }

    func testUnknownDurationNeedsDistinctiveExactTitle() {
        var f = DuplicateFilter(level: .normal)
        let out = f.admit([
            video("wp-doeda.com", "1", "Masaj Salonunda Tanıştığı Kadınla Eve Gitti"),
            video("wp-doeda.one", "2", "Masaj salonunda tanistigi kadinla eve gitti!"),   // aynı yazı, ikiz site
            video("wp-doeda.com", "3", "Masaj"),
            video("wp-doeda.one", "4", "Masaj"),                                          // fazla genel: birleştirme
        ])
        XCTAssertEqual(out.map(\.remoteID), ["1", "3", "4"])
    }

    func testStrictCatchesRetitledCopies() {
        let a = video("eporner", "1", "Blonde neighbor gets a deep massage on the couch", 1291)
        let b = video("xnxx", "2", "Neighbor massage on couch - blonde amateur", 1290)
        var normal = DuplicateFilter(level: .normal)
        XCTAssertEqual(normal.admit([a, b]).count, 2)
        var strict = DuplicateFilter(level: .strict)
        XCTAssertEqual(strict.admit([a, b]).count, 1)
    }

    func testPreferredCopyWinsInsideBatchButShownOnesStay() {
        var f = DuplicateFilter(level: .normal)
        let embedOnly = video("pornhub", "1", "Sunny afternoon by the pool", 800, views: 10)
        let direct = video("xvideos", "2", "Sunny afternoon by the pool", 800, views: 5, height: 1080)
        let prefer: (Video, Video) -> Bool = { a, b in (a.maxHeight ?? 0) > (b.maxHeight ?? 0) }

        let first = f.admit([embedOnly, direct], prefer: prefer)
        XCTAssertEqual(first.map(\.id), ["xvideos:2"], "aynı grupta daha iyi kopya tutulur")
        XCTAssertEqual(f.alternates["xvideos:2"]?.map(\.id), ["pornhub:1"])

        // Sonraki sayfada daha da iyisi gelse bile ekrandaki kart değişmez; yeni gelen gizlenir.
        let better = video("xnxx", "3", "Sunny afternoon by the pool", 801, height: 2160)
        XCTAssertTrue(f.admit([better], prefer: prefer).isEmpty)
        XCTAssertEqual(f.alternates["xvideos:2"]?.map(\.id), ["pornhub:1", "xnxx:3"])
        XCTAssertEqual(f.hiddenCount, 2)
    }

    func testOffLevelPassesEverything() {
        var f = DuplicateFilter(level: .off)
        let v = video("a", "1", "Same title here twice", 100)
        XCTAssertEqual(f.admit([v, video("b", "2", "Same title here twice", 100)]).count, 2)
    }

    func testSignatureNormalisation() {
        let a = VideoSignature(title: "Sarışın & Esmer — FULL HD 1080p Video", duration: 61)
        XCTAssertEqual(a.key, "esmer sarisin")
        XCTAssertEqual(a.historyKey, "esmer sarisin|12")
        XCTAssertEqual(VideoSignature(title: "Episode 2", duration: 0).tokens, ["episode", "2"])
    }
}

final class SafetyFilterTests: XCTestCase {
    func testBlocksMinorsInBothLanguages() {
        for bad in ["cute loli", "Shota adventure", "underage", "she is 16 years old", "17yo girl",
                    "Liseli kız", "çocuk", "küçük yaşta", "16 yaşında", "Reşit olmayan", "ergen", "lolita"] {
            XCTAssertTrue(SafetyFilter.isBlocked(bad), bad)
        }
        for ok in ["18 yaşındaki genç kadın", "18 years old", "childhood friend", "Üniversiteli", "milf",
                   "19yo", "kidnapped by aliens", "minority report", "liselotte"] {
            XCTAssertFalse(SafetyFilter.isBlocked(ok), ok)
        }
    }

    func testSchoolThemeOnlyBlockedForDrawnContent() {
        XCTAssertTrue(SafetyFilter.isBlocked("school girl", kind: .hentai))
        XCTAssertFalse(SafetyFilter.isBlocked("school girl", kind: .real))
    }

    func testVideoAndTermFiltering() {
        XCTAssertFalse(SafetyFilter.isAllowed(video("x", "1", "Fine title", tags: ["blonde", "liseli"])))
        XCTAssertTrue(SafetyFilter.isAllowed(video("x", "2", "Fine title", tags: ["18 yas", "amator"])))
        XCTAssertEqual(SafetyFilter.sanitize(["blonde", "loli", "masaj"]), ["blonde", "masaj"])
    }
}

final class WatchHistoryTests: XCTestCase {
    func testWatchedIsRecognisedAcrossSites() throws {
        let suite = "vitrin.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let h = WatchHistory(defaults: defaults)
        let seen = video("eporner", "1", "Evening walk on the beach", 600)
        XCTAssertFalse(h.isWatched(seen))
        h.markWatched(seen)
        XCTAssertTrue(h.isWatched(seen))
        XCTAssertTrue(h.isWatched(video("pornhub", "9", "Evening Walk On The Beach HD", 601)), "başka sitedeki kopya")
        XCTAssertFalse(h.isWatched(video("pornhub", "8", "Evening walk on the beach", 1500)))
        XCTAssertEqual(h.count, 1)

        // Kalıcı mı?
        XCTAssertTrue(WatchHistory(defaults: defaults).isWatched(seen))
        h.clear()
        XCTAssertFalse(WatchHistory(defaults: defaults).isWatched(seen))
    }
}

final class FavoritesStoreTests: XCTestCase {
    func testFavoritesPersistAndToggle() async {
        let suite = "vitrin.tests.\(UUID().uuidString)"
        let a = Video(providerID: "eporner", remoteID: "1", kind: .real, title: "A",
                      thumbnail: URL(string: "https://cdn/a.jpg"), durationSec: 60, addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      tags: ["x"], embedURL: URL(string: "https://e/1"), maxHeight: 720)
        let b = video("xvideos", "2", "B", 30)

        await MainActor.run {
            guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("UserDefaults açılamadı") }
            defer { defaults.removePersistentDomain(forName: suite) }

            let store = FavoritesStore(defaults: defaults)
            XCTAssertTrue(store.toggle(a))
            XCTAssertTrue(store.toggle(b))
            XCTAssertEqual(store.videos.map(\.id), ["xvideos:2", "eporner:1"], "son eklenen başta")

            let reloaded = FavoritesStore(defaults: defaults)
            XCTAssertEqual(reloaded.videos, store.videos, "tüm alanlarıyla geri yüklenmeli")
            XCTAssertFalse(reloaded.toggle(a))
            XCTAssertEqual(FavoritesStore(defaults: defaults).videos.map(\.id), ["xvideos:2"])
        }
    }
}
