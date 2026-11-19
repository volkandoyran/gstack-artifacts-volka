import XCTest
@testable import VitrinCore

final class TagTranslatorTests: XCTestCase {
    func testTurkishInputGetsEnglishForForeignSites() {
        let t = TagTranslator.bilingual("Sarışın olgun masaj")
        XCTAssertEqual(t.en, ["blonde", "milf", "massage"])
        XCTAssertEqual(t.tr, ["sarışın", "olgun", "masaj"])
    }

    func testEnglishInputGetsTurkishForTurkishSites() {
        let t = TagTranslator.bilingual("big tits blonde")
        XCTAssertEqual(t.en, ["big tits", "blonde"])
        XCTAssertEqual(t.tr, ["büyük göğüs", "sarışın"])
    }

    func testPhrasesAndUnknownWords() {
        let t = TagTranslator.bilingual("ev yapımı brazzers, TÜRK")
        XCTAssertEqual(t.en, ["homemade", "brazzers", "turkish"])
        XCTAssertEqual(t.tr, ["ev yapımı", "brazzers", "türk"])
        XCTAssertTrue(TagTranslator.bilingual("  ").isEmpty)
    }
}

final class AIReplyParsingTests: XCTestCase {
    func testObjectReply() {
        let reply = "```json\n{\"en\": [\"Blonde\", \"milf \"], \"tr\": [\"sarışın\", \"olgun\"]}\n```"
        XCTAssertEqual(AITagAssistant.parse(reply), BilingualTerms(en: ["blonde", "milf"], tr: ["sarışın", "olgun"]))
    }

    func testArrayReplyFallsBackToDictionaryForTurkish() {
        XCTAssertEqual(AITagAssistant.parse("Sure: [\"blonde\", \"massage\"]"),
                       BilingualTerms(en: ["blonde", "massage"], tr: ["sarışın", "masaj"]))
    }

    func testUnsafeOrEmptyRepliesAreRejected() {
        XCTAssertNil(AITagAssistant.parse("I can't help with that."))
        XCTAssertNil(AITagAssistant.parse("{\"en\": [], \"tr\": []}"))
        XCTAssertEqual(AITagAssistant.parse("{\"en\": [\"loli\", \"maid\"], \"tr\": [\"hizmetçi\"]}")?.en, ["maid"])
    }

    func testDictionaryFallbackWhenNoEngineConfigured() async {
        let settings = AITagAssistant.Settings(engine: .auto, geminiKey: "", geminiModel: "m",
                                               gptBaseURL: "https://example.invalid/v1", gptModel: "m", gptKey: "")
        let r = await AITagAssistant(settings: settings).tags(for: "kızıl hemşire")
        XCTAssertEqual(r.source, "Sözlük")
        XCTAssertEqual(r.terms.en, ["redhead", "nurse"])
    }
}

final class SearchPlannerTests: XCTestCase {
    private let providers: [any ContentProvider] = [EpornerProvider(), WordPressProvider(site: .doeda)]
    private func cat(_ id: String) -> AppCategory { CategoryCatalog.all.first { $0.id == id }! }

    func testAndModeSendsOneQueryPerSiteInItsLanguage() {
        let jobs = SearchPlanner.jobs(providers: providers, selected: [cat("r-blonde"), cat("r-massage")],
                                      free: TagTranslator.bilingual("ofis"), combine: .all, sort: .newest, page: 1)
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs.first { $0.provider.id == "eporner" }?.query.terms, ["blonde", "massage", "office"])
        XCTAssertEqual(jobs.first { $0.provider.id == "wp-doeda.com" }?.query.terms, ["sarışın", "masaj", "ofis"])
    }

    func testOrModeSendsOneQueryPerCategory() {
        let jobs = SearchPlanner.jobs(providers: [EpornerProvider()], selected: [cat("r-blonde"), cat("r-massage")],
                                      free: BilingualTerms(en: [], tr: []), combine: .any, sort: .relevance, page: 2)
        XCTAssertEqual(jobs.map(\.query.terms), [["blonde"], ["massage"]])
        XCTAssertTrue(jobs.allSatisfy { $0.query.page == 2 })
    }

    func testNoSelectionBrowsesEverything() {
        let jobs = SearchPlanner.jobs(providers: providers, selected: [],
                                      free: BilingualTerms(en: [], tr: []), combine: .all, sort: .relevance, page: 1)
        XCTAssertEqual(jobs.count, 2)
        XCTAssertTrue(jobs.allSatisfy { $0.query.terms.isEmpty })
    }

    func testCatalogHasNoAnimatedCategories() {
        XCTAssertFalse(CategoryCatalog.all.contains { AnimatedFilter.isAnimated($0.title) || AnimatedFilter.isAnimated($0.term) })
        XCTAssertTrue(CategoryCatalog.all.allSatisfy { $0.id.hasPrefix("r-") })
    }

    func testInterleaveAndSort() {
        func v(_ p: String, _ id: String, d: Int, views: Int) -> Video {
            Video(providerID: p, remoteID: id, title: id, durationSec: d, views: views)
        }
        let a = [v("a", "1", d: 100, views: 5), v("a", "2", d: 0, views: 9)]
        let b = [v("b", "3", d: 50, views: 7)]
        var merged = SearchPlanner.interleave([a, b, []])
        XCTAssertEqual(merged.map(\.remoteID), ["1", "3", "2"])
        SearchPlanner.sort(&merged, by: .mostViewed)
        XCTAssertEqual(merged.map(\.remoteID), ["2", "3", "1"])
        SearchPlanner.sort(&merged, by: .shortest)
        XCTAssertEqual(merged.map(\.remoteID), ["3", "1", "2"], "süresi bilinmeyen sona")
    }

    func testRegistryHasAllBuiltInSources() {
        let ids = ProviderRegistry.builtIn.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "kimlikler benzersiz olmalı")
        XCTAssertEqual(Set(ids), ["xvideos", "xnxx", "eporner", "pornhub", "redtube", "wp-doeda.com", "wp-doeda.one"])
    }
}
