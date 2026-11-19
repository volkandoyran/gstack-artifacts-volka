// Cihazda (yalnızca bu tarayıcıda) saklanan ayarlar, izleme geçmişi ve favoriler.
import { signature } from './dedupe.js';

export function createStore(storage) {
  const read = (key, fallback) => {
    try { const raw = storage.getItem(key); return raw == null ? fallback : JSON.parse(raw); } catch { return fallback; }
  };
  const write = (key, value) => { try { storage.setItem(key, JSON.stringify(value)); } catch { /* dolu / kapalı */ } };

  const DEFAULTS = { ageConfirmed: false, dedupeLevel: 1, hideWatched: false, disabled: [], customSites: [], relayURL: '', unguarded: [] };
  const HISTORY_LIMIT = 4000, FAVORITE_LIMIT = 500;

  let history = read('vitrin.history', []);
  let historySet = new Set(history);
  const keysFor = (v) => {
    const sig = signature(v.title, v.durationSec);
    return sig.tokens.size >= 2 ? [`id:${v.id}`, `sig:${sig.historyKey}`] : [`id:${v.id}`];
  };

  return {
    get settings() { return { ...DEFAULTS, ...read('vitrin.settings', {}) }; },
    update(patch) { write('vitrin.settings', { ...this.settings, ...patch }); },

    // İzleme geçmişi: aynı video başka siteden gelse de tanınır.
    markWatched(v) {
      for (const k of keysFor(v)) if (!historySet.has(k)) { historySet.add(k); history.push(k); }
      if (history.length > HISTORY_LIMIT) { history = history.slice(-HISTORY_LIMIT); historySet = new Set(history); }
      write('vitrin.history', history);
    },
    isWatched(v) { return keysFor(v).some((k) => historySet.has(k)); },
    get watchedCount() { return history.filter((k) => k.startsWith('id:')).length; },
    clearHistory() { history = []; historySet = new Set(); write('vitrin.history', []); },

    // Favoriler: videonun kendisi saklanır (liste çevrimdışı da görünsün diye).
    get favorites() { return read('vitrin.favorites', []); },
    isFavorite(v) { return this.favorites.some((f) => f.id === v.id); },
    toggleFavorite(v) {
      const list = this.favorites;
      const i = list.findIndex((f) => f.id === v.id);
      if (i >= 0) list.splice(i, 1); else list.unshift(v);
      write('vitrin.favorites', list.slice(0, FAVORITE_LIMIT));
      return i < 0;
    },
  };
}
