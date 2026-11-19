import Foundation
import Observation

struct SearchJob: Sendable {
    let provider: any ContentProvider
    let query: SearchQuery
}

/// Seçimlere göre hangi siteye hangi sorgunun gideceğini belirler (saf fonksiyonlar; test edilebilir).
enum SearchPlanner {
    static func jobs(providers: [any ContentProvider], selected: [AppCategory],
                     free: BilingualTerms, combine: CombineMode, sort: SortOption, page: Int) -> [SearchJob] {
        var jobs: [SearchJob] = []
        for provider in providers {
            let lang = provider.language
            let extra = free.terms(for: lang)
            let terms = selected.map { $0.term(for: lang) }

            let termSets: [[String]]
            if terms.isEmpty {
                termSets = [extra]
            } else if combine == .all {
                termSets = [terms + extra]          // VE: tek sorgu, tüm terimler
            } else {
                termSets = terms.map { [$0] + extra }  // VEYA: her kategori ayrı sorgu
            }
            for set in termSets {
                jobs.append(SearchJob(provider: provider, query: SearchQuery(terms: set, sort: sort, page: page)))
            }
        }
        return jobs
    }

    /// Her kaynaktan sırayla bir video alarak karıştırır (tek sitenin listeyi doldurmaması için).
    static func interleave(_ buckets: [[Video]]) -> [Video] {
        var merged: [Video] = []
        let longest = buckets.map(\.count).max() ?? 0
        for i in 0..<longest {
            for b in buckets where i < b.count { merged.append(b[i]) }
        }
        return merged
    }

    /// Kaynakların kendi sıralamaları farklı olduğu için birleşik listeyi yeniden sıralar.
    static func sort(_ list: inout [Video], by sort: SortOption) {
        switch sort {
        case .relevance: break
        case .newest: list.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .mostViewed: list.sort { $0.views > $1.views }
        case .topRated: list.sort { $0.rating > $1.rating }
        case .longest: list.sort { $0.durationSec > $1.durationSec }
        case .shortest:
            // Süresi bilinmeyenler (0) sona
            list.sort { ($0.durationSec == 0 ? Int.max : $0.durationSec) < ($1.durationSec == 0 ? Int.max : $1.durationSec) }
        }
    }

    /// Aynı videonun iki kopyasından hangisi gösterilsin? Doğrudan akış veren (uygulama içi
    /// kalite seçimi olan) kaynak, sonra daha yüksek çözünürlük, sonra daha çok izlenen.
    static func prefer(_ a: Video, over b: Video) -> Bool {
        func score(_ v: Video) -> (Int, Int, Int) {
            (ProviderRegistry.provider(v.providerID)?.nativeQuality == true ? 1 : 0, v.maxHeight ?? 0, v.views)
        }
        return score(a) > score(b)
    }
}

enum FilterSettings {
    static let dedupeKey = "dedupeLevel"
    static let hideWatchedKey = "hideWatched"

    static var dedupeLevel: DedupeLevel {
        DedupeLevel(rawValue: UserDefaults.standard.object(forKey: dedupeKey) as? Int ?? DedupeLevel.normal.rawValue) ?? .normal
    }
    static var hideWatched: Bool { UserDefaults.standard.bool(forKey: hideWatchedKey) }
}

/// Tüm sağlayıcılarda paralel arama yapar; sonuçları birleştirir, süzer ve sıralar.
@MainActor
@Observable
final class BrowseModel {
    var selected: Set<String> = []
    var freeText = ""
    var combine: CombineMode = .all
    var sort: SortOption = .relevance

    private(set) var videos: [Video] = []
    private(set) var failures: [String: String] = [:]
    private(set) var isLoading = false
    /// Yinelenen olduğu için gizlenen video sayısı
    private(set) var hiddenDuplicates = 0
    /// Daha önce izlendiği için gizlenen video sayısı
    private(set) var hiddenWatched = 0
    /// Gösterilen video kimliği -> aynı videonun diğer sitelerdeki kopyaları
    private(set) var alternates: [String: [Video]] = [:]
    /// Yapay zekânın son çevirisi hakkında kısa not
    private(set) var aiNote: String?
    private(set) var aiBusy = false

    private var page = 1
    private var canLoadMore = true
    private var seen = Set<String>()
    private var generation = 0
    private var dedupe = DuplicateFilter()
    private var aiTerms: (text: String, terms: BilingualTerms)?
    private var emptyStreak = 0

    var visibleCategories: [AppCategory] {
        CategoryCatalog.all
    }

    func toggle(_ c: AppCategory) {
        if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
    }

