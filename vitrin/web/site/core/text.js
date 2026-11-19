// Metin yardımcıları (Swift çekirdeğindeki TextUtil / Fmt ile aynı davranış).

const TR_MAP = { 'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', 'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c' };

/** Karşılaştırma için sadeleştirme: küçük harf, Türkçe karakterler ve aksanlar ASCII'ye. */
export function asciiFold(s) {
  return String(s)
    .replace(/[İIıŞşĞğÜüÖöÇç]/g, (c) => TR_MAP[c])
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase();
}

/** Harf/rakam dışındaki her şeyi ayırıcı sayarak kelimelere böler. */
export function wordTokens(s) {
  return String(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

const NAMED = { '&quot;': '"', '&apos;': "'", '&lt;': '<', '&gt;': '>', '&nbsp;': ' ', '&hellip;': '…', '&ndash;': '–', '&mdash;': '—', '&amp;': '&' };

export function htmlDecode(s) {
  if (!String(s).includes('&')) return String(s);
  return String(s)
    .replace(/&#(x?)([0-9a-f]+);/gi, (m, hex, code) => {
      const n = parseInt(code, hex ? 16 : 10);
      return Number.isFinite(n) && n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : m;
    })
    .replace(/&(quot|apos|lt|gt|nbsp|hellip|ndash|mdash|amp);/g, (m) => NAMED[m]);
}

export function stripTags(s) {
  return htmlDecode(String(s).replace(/<[^>]+>/g, ' '));
}

/** "12:34" veya "1:02:03" -> saniye */
export function secondsFromClock(s) {
  if (!s) return 0;
  return String(s).split(':').map((p) => parseInt(p, 10)).filter((n) => !Number.isNaN(n)).reduce((a, n) => a * 60 + n, 0);
}

/** "12 min", "1 h 5 min", "6min", "45 sec" -> saniye */
export function secondsFromLoose(s) {
  let total = 0;
  for (const m of String(s).toLowerCase().matchAll(/(\d+)\s*(h|min|sec)/g)) {
    const n = parseInt(m[1], 10);
    total += m[2] === 'h' ? n * 3600 : m[2] === 'min' ? n * 60 : n;
  }
  return total;
}

/** "7M", "876.1k", "18,093" -> sayı */
export function countFromCompact(s) {
  const m = /([\d.,]+)\s*([kKmMbB])?/.exec(String(s));
  if (!m) return 0;
  const suffix = (m[2] || '').toLowerCase();
  const num = suffix ? m[1].replace(',', '.') : m[1].replace(/[.,]/g, '');
  const v = parseFloat(num) || 0;
  return Math.trunc(v * ({ k: 1e3, m: 1e6, b: 1e9 }[suffix] || 1));
}

export function clock(sec) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export function compact(n) {
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'B'; // B = bin
  return String(n);
}

/** "2026-11-13 22:22:15" ya da "2026-11-14T10:10:22" (UTC) -> ms */
export function parseUTC(s) {
  if (!s) return null;
  const t = Date.parse(String(s).slice(0, 19).replace(' ', 'T') + 'Z');
  return Number.isNaN(t) ? null : t;
}
