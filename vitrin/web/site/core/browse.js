// Arama denetleyicisi: tüm kaynaklarda paralel arar; sonuçları birleştirir, süzer, sıralar.
// Arayüzden bağımsızdır (Node'da test edilebilir); değişiklikleri onChange ile bildirir.
import { CATEGORIES, bilingual } from './catalog.js';
import { DuplicateFilter } from './dedupe.js';
import { isAllowed, sanitize } from './safety.js';
import { planJobs, interleave, sortVideos, prefer } from './planner.js';
import { describeError, RelayNeededError } from './net.js';

export function createBrowser({ net, store, getProviders, onChange = () => {} }) {
  const state = {
    kindFilter: 'all', selected: new Set(), freeText: '', combine: 'all', sort: 'relevance',
    videos: [], failures: {}, loading: false, hiddenDuplicates: 0, hiddenWatched: 0,
    alternates: new Map(), skippedForRelay: [],
  };
  let page = 1, canLoadMore = true, seen = new Set(), generation = 0, emptyStreak = 0;
  let dedupe = new DuplicateFilter(1);

  function freeTerms() {
    const text = state.freeText.trim();
    if (!text) return { en: [], tr: [] };
    const t = bilingual(text);
    return { en: sanitize(t.en), tr: sanitize(t.tr) };
  }

  async function load(gen) {
    state.loading = true; onChange();
    const settings = store.settings;
    const all = getProviders().filter((p) => !settings.disabled.includes(p.id));
    // Aracı gerektiren kaynaklar aracı yoksa hata vermeden atlanır.
    const usable = all.filter((p) => !p.relayForSearch || net.hasRelay);
    state.skippedForRelay = all.filter((p) => !usable.includes(p)).map((p) => p.name);

    const jobs = planJobs({
      providers: usable, kindFilter: state.kindFilter,
      selected: CATEGORIES.filter((c) => state.selected.has(c.id)),
      free: freeTerms(), combine: state.combine, sort: state.sort, page,
    });
    const errors = {};
    const buckets = await Promise.all(jobs.map(async (job) => {
      try { return await job.provider.search(job.query, net); }
      catch (e) {
        if (!(e instanceof RelayNeededError)) errors[job.provider.name] = describeError(e);
        return [];
      }
    }));
    if (gen !== generation) return;   // bu arada yeni arama başlamış

    // 1) güvenlik  2) aynı kimlik  3) izlenenler  4) yinelenenler  5) sıralama
    // Daha önce görülmemiş kimlikler. Hiç yenisi yoksa (site aynı sayfayı tekrar veriyorsa) liste bitmiştir.
    const fresh = interleave(buckets).filter((v) => !seen.has(v.id) && seen.add(v.id));
    let batch = fresh.filter(isAllowed);
    if (settings.hideWatched) {
      const before = batch.length;
      batch = batch.filter((v) => !store.isWatched(v));
      state.hiddenWatched += before - batch.length;
    }
    batch = sortVideos(dedupe.admit(batch, prefer), state.sort);

    state.videos = state.videos.concat(batch);
    state.alternates = dedupe.alternates;
    state.hiddenDuplicates = dedupe.hiddenCount;
    Object.assign(state.failures, errors);
    canLoadMore = fresh.length > 0;

    // Sayfanın tamamı süzüldüyse kullanıcı kaydırmadan sonrakini getir.
    if (!batch.length && canLoadMore && emptyStreak < 3) {
      emptyStreak++; page++;
      return load(gen);
    }
    emptyStreak = 0;
    state.loading = false; onChange();
  }

  return {
    state,
    get canLoadMore() { return canLoadMore; },
    refresh() {
      generation++; page = 1; seen = new Set(); canLoadMore = true; emptyStreak = 0;
      Object.assign(state, { videos: [], failures: {}, alternates: new Map(), hiddenDuplicates: 0, hiddenWatched: 0 });
      dedupe = new DuplicateFilter(store.settings.dedupeLevel);
      return load(generation);
    },
    loadMore() {
      if (!canLoadMore || state.loading) return Promise.resolve();
      page++;
      return load(generation);
    },
  };
}
