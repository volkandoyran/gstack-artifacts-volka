import Foundation

/// Her kaynak site bir "eklenti"dir. Yeni site eklemek için bu protokolü uygulayan
/// bir struct yazıp `ProviderRegistry.builtIn` listesine eklemen yeterli.
/// WordPress tabanlı siteler kod yazmadan Ayarlar'dan eklenebilir.
protocol ContentProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Arama terimlerinin dili (Türk siteleri için .tr)
    var language: Lang { get }
    /// Doğrudan akış verip uygulama içi kalite menüsünü destekliyor mu?
    var nativeQuality: Bool { get }

    func search(_ query: SearchQuery) async throws -> [Video]
    func playback(for video: Video) async throws -> PlaybackSource
}

extension ContentProvider {
    var language: Lang { .en }
    var nativeQuality: Bool { false }

    func playback(for video: Video) async throws -> PlaybackSource {
        guard let url = video.embedURL else { throw HTTPError.empty }
        return .embed(url, referer: video.pageURL)
    }
}

enum ProviderRegistry {
    static let builtIn: [any ContentProvider] = [
        XVideosProvider(site: .xvideos),
        XVideosProvider(site: .xnxx),
        EpornerProvider(),
        PornhubProvider(),
        RedTubeProvider(),
        WordPressProvider(site: .doeda),
        WordPressProvider(site: .doedaOne),
    ]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedAll: [any ContentProvider]?

    /// Yerleşik kaynaklar + kullanıcının Ayarlar'dan eklediği WordPress siteleri.
    static var all: [any ContentProvider] {
        lock.lock(); defer { lock.unlock() }
        if let cachedAll { return cachedAll }
        let list = builtIn + customSitesUnlocked().map { WordPressProvider(site: $0) as any ContentProvider }
        cachedAll = list
        return list
    }

    static func provider(_ id: String) -> (any ContentProvider)? {
        all.first { $0.id == id }
    }

    // MARK: Aç/kapat

    private static let disabledKey = "disabledProviders"

    static var disabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: disabledKey) }
    }

    static func enabled() -> [any ContentProvider] {
        let off = disabledIDs
        return all.filter { !off.contains($0.id) }
    }

    // MARK: Kullanıcının eklediği siteler

    private static let customKey = "customWordPressSites"

    private static func customSitesUnlocked() -> [WordPressSite] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let sites = try? JSONDecoder().decode([WordPressSite].self, from: data) else { return [] }
        return sites
    }

    static var customSites: [WordPressSite] {
        get { customSitesUnlocked() }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey)
            lock.lock(); cachedAll = nil; lock.unlock()
        }
    }
}
