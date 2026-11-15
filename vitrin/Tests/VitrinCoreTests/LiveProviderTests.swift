import XCTest
@testable import VitrinCore

/// Kaynak sitelere GERÇEK istek atar: her yerleşik kaynakta arama yapar, ilk sonucun
/// oynatma bilgisini çözer. Yalnızca `VITRIN_LIVE=1 swift test --filter LiveProviderTests`
/// ile çalışır (GitHub Actions'taki "Canlı kaynak denemesi" işi). Çıktıda başlık yoktur, sadece sayılar.
final class LiveProviderTests: XCTestCase {
    func testBuiltInProvidersLive() async throws {
        guard ProcessInfo.processInfo.environment["VITRIN_LIVE"] == "1" else {
            throw XCTSkip("VITRIN_LIVE=1 verilmedi")
        }
        var rows: [String] = []
        var working = 0

        for p in ProviderRegistry.builtIn {
            let kind: ContentKind = p.kinds.contains(.real) ? .real : .hentai
            let term = kind == .hentai ? "uncensored" : (p.language == .tr ? "masaj" : "massage")
            var searchCell = "", playCell = "—"
            do {
                let list = try await p.search(SearchQuery(terms: [term], kind: kind, sort: .relevance, page: 1))
                let timed = list.filter { $0.durationSec > 0 }.count
                let thumbed = list.filter { $0.thumbnail != nil }.count
                searchCell = "\(list.count) sonuç · süreli \(timed) · görselli \(thumbed)"
                if !list.isEmpty { working += 1 }
                // İlk üç (güvenlik filtresinden geçen) sonucun oynatma bilgisini çöz.
                var outcomes: [String] = []
                for video in list.filter(SafetyFilter.isAllowed).prefix(3) {
                    do {
                        switch try await p.playback(for: video) {
                        case .streams(let variants, let headers):
                            var text = "yerel oynatıcı [" + variants.map(\.label).joined(separator: ", ") + "]"
                            // İlk HLS listesine gerçekten erişilebiliyor mu?
                            if let hls = variants.first(where: { $0.url.pathExtension.lowercased() == "m3u8" }) {
                                let body = (try? await HTTP.text(hls.url, headers: headers)) ?? ""
                                text += body.contains("#EXTM3U") ? " akış erişilebilir" : " AKIŞA ERİŞİLEMEDİ"
                            }
                            outcomes.append(text)
                        case .embed(let url, _):
                            var text = "gömülü oynatıcı (\(url.host ?? "?"))"
                            // Doğrudan akış beklenen kaynakta gömülüye düşüldüyse nedenini kaydet (başlık yazılmaz).
                            if p.nativeQuality, let page = video.pageURL {
                                let html = (try? await HTTP.text(page)) ?? ""
                                text += " {sayfa \(html.count) bayt"
                                    + ", html5player: \(html.contains("html5player"))"
                                    + ", HLS: \(html.contains("setVideoHLS"))"
                                    + ", yaş doğrulama: \(html.lowercased().contains("age verification") || html.lowercased().contains("verify your age"))}"
                            }
                            outcomes.append(text)
                        }
                    } catch {
                        outcomes.append("OYNATMA HATASI: \(HTTP.describe(error)) [\(String(describing: error).prefix(100))]")
                    }
                }
                if !outcomes.isEmpty { playCell = outcomes.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: " · ") }
            } catch {
                searchCell = "ARAMA HATASI: \(HTTP.describe(error)) [\(String(describing: error).prefix(120))]"
            }
            rows.append("| \(p.displayName) | \(term) | \(searchCell) | \(playCell) |")
        }

        let table = (["## Canlı kaynak denemesi", "",
                      "| Kaynak | Arama | Sonuç | Oynatma |", "|---|---|---|---|"] + rows).joined(separator: "\n") + "\n"
        print(table)
        if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"],
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(table.utf8))
            handle.closeFile()
        }
        XCTAssertGreaterThan(working, 0, "hiçbir kaynak sonuç döndürmedi")
    }
}
