import Foundation
import Observation

/// Favori videolar. Videonun kendisi cihazda saklanır (liste çevrimdışı da görünsün diye).
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore(defaults: .standard)

    private(set) var videos: [Video] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "favorites.v1"
    @ObservationIgnored private let limit = 500

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([Video].self, from: data) {
            videos = list
        }
    }

    func isFavorite(_ v: Video) -> Bool { videos.contains { $0.id == v.id } }

    /// - Returns: işlemden sonra favori mi
    @discardableResult
    func toggle(_ v: Video) -> Bool {
        if let i = videos.firstIndex(where: { $0.id == v.id }) {
            videos.remove(at: i)
        } else {
            videos.insert(v, at: 0)
            if videos.count > limit { videos.removeLast(videos.count - limit) }
        }
        defaults.set(try? JSONEncoder().encode(videos), forKey: storageKey)
        return isFavorite(v)
    }
}
