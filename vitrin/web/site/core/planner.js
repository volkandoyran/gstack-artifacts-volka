// Arama planı, birleştirme ve sıralama (Swift çekirdeğindeki SearchPlanner ile aynı).

/** Seçimlere göre hangi siteye hangi sorgunun gideceğini belirler. */
export function planJobs({ providers, selected, free, combine, sort, page }) {
  const jobs = [];
  for (const provider of providers) {
    const tr = provider.lang === 'tr';
    const extra = tr ? free.tr : free.en;
    const terms = selected.map((c) => (tr ? c.termTR : c.term));
    const sets = !terms.length ? [extra] : combine === 'all' ? [terms.concat(extra)] : terms.map((t) => [t].concat(extra));
    for (const set of sets) jobs.push({ provider, query: { terms: set, sort, page } });
  }
  return jobs;
}

/** Her kaynaktan sırayla bir video alarak karıştırır. */
export function interleave(buckets) {
  const merged = [];
  const longest = Math.max(0, ...buckets.map((b) => b.length));
  for (let i = 0; i < longest; i++) for (const b of buckets) if (i < b.length) merged.push(b[i]);
  return merged;
}

export function sortVideos(list, sort) {
  const by = {
    newest: (a, b) => (b.addedAt || 0) - (a.addedAt || 0),
    mostViewed: (a, b) => b.views - a.views,
    topRated: (a, b) => b.rating - a.rating,
    longest: (a, b) => b.durationSec - a.durationSec,
    shortest: (a, b) => (a.durationSec || Infinity) - (b.durationSec || Infinity),   // süresi bilinmeyen sona
  }[sort];
  return by ? list.slice().sort(by) : list;
}

/** Aynı videonun iki kopyasından hangisi gösterilsin? Daha yüksek çözünürlük, sonra daha çok izlenen. */
export function prefer(a, b) {
  const ha = a.maxHeight || 0, hb = b.maxHeight || 0;
  return ha !== hb ? ha > hb : a.views > b.views;
}
