import Foundation

/// İzlenen videoların (yalnızca cihazda tutulan) kısa listesi. "İzlediklerimi gizle"
/// filtresi bunu kullanır; aynı video başka bir siteden gelse de tanınır.
final class WatchHistory: @unchecked Sendable {
    static let shared = WatchHistory(defaults: .standard)

    private let defaults: UserDefaults
    private let storageKey = "watchHistory.v1"
    private let limit = 4000
    private let lock = NSLock()
    private var order: [String] = []
    private var set: Set<String> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        order = defaults.stringArray(forKey: storageKey) ?? []
        set = Set(order)
    }

    private func keys(for v: Video) -> [String] {
        let sig = VideoSignature(v)
        // Kimlik + (ayırt edici başlığı olanlar için) başlık/süre imzası
        return sig.tokens.count >= 2 ? ["id:\(v.id)", "sig:\(sig.historyKey)"] : ["id:\(v.id)"]
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return order.filter { $0.hasPrefix("id:") }.count
    }

    func markWatched(_ v: Video) {
        lock.lock(); defer { lock.unlock() }
        for k in keys(for: v) where set.insert(k).inserted { order.append(k) }
        if order.count > limit {
            let drop = order.count - limit
            set.subtract(order.prefix(drop))
            order.removeFirst(drop)
        }
        defaults.set(order, forKey: storageKey)
    }

    func isWatched(_ v: Video) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys(for: v).contains { set.contains($0) }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        order = []
        set = []
        defaults.removeObject(forKey: storageKey)
    }
}
