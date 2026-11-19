import XCTest
@testable import VitrinCore

/// Sitelerden kaydedilmiş GERÇEK yanıtlarla ayrıştırıcıları dener. Örnek dosyalar depoya
/// konmaz; `VITRIN_SAMPLES=/klasör swift test` ile verilir, yoksa testler atlanır.
/// Beklenen dosyalar: pornhub.json, redtube.json, wp_doeda_com.json, wp_doeda_one.json,
/// xvideos_search.html, xnxx_search.html, xvideos_video.html, doeda_page.html
final class RealSampleTests: XCTestCase {
    private func sample(_ name: String) throws -> Data {
        guard let dir = ProcessInfo.processInfo.environment["VITRIN_SAMPLES"] else {
            throw XCTSkip("VITRIN_SAMPLES verilmedi")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("\(name) yok") }
        return data
    }
    private func text(_ name: String) throws -> String { String(decoding: try sample(name), as: UTF8.self) }

    private func check(_ list: [Video], min: Int, needsDuration: Bool = true, needsThumb: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(list.count, min, file: file, line: line)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "kimlikler benzersiz", file: file, line: line)
        for v in list {
            XCTAssertFalse(v.title.isEmpty, file: file, line: line)
            XCTAssertFalse(v.title.contains("&amp;") || v.title.contains("<"), v.title, file: file, line: line)
            XCTAssertNotNil(v.pageURL, file: file, line: line)
        }
        let timed = list.filter { $0.durationSec > 0 }.count, thumbed = list.filter { $0.thumbnail != nil }.count
        if needsDuration { XCTAssertGreaterThanOrEqual(timed, list.count * 9 / 10, "süreler", file: file, line: line) }
        if needsThumb { XCTAssertGreaterThanOrEqual(thumbed, list.count * 9 / 10, "küçük resimler", file: file, line: line) }
        print("  örnek: \(list.count) video · süreli \(timed) · görselli \(thumbed) · izlenmeli \(list.filter { $0.views > 0 }.count)")
    }

    func testPornhub() throws {
        check(try WebmasterAPI.videos(from: try sample("pornhub.json"), provider: "pornhub") {
            URL(string: "https://www.pornhub.com/embed/\($0)")
        }, min: 20)
    }

    func testRedTube() throws {
        let list = try WebmasterAPI.videos(from: try sample("redtube.json"), provider: "redtube") { _ in nil }
        check(list, min: 15)
        XCTAssertTrue(list.allSatisfy { $0.embedURL != nil })
    }

    func testXVideosSearch() throws {
        let list = XVideosProvider.parseSearch(html: try text("xvideos_search.html"), site: .xvideos)
        check(list, min: 20)
        XCTAssertGreaterThan(list.filter { $0.views > 0 }.count, list.count / 2)
        XCTAssertTrue(list.allSatisfy { $0.pageURL?.host == "www.xvideos.com" })
    }

    func testXNXXSearch() throws {
        let list = XVideosProvider.parseSearch(html: try text("xnxx_search.html"), site: .xnxx)
        check(list, min: 20)
        XCTAssertGreaterThan(list.filter { $0.views > 0 }.count, list.count / 2)
    }

    func testXVideosVideoPage() throws {
        let s = XVideosProvider.parseStreams(html: try text("xvideos_video.html"))
        XCTAssertEqual(s.hls?.pathExtension, "m3u8")
        XCTAssertNotNil(s.high)
        XCTAssertNotNil(s.low)
    }

    func testDoedaPosts() throws {
        let com = try WordPressProvider.videos(from: try sample("wp_doeda_com.json"), site: .doeda)
        check(com, min: 2, needsDuration: false)
        XCTAssertTrue(com.allSatisfy { $0.views > 0 && !$0.tags.isEmpty })
        let one = try WordPressProvider.videos(from: try sample("wp_doeda_one.json"), site: .doedaOne)
        check(one, min: 1, needsDuration: false)
    }

    func testDoedaVideoPage() throws {
        let page = URL(string: "http://www.doeda.com/ornek/")!
        guard case .jetPlayer(let base, let vid, _)? = WordPressProvider.findPlayer(html: try text("doeda_page.html"), pageURL: page) else {
            return XCTFail("oynatıcı çerçevesi bulunamadı")
        }
        XCTAssertTrue(base.absoluteString.hasSuffix("/player/"), base.absoluteString)
        XCTAssertEqual(vid.count, 32)
    }

    /// Gerçek sonuçları birlikte süzgeçten geçirir (çökme / aşırı birleştirme olmamalı).
    func testFiltersOnRealMix() throws {
        var all = try WebmasterAPI.videos(from: try sample("pornhub.json"), provider: "pornhub") { _ in nil }
        all += try WebmasterAPI.videos(from: try sample("redtube.json"), provider: "redtube") { _ in nil }
        all += XVideosProvider.parseSearch(html: try text("xvideos_search.html"), site: .xvideos)
        all += XVideosProvider.parseSearch(html: try text("xnxx_search.html"), site: .xnxx)
        let safe = all.filter(SafetyFilter.isAllowed)
        var normal = DuplicateFilter(level: .normal), strict = DuplicateFilter(level: .strict)
        let n = normal.admit(safe), s = strict.admit(safe)
        print("  karışım: \(all.count) video · güvenlik sonrası \(safe.count) · normal \(n.count) · sıkı \(s.count)")
        for (kept, alts) in strict.alternates {
            let k = safe.first { $0.id == kept }!
            print("   ≈ [\(k.durationSec)s] \(k.providerID) ⇄ " + alts.map { "\($0.providerID) [\($0.durationSec)s]" }.joined(separator: ", "))
        }
        XCTAssertLessThanOrEqual(s.count, n.count)
        XCTAssertGreaterThan(n.count, safe.count * 3 / 4, "normal mod farklı videoları yutmamalı")
    }
}
