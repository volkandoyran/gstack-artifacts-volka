// Kategoriler, sıralama ölçütleri ve TR <-> EN etiket sözlüğü.
import { asciiFold, wordTokens } from './text.js';

const r = (title, en, tr) => ({ id: `r-${en}`, title, term: en, termTR: tr ?? title.toLowerCase(), kind: 'real' });
const h = (title, en, tr) => ({ id: `h-${en}`, title, term: en, termTR: tr ?? title.toLowerCase(), kind: 'hentai' });

export const CATEGORIES = [
  r('Türk', 'turkish', 'türk'), r('Türkçe altyazılı', 'turkish subtitles', 'türkçe altyazılı'),
  r('Amatör', 'amateur', 'amatör'), r('Ev yapımı', 'homemade', 'ev yapımı'),
  r('Sarışın', 'blonde', 'sarışın'), r('Esmer', 'brunette', 'esmer'), r('Kızıl', 'redhead', 'kızıl'),
  r('Olgun', 'milf', 'olgun'), r('Asyalı', 'asian', 'asyalı'), r('Japon', 'japanese', 'japon'),
  r('Latin', 'latina', 'latin'), r('Siyahi', 'ebony', 'zenci'), r('Lezbiyen', 'lesbian', 'lezbiyen'),
  r('Üçlü', 'threesome', 'grup'), r('POV', 'pov', 'pov'), r('Anal', 'anal', 'anal'),
  r('Oral', 'blowjob', 'oral'), r('Büyük göğüs', 'big tits', 'büyük memeli'), r('Masaj', 'massage', 'masaj'),
  r('Dış mekan', 'outdoor', 'dışarıda'), r('Çift', 'couple', 'çift'), r('Romantik', 'romantic', 'romantik'),
  r('Sert', 'rough', 'sert'), r('Solo', 'solo', 'mastürbasyon'), r('Konulu', 'story', 'konulu'),
  r('4K', '4k', 'full hd'),
  h('Sansürsüz', 'uncensored', 'sansürsüz'), h('Vanilla', 'vanilla', 'vanilla'),
  h('Romantik', 'romance', 'romantik'), h('Komedi', 'comedy', 'komedi'),
  h('Fantastik', 'fantasy', 'fantastik'), h('Büyük göğüs', 'big boobs', 'büyük memeli'),
  h('Olgun', 'milf', 'olgun'), h('Hizmetçi', 'maid', 'hizmetçi'), h('Hemşire', 'nurse', 'hemşire'),
  h('Elf', 'elf', 'elf'), h('Harem', 'harem', 'harem'), h('Yuri', 'yuri', 'yuri'),
  h('Dokunaç', 'tentacle', 'tentacle'), h('Ahegao', 'ahegao', 'ahegao'), h('NTR', 'ntr', 'ntr'),
  h('3D', '3d', '3d'), h('Canavar kız', 'monster girl', 'canavar'), h('Bikini', 'swimsuit', 'bikini'),
];

export const SORTS = [
  { id: 'relevance', title: 'İlgili' }, { id: 'newest', title: 'En yeni' },
  { id: 'mostViewed', title: 'En çok izlenen' }, { id: 'topRated', title: 'En yüksek puan' },
  { id: 'longest', title: 'En uzun' }, { id: 'shortest', title: 'En kısa' },
];

// (Türkçe, İngilizce)
const PAIRS = [
  ['türkçe altyazılı', 'turkish subtitles'], ['büyük göğüs', 'big tits'], ['büyük memeli', 'big tits'],
  ['ev yapımı', 'homemade'], ['dış mekan', 'outdoor'], ['gizli çekim', 'hidden cam'],
  ['canavar kız', 'monster girl'], ['üvey anne', 'stepmom'], ['üvey kardeş', 'stepsister'],
  ['sarışın', 'blonde'], ['esmer', 'brunette'], ['kızıl', 'redhead'], ['olgun', 'milf'],
  ['amatör', 'amateur'], ['türk', 'turkish'], ['asyalı', 'asian'], ['japon', 'japanese'],
  ['koreli', 'korean'], ['rus', 'russian'], ['latin', 'latina'], ['zenci', 'ebony'], ['siyahi', 'ebony'],
  ['lezbiyen', 'lesbian'], ['üçlü', 'threesome'], ['grup', 'group'], ['masaj', 'massage'],
  ['çift', 'couple'], ['romantik', 'romantic'], ['sert', 'rough'], ['oral', 'blowjob'],
  ['hemşire', 'nurse'], ['hizmetçi', 'maid'], ['dokunaç', 'tentacle'], ['sansürsüz', 'uncensored'],
  ['komedi', 'comedy'], ['fantastik', 'fantasy'], ['sekreter', 'secretary'], ['öğretmen', 'teacher'],
  ['duş', 'shower'], ['plaj', 'beach'], ['dövmeli', 'tattoo'], ['şişman', 'bbw'], ['tombul', 'chubby'],
  ['zayıf', 'skinny'], ['dışarıda', 'outdoor'], ['ofis', 'office'], ['konulu', 'story'],
  ['aldatma', 'cheating'], ['altyazılı', 'subtitles'], ['mastürbasyon', 'masturbation'],
  ['evli', 'married'], ['komşu', 'neighbor'], ['patron', 'boss'], ['doktor', 'doctor'],
];

const trToEn = new Map(), enToTr = new Map();
let maxWords = 1;
for (const [tr, en] of PAIRS) {
  const ft = asciiFold(tr), fe = asciiFold(en);
  if (!trToEn.has(ft)) trToEn.set(ft, en);
  if (!enToTr.has(fe)) enToTr.set(fe, tr);
  maxWords = Math.max(maxWords, wordTokens(ft).length, wordTokens(fe).length);
}

/** Serbest metni iki dile çevirir; sözlükte olmayan kelimeler iki listeye de olduğu gibi girer. */
export function bilingual(text) {
  const original = wordTokens(String(text).toLowerCase());
  const folded = original.map(asciiFold);
  const en = [], tr = [];
  for (let i = 0; i < folded.length;) {
    let matched = false;
    for (let n = Math.min(maxWords, folded.length - i); n >= 1; n--) {
      const phrase = folded.slice(i, i + n).join(' ');
      const typed = original.slice(i, i + n).join(' ');
      if (trToEn.has(phrase)) { en.push(trToEn.get(phrase)); tr.push(typed); }
      else if (enToTr.has(phrase)) { en.push(typed); tr.push(enToTr.get(phrase)); }
      else continue;
      i += n; matched = true; break;
    }
    if (!matched) { en.push(original[i]); tr.push(original[i]); i++; }
  }
  return { en, tr };
}