    func refresh() {
        generation += 1
        page = 1
        videos = []
        seen = []
        failures = [:]
        alternates = [:]
        hiddenDuplicates = 0
        hiddenWatched = 0
        canLoadMore = true
        dedupe = DuplicateFilter(level: FilterSettings.dedupeLevel)
        if aiTerms?.text != freeText { aiNote = nil }
        let gen = generation
        Task { await load(generation: gen) }
    }

    func loadMoreIfNeeded(current v: Video) {
        guard canLoadMore, !isLoading,
              let idx = videos.firstIndex(where: { $0.id == v.id }),
              idx >= videos.count - 6 else { return }
        page += 1
        let gen = generation
        Task { await load(generation: gen) }
    }

    /// Arama kutusundaki metni Gemini/GPT (yoksa sözlük) ile etiketlere çevirip arar.
    func expandWithAI() async {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !aiBusy else { return }
        aiBusy = true
        let result = await AITagAssistant().tags(for: text)
        aiBusy = false
        guard text == freeText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        aiTerms = (freeText, result.terms)
        let en = result.terms.en.joined(separator: ", "), tr = result.terms.tr.joined(separator: ", ")
        aiNote = "\(result.source): \(en)" + (tr != en && !tr.isEmpty ? " · \(tr)" : "")
        refresh()
    }

    // MARK: - Yükleme

    private func freeTerms() -> BilingualTerms {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return BilingualTerms(en: [], tr: []) }
        if let ai = aiTerms, ai.text == freeText { return ai.terms }
        let t = TagTranslator.bilingual(text)
        return BilingualTerms(en: AnimatedFilter.sanitize(SafetyFilter.sanitize(t.en)),
                              tr: AnimatedFilter.sanitize(SafetyFilter.sanitize(t.tr)))
    }

    private func load(generation gen: Int) async {
        isLoading = true
        defer { if gen == generation { isLoading = false } }

        let jobs = SearchPlanner.jobs(
            providers: ProviderRegistry.enabled(),
            selected: CategoryCatalog.all.filter { selected.contains($0.id) },
            free: freeTerms(), combine: combine, sort: sort, page: page)

        var buckets = [[Video]](repeating: [], count: jobs.count)
        var errors: [String: String] = [:]

        await withTaskGroup(of: (Int, Result<[Video], Error>).self) { group in
            for (i, job) in jobs.enumerated() {
                group.addTask {
                    do { return (i, .success(try await job.provider.search(job.query))) }
                    catch { return (i, .failure(error)) }
                }
            }
            for await (i, result) in group {
                switch result {
                case .success(let v): buckets[i] = v
                case .failure(let e): errors[jobs[i].provider.displayName] = HTTP.describe(e)
                }
            }
        }

        guard gen == generation else { return }   // bu arada yeni arama başlamış

        // 1) güvenlik  2) aynı kimlik  3) izlenenler  4) yinelenenler  5) sıralama
        // Daha önce görülmemiş kimlikler. Hiç yenisi yoksa (site aynı sayfayı tekrar veriyorsa) liste bitmiştir.
        let fresh = SearchPlanner.interleave(buckets).filter { seen.insert($0.id).inserted }
        var batch = fresh.filter { SafetyFilter.isAllowed($0) && !AnimatedFilter.isAnimated($0) }
        if FilterSettings.hideWatched {
            let before = batch.count
            batch.removeAll { WatchHistory.shared.isWatched($0) }
            hiddenWatched += before - batch.count
        }
        batch = dedupe.admit(batch) { SearchPlanner.prefer($0, over: $1) }
        SearchPlanner.sort(&batch, by: sort)

        videos.append(contentsOf: batch)
        alternates = dedupe.alternates
        hiddenDuplicates = dedupe.hiddenCount
        failures.merge(errors) { _, new in new }
        canLoadMore = !fresh.isEmpty

        // Otomatik denemeler için (uygulama "-diagnostics" ile başlatılırsa): yalnızca sayılar, başlık yok.
        if ProcessInfo.processInfo.arguments.contains("-diagnostics") {
            let perSource = Dictionary(grouping: videos, by: \.providerID).mapValues(\.count)
                .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            print("VITRIN-DIAG sayfa=\(page) gosterilen=\(videos.count) yinelenen=\(hiddenDuplicates) kaynaklar=[\(perSource)] hatalar=\(failures.keys.sorted())")
        }

        // Sayfanın tamamı süzüldüyse (hepsi yinelenen/izlenmiş) kullanıcı kaydırmadan sonrakini getir.
        if batch.isEmpty, canLoadMore, emptyStreak < 3 {
            emptyStreak += 1
            page += 1
            await load(generation: gen)
        } else {
            emptyStreak = 0
        }
    }
}
