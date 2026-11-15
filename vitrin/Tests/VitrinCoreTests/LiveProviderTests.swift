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
                if let first = list.first(where: SafetyFilter.isAllowed) {
                    do {
                        switch try await p.playback(for: first) {
                        case .streams(let variants, let headers):
                            playCell = "yerel oynatıcı: " + variants.map(\.label).joined(separator: ", ")
                            // İlk HLS listesine gerçekten erişilebiliyor mu?
                            if let hls = variants.first(where: { $0.url.pathExtension.lowercased() == "m3u8" }) {
                                let body = (try? await HTTP.text(hls.url, headers: headers)) ?? ""
                                playCell += body.contains("#EXTM3U") ? " · akış erişilebilir" : " · AKIŞA ERİŞİLEMEDİ"
                            }
                        case .embed(let url, _):
                            playCell = "gömülü oynatıcı (\(url.host ?? "?"))"
                        }
                    } catch {
                        playCell = "OYNATMA HATASI: \(HTTP.describe(error)) [\(String(describing: error).prefix(120))]"
                    }
                }
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
