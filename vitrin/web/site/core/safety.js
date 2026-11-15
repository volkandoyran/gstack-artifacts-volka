// Reşit olmayanları çağrıştıran (ve hayvan içeren) içerikleri her zaman eler.
// Ayarlardan kapatılamaz. Hem sonuçlara hem arama terimlerine uygulanır.
import { asciiFold } from './text.js';

// Desenler ASCII'ye sadeleştirilmiş metne uygulanır (ç->c, ş->s, ı->i …).
const ALWAYS = [
  /\b(loli|lolicon|lolita|shota|shotacon|underage|under[- ]?age|preteen|pre[- ]teen|jailbait|toddler|child|children|kids?|minors?|little girl|young girl|pedo\w*)\b/,
  /\b(1[0-7]|[1-9])\s*(yo|y\.?o\.?|yrs?\s*old|years?\s*old)\b/,
  /\b(cocuk\w*|kucuk kiz\w*|kucuk yas\w*|yasi kucuk|resit olmayan|liseli\w*|lise|ortaokul\w*|ilkokul\w*|ergen\w*|yeniyetme\w*)\b/,
  /\b(1[0-7]|[1-9])\s*yas\w*/,
  /\b(bestiality|zoophil\w*|zoo ?porn|hayvanla)\b/,
];
// Çizim içerikte okul teması çoğunlukla reşit olmayan karakter demektir.
const HENTAI_ONLY = [/\b(school ?girl\w*|school ?boy\w*|high ?school\w*|middle ?school\w*|okullu\w*)\b/];

export function isBlocked(text, kind) {
  const t = asciiFold(text);
  return (kind === 'hentai' ? ALWAYS.concat(HENTAI_ONLY) : ALWAYS).some((re) => re.test(t));
}

export function isAllowed(video) {
  return !isBlocked(video.title, video.kind) && !(video.tags || []).some((t) => isBlocked(t, video.kind));
}

export function sanitize(terms) {
  return terms.filter((t) => !isBlocked(t, 'hentai'));
}
