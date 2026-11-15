// Yinelenen video filtresi (Swift çekirdeğindeki DuplicateFilter ile aynı kurallar).
import { asciiFold, wordTokens } from './text.js';

export const DEDUPE_LEVELS = [
  { id: 0, title: 'Kapalı', detail: 'Aynı video farklı sitelerden tekrar tekrar görünebilir.' },
  { id: 1, title: 'Normal', detail: 'Başlığı neredeyse aynı ve süresi tutan videolar tek kart olur.' },
  { id: 2, title: 'Sıkı', detail: 'Başlığı kısmen benzeyen ve süresi tutan videolar da birleştirilir (nadiren farklı videoları da birleştirebilir).' },
];

const NOISE = new Set(['hd', 'fhd', 'uhd', '4k', '2k', '1080p', '720p', '480p', '360p', '60fps', 'full', 'video', 'videos', 'clip',
  'porn', 'porno', 'porna', 'sex', 'seks', 'sikis', 'xxx', 'izle', 'seyret', 'film', 'filmi', 'free', 'new',
  'the', 'a', 'an', 'and', 'of', 'in', 'on', 'with', 'to', 'for', 'her', 'his', 'by', 'at', 'is',
  've', 'ile', 'bir', 'bu', 'icin', 'com', 'www']);

/** Sadeleştirilmiş başlık kelimeleri + süre. */
export function signature(title, duration = 0) {
  const tokens = new Set(wordTokens(asciiFold(title)).filter((w) => !NOISE.has(w) && (w.length > 1 || /\d/.test(w))));
  const d = Math.max(0, duration | 0);
  const key = [...tokens].sort().join(' ');
  return { tokens, key, duration: d, historyKey: `${key}|${d > 0 ? Math.floor((d + 2) / 5) : 0}` };
}

export class DuplicateFilter {
  constructor(level = 1) {
    this.level = level;
    this.kept = [];               // { video, sig }
    this.byKey = new Map();       // key -> [index]
    this.byDuration = new Map();  // saniye -> [index]
    this.hiddenCount = 0;
    this.alternates = new Map();  // tutulan video kimliği -> [kopyalar]
  }

  tolerance(a, b) {
    const longer = Math.max(a, b);
    return this.level === 2 ? Math.max(5, Math.floor(longer * 0.03)) : Math.max(2, Math.floor(longer * 0.01));
  }

  isSame(a, b) {
    if (this.level === 0 || !a.tokens.size || !b.tokens.size) return false;
    const bothTimed = a.duration > 0 && b.duration > 0;
    const diff = Math.abs(a.duration - b.duration);
    let shared = 0;
    for (const t of a.tokens) if (b.tokens.has(t)) shared++;
    const jaccard = shared / (a.tokens.size + b.tokens.size - shared);

    if (a.key === b.key) {
      if (bothTimed) return diff <= this.tolerance(a.duration, b.duration);
      // Süre bilinmiyorsa yalnızca yeterince ayırt edici başlıklar eşleşir.
      return a.tokens.size >= (this.level === 2 ? 2 : 3);
    }
    if (!bothTimed || diff > this.tolerance(a.duration, b.duration) || shared < 2) return false;
    if (jaccard >= (this.level === 2 ? 0.5 : 0.75)) return true;
    return this.level === 2 && diff <= 1 && a.duration >= 120 && jaccard >= 0.3;
  }

  candidates(sig) {
    const out = new Set(this.byKey.get(sig.key) || []);
    if (sig.duration > 0) {
      const tol = this.tolerance(sig.duration, sig.duration) + 2;
      for (let d = Math.max(1, sig.duration - tol); d <= sig.duration + tol; d++) {
        for (const i of this.byDuration.get(d) || []) out.add(i);
      }
    }
    return [...out].sort((x, y) => x - y);
  }

  index(i) {
    const { sig } = this.kept[i];
    if (!this.byKey.has(sig.key)) this.byKey.set(sig.key, []);
    this.byKey.get(sig.key).push(i);
    if (sig.duration > 0) {
      if (!this.byDuration.has(sig.duration)) this.byDuration.set(sig.duration, []);
      this.byDuration.get(sig.duration).push(i);
    }
  }

  unindex(i) {
    const { sig } = this.kept[i];
    const drop = (map, k) => { const l = map.get(k); if (l) map.set(k, l.filter((x) => x !== i)); };
    drop(this.byKey, sig.key);
    if (sig.duration > 0) drop(this.byDuration, sig.duration);
  }

  /**
   * Yeni bir sonuç grubunu süzer. Daha önce gösterilenlerle ya da grubun kendi içinde yinelenenler
   * gizlenir; grup içindeki kopyalardan prefer(a, b) true dönen (a) tutulur.
   */
  admit(batch, prefer = () => false) {
    if (this.level === 0) return batch.slice();
    const start = this.kept.length;
    for (const video of batch) {
      const sig = signature(video.title, video.durationSec);
      const i = this.candidates(sig).find((c) => this.isSame(this.kept[c].sig, sig));
      if (i === undefined) {
        this.kept.push({ video, sig });
        this.index(this.kept.length - 1);
        continue;
      }
      this.hiddenCount++;
      const existing = this.kept[i].video;
      if (i >= start && prefer(video, existing)) {
        this.unindex(i);
        this.kept[i] = { video, sig };
        this.index(i);
        const moved = this.alternates.get(existing.id) || [];
        this.alternates.delete(existing.id);
        this.alternates.set(video.id, moved.concat([existing]));
      } else {
        this.alternates.set(existing.id, (this.alternates.get(existing.id) || []).concat([video]));
      }
    }
    return this.kept.slice(start).map((e) => e.video);
  }
}
