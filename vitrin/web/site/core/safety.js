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
export function isBlocked(text) {
  const t = asciiFold(text);
  return ALWAYS.some((re) => re.test(t));
}

export function isAllowed(video) {
  return !isBlocked(video.title) && !(video.tags || []).some(isBlocked);
}

export function sanitize(terms) {
  return terms.filter((t) => !isBlocked(t) && !isAnimated(t));
}

// Uygulama yalnızca gerçek (çizim olmayan) videoları gösterir: hentai / animasyon / çizgi
// etiketli sonuçlar gerçek video sitelerinden gelse bile listeden çıkarılır.
const ANIMATED = /\b(hentai\w*|anime|animated|animation|cartoons?|toons?|manga|doujin\w*|animasyon\w*|cizgi film\w*|cizgi)\b/;

export function isAnimated(textOrVideo) {
  if (typeof textOrVideo === 'string') return ANIMATED.test(asciiFold(textOrVideo));
  return isAnimated(textOrVideo.title) || (textOrVideo.tags || []).some((t) => isAnimated(t));
}
