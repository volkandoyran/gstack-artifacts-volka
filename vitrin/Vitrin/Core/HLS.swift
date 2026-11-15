import Foundation

/// HLS ana listesini (master playlist) kalite seçeneklerine ayırır.
enum HLS {
    /// Ana listeyi indirip ayrıştırır. İndirilemezse sadece "Otomatik" döner.
    static func variants(master: URL, headers: [String: String] = [:]) async -> [StreamVariant] {
        guard let text = try? await HTTP.text(master, headers: headers) else {
            return [StreamVariant(height: 0, url: master)]
        }
        return parse(master: text, baseURL: master)
    }

    /// İlk eleman her zaman "Otomatik" (uyarlanabilir ana liste), ardından yüksekten düşüğe sabit kaliteler.
    static func parse(master text: String, baseURL: URL) -> [StreamVariant] {
        var best: [Int: (bandwidth: Int, url: URL)] = [:]
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                var height = Int(Rx.first(#"RESOLUTION=\d+x(\d+)"#, in: line)?[1] ?? "") ?? 0
                if height == 0 { height = Int(Rx.first(#"NAME="?(\d{3,4})p"#, in: line)?[1] ?? "") ?? 0 }
                let bandwidth = Int(Rx.first(#"BANDWIDTH=(\d+)"#, in: line)?[1] ?? "") ?? 0
                var j = i + 1
                while j < lines.count, lines[j].isEmpty || lines[j].hasPrefix("#") { j += 1 }
                if j < lines.count, height > 0, let url = URL(string: lines[j], relativeTo: baseURL)?.absoluteURL {
                    if best[height] == nil || best[height]!.bandwidth < bandwidth {
                        best[height] = (bandwidth, url)
                    }
                }
                i = j
            }
            i += 1
        }
        let fixed = best.map { StreamVariant(height: $0.key, url: $0.value.url) }.sorted { $0.height > $1.height }
        return [StreamVariant(height: 0, url: baseURL)] + fixed
    }
}
