// Web sürümünün çekirdek testleri:  node --test tests/*.test.mjs
// Gerçek site yanıtlarıyla denemek için: VITRIN_SAMPLES=/klasör node --test tests/*.test.mjs*.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

import { asciiFold, htmlDecode, secondsFromLoose, secondsFromClock, countFromCompact, stripTags, wordTokens } from '../site/core/text.js';
import { isBlocked, isAllowed, sanitize } from '../site/core/safety.js';
import { DuplicateFilter, signature } from '../site/core/dedupe.js';
import { bilingual, CATEGORIES } from '../site/core/catalog.js';
import { planJobs, interleave, sortVideos } from '../site/core/planner.js';
import { eporner, pornhub, redtube, xvideos, xnxx, parseXSearch, parseWordPress, findPlayer, wordpress, customSite, DOEDA, DOEDA_ONE, builtInProviders } from '../site/core/providers.js';
import { createNet, RelayNeededError, describeError } from '../site/core/net.js';
import { createStore } from '../site/core/store.js';
import { createBrowser } from '../site/core/browse.js';

const v = (providerID, remoteID, title, durationSec = 0, extra = {}) =>
  ({ id: `${providerID}:${remoteID}`, providerID, remoteID, kind: 'real', title, durationSec, views: 0, rating: 0, tags: [], ...extra });

function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, val) => m.set(k, String(val)), removeItem: (k) => m.delete(k) };
}

test('metin yardımcıları', () => {
  assert.equal(asciiFold('Sarışın ÇİFT Öğle'), 'sarisin cift ogle');
  assert.equal(htmlDecode('Tom &amp; Jerry&#8217;s &#x41;'), 'Tom & Jerry’s A');
  assert.deepEqual(wordTokens(stripTags('<b>a</b>&nbsp;b')), ['a', 'b']);
  assert.equal(secondsFromLoose('1 h 5 min'), 3900);
  assert.equal(secondsFromLoose('6min'), 360);
  assert.equal(secondsFromClock('1:02:03'), 3723);
  assert.equal(countFromCompact('876.1k'), 876100);
  assert.equal(countFromCompact('18,093'), 18093);
  assert.equal(countFromCompact('7M'), 7000000);
});

test('güvenlik filtresi iki dilde reşit olmayanları eler', () => {
  for (const bad of ['cute loli', 'Shota adventure', 'she is 16 years old', '17yo girl', 'Liseli kız', 'çocuk', '16 yaşında', 'Reşit olmayan', 'ergen']) {
    assert.ok(isBlocked(bad), bad);
  }
  for (const ok of ['18 yaşındaki genç kadın', '18 years old', 'childhood friend', 'Üniversiteli', '19yo', 'liselotte', 'kidnapped']) {
    assert.ok(!isBlocked(ok), ok);
  }
  assert.ok(isBlocked('school girl', 'hentai') && !isBlocked('school girl', 'real'));
  assert.ok(!isAllowed(v('x', '1', 'Fine title', 0, { tags: ['blonde', 'liseli'] })));
  assert.deepEqual(sanitize(['blonde', 'loli', 'masaj']), ['blonde', 'masaj']);
});

test('yinelenen filtresi: siteler arası aynı video tek kart olur', () => {
  const f = new DuplicateFilter(1);
  const out = f.admit([
    v('eporner', '1', 'Relaxing Massage Turns Into Something More', 725),
    v('pornhub', '2', 'Relaxing massage turns into something more - HD', 726),
    v('redtube', '3', 'RELAXING MASSAGE TURNS INTO SOMETHING MORE (Full Video)', 724),
    v('xvideos', '4', 'Completely different title here', 725),
  ]);
  assert.deepEqual(out.map((x) => x.id), ['eporner:1', 'xvideos:4']);
  assert.equal(f.hiddenCount, 2);
  assert.deepEqual(f.alternates.get('eporner:1').map((x) => x.id), ['pornhub:2', 'redtube:3']);
});

test('yinelenen filtresi: farklı süre / bölüm / genel başlık ayrı kalır; sıkı mod daha fazlasını yakalar', () => {
  const f = new DuplicateFilter(1);
  assert.equal(f.admit([
    v('a', '1', 'Hot blonde massage', 600), v('b', '2', 'Hot blonde massage', 1900),
    v('c', '3', 'Office story part 1', 900), v('c', '4', 'Office story part 2', 900),
    v('wp', '5', 'Masaj'), v('wp2', '6', 'Masaj'),
    v('wp', '7', 'Masaj Salonunda Tanıştığı Kadınla Eve Gitti'), v('wp2', '8', 'Masaj salonunda tanistigi kadinla eve gitti!'),
  ]).length, 7);
  const a = v('eporner', '1', 'Blonde neighbor gets a deep massage on the couch', 1291);
  const b = v('xnxx', '2', 'Neighbor massage on couch - blonde amateur', 1290);
  assert.equal(new DuplicateFilter(1).admit([a, b]).length, 2);
  assert.equal(new DuplicateFilter(2).admit([a, b]).length, 1);
  assert.equal(new DuplicateFilter(0).admit([a, a]).length, 2);
  assert.equal(signature('Sarışın & Esmer — FULL HD 1080p Video', 61).historyKey, 'esmer sarisin|12');
});

test('yinelenen filtresi: aynı grupta daha iyi kopya tutulur, ekrandaki kart değişmez', () => {
  const f = new DuplicateFilter(1);
  const prefer = (x, y) => (x.maxHeight || 0) > (y.maxHeight || 0);
  const first = f.admit([v('pornhub', '1', 'Sunny afternoon by the pool', 800), v('xvideos', '2', 'Sunny afternoon by the pool', 800, { maxHeight: 1080 })], prefer);
  assert.deepEqual(first.map((x) => x.id), ['xvideos:2']);
  assert.equal(f.admit([v('xnxx', '3', 'Sunny afternoon by the pool', 801, { maxHeight: 2160 })], prefer).length, 0);
  assert.deepEqual(f.alternates.get('xvideos:2').map((x) => x.id), ['pornhub:1', 'xnxx:3']);
});

test('çeviri sözlüğü her siteye kendi dilinde terim verir', () => {
  assert.deepEqual(bilingual('Sarışın olgun masaj'), { en: ['blonde', 'milf', 'massage'], tr: ['sarışın', 'olgun', 'masaj'] });
  assert.deepEqual(bilingual('big tits blonde'), { en: ['big tits', 'blonde'], tr: ['büyük göğüs', 'sarışın'] });
  assert.deepEqual(bilingual('ev yapımı brazzers'), { en: ['homemade', 'brazzers'], tr: ['ev yapımı', 'brazzers'] });
});

test('arama planı: VE/VEYA, dil ve tür ayrımı', () => {
  const cat = (id) => CATEGORIES.find((c) => c.id === id);
  const providers = [eporner, wordpress(DOEDA)];
  const and = planJobs({ providers, kindFilter: 'real', selected: [cat('r-blonde'), cat('r-massage')], free: bilingual('ofis'), combine: 'all', sort: 'newest', page: 1 });
  assert.deepEqual(and.map((j) => j.query.terms), [['blonde', 'massage', 'office'], ['sarışın', 'masaj', 'ofis']]);
  const or = planJobs({ providers: [eporner], kindFilter: 'all', selected: [cat('r-blonde'), cat('r-massage')], free: { en: [], tr: [] }, combine: 'any', sort: 'relevance', page: 2 });
  assert.deepEqual(or.map((j) => j.query.terms), [['blonde'], ['massage']]);
  const mixed = planJobs({ providers, kindFilter: 'all', selected: [cat('r-blonde'), cat('h-elf')], free: { en: [], tr: [] }, combine: 'all', sort: 'relevance', page: 1 });
  assert.deepEqual(mixed.map((j) => `${j.provider.id}|${j.query.kind}|${j.query.terms}`),
    ['eporner|real|blonde', 'wp-doeda.com|real|sarışın', 'eporner|hentai|elf', 'wp-doeda.com|hentai|elf']);
  assert.deepEqual(interleave([[1, 2], [3], []]), [1, 3, 2]);
  assert.deepEqual(sortVideos([v('a', '1', 'x', 100), v('a', '2', 'y', 0), v('a', '3', 'z', 50)], 'shortest').map((x) => x.remoteID), ['3', '1', '2']);
});

test('kaynak ayrıştırıcıları (gerçek yanıt biçimlerinden örnekler)', () => {
  const ep = eporner.parse({ videos: [{ id: '27zf', title: 'Sample Clip', keywords: 'blonde, massage', views: 285, rate: '4.50',
    url: 'https://www.eporner.com/video-27zf/x/', added: '2026-11-13 22:22:15', length_sec: 1291,
    embed: 'https://www.eporner.com/embed/27zf/', default_thumb: { src: 'https://cdn/7_360.jpg' } }] }, 'real')[0];
  assert.equal(ep.id, 'eporner:27zf');
  assert.equal(ep.rating, 90);
  assert.deepEqual(ep.tags, ['blonde', 'massage']);
  assert.ok(ep.addedAt > 0);

  const ph = pornhub.parse({ videos: [{ duration: '3:01', views: 40, video_id: '6aef', rating: 100, title: 'Sample', url: 'https://www.pornhub.com/view_video.php?viewkey=6aef',
    default_thumb: 'https://pix/x.jpg', publish_date: '2026-11-15 14:00:05', tags: [{ tag_name: 'pov' }] }] }, 'real')[0];
  assert.equal(ph.durationSec, 181);
  assert.equal(ph.embedURL, 'https://www.pornhub.com/embed/6aef');

  const rt = redtube.parse({ videos: [{ video: { duration: '0:21', views: 7, video_id: '309', rating: 0, title: 'Sample', url: 'https://www.redtube.com/309',
    embed_url: 'https://embed.redtube.com/?id=309', default_thumb: 'https://ei/(m=e)(mh=1)9.jpg', tags: [] } }] }, 'real')[0];
  assert.equal(rt.id, 'redtube:309');
  assert.equal(rt.embedURL, 'https://embed.redtube.com/?id=309');

  const xhtml = `<div id="video_ufim" data-id="83000781" data-eid="ufimdcde2e5" class="thumb-block"><div class="thumb"><a href="/video.ufimdcde2e5/sample"><img src="https://x/lightbox-blank.gif" data-src="https://thumb/xv_29_t.jpg"><span class="video-hd-mark">1080p</span></a></div><p class="title"><a href="/video.ufimdcde2e5/sample" title="Sample &amp; session">Sample <span class="duration">12 min</span></a></p><p class="metadata"><span class="duration">12 min</span><span> - </span> 7M <span class="sprfluous">Views</span></p></div>`;
  const xv = parseXSearch(xhtml, { id: 'xvideos', host: 'www.xvideos.com' }, 'real')[0];
  assert.equal(xv.title, 'Sample & session');
  assert.equal(xv.durationSec, 720);
  assert.equal(xv.views, 7000000);
  assert.equal(xv.maxHeight, 1080);
  assert.equal(xv.thumbnail, 'https://thumb/xv_29_t.jpg');
  assert.equal(xv.pageURL, 'https://www.xvideos.com/video.ufimdcde2e5/sample');
  assert.equal(xv.embedURL, 'https://www.xvideos.com/embedframe/ufimdcde2e5');

  assert.equal(xvideos.searchURL('blonde massage', 1, 'newest'), 'https://www.xvideos.com/?k=blonde+massage&p=0&sort=uploaddate');
  assert.equal(xnxx.searchURL('blonde massage', 3), 'https://www.xnxx.com/search/blonde+massage/2');
  assert.equal(xnxx.searchURL('', 1), null);

  const wp = parseWordPress([{ id: 65392, date_gmt: '2026-11-14T10:10:22', link: 'http://www.doeda.com/ornek/', title: { rendered: 'Masaj &#8211; Örnek' },
    views: '131', class_list: ['post-1', 'category-18-yas-x', 'category-masaj-1', 'tag-hd'],
    _embedded: { 'wp:featuredmedia': [{ source_url: 'http://www.doeda.com/a.jpeg', media_details: { sizes: { medium: { source_url: 'http://www.doeda.com/a-300.jpeg' } } } }] } },
    { id: 7, link: 'https://x/b/', title: { rendered: 'Görselsiz' }, _embedded: { 'wp:featuredmedia': [{ code: 'rest_post_invalid_id' }] } }], DOEDA, 'real');
  assert.equal(wp[0].title, 'Masaj – Örnek');
  assert.equal(wp[0].views, 131);
  assert.equal(wp[0].thumbnail, 'http://www.doeda.com/a.jpeg');
  assert.deepEqual(wp[0].tags, ['18 yas', 'masaj', 'hd']);
  assert.equal(wp[1].thumbnail, null);

  const page = 'http://www.doeda.com/ornek/';
  assert.deepEqual(findPlayer('<iframe src="https://ads.exoclick.com/b.html"></iframe><iframe src="https://www.canlitvnews3.xyz/player/play.php?vid=abc123"></iframe>', page),
    { embed: 'https://www.canlitvnews3.xyz/player/play.php?vid=abc123' });
  assert.deepEqual(findPlayer('<iframe data-src="//player.example.net/e/1"></iframe>', page), { embed: 'https://player.example.net/e/1' });
  assert.deepEqual(findPlayer('<video><source src="https://cdn.example/v.m3u8?a=1&amp;b=2"></video>', page), { video: 'https://cdn.example/v.m3u8?a=1&b=2' });
  assert.equal(findPlayer('<p>yok</p>', page), null);

  assert.equal(customSite('', ' ornek-site.com/ ').baseURL, 'https://ornek-site.com');
  assert.equal(customSite('x', 'bozuk'), null);
  assert.equal(new Set(builtInProviders().map((p) => p.id)).size, 7);
});

test('ağ katmanı: aracı gereken istekler aracıdan geçer, yoksa anlaşılır hata verir', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => { calls.push([url, init.method]); return new Response('{"videos":[]}', { status: 200 }); };
  const direct = createNet({ fetchImpl });
  await assert.rejects(() => pornhub.search({ terms: ['x'], kind: 'real', sort: 'relevance', page: 1 }, direct), RelayNeededError);
  assert.match(describeError(new RelayNeededError()), /aracı/);
  await eporner.search({ terms: ['x'], kind: 'real', sort: 'relevance', page: 1 }, direct);
  assert.ok(calls[0][0].startsWith('https://www.eporner.com/api/v2/video/search/?query=x'));

  const relayed = createNet({ relayBase: 'https://app.example/r', fetchImpl });
  await pornhub.search({ terms: ['x'], kind: 'hentai', sort: 'newest', page: 2 }, relayed);
  const last = calls.at(-1)[0];
  assert.ok(last.startsWith('https://app.example/r?u=https%3A%2F%2Fwww.pornhub.com%2Fwebmasters%2Fsearch%3Fsearch%3Dhentai%2Bx'), last);
  assert.equal(relayed.asset('http://www.doeda.com/a.jpg'), 'https://app.example/r?u=http%3A%2F%2Fwww.doeda.com%2Fa.jpg');
  assert.equal(relayed.asset('https://cdn/a.jpg'), 'https://cdn/a.jpg');
  assert.equal(wordpress(DOEDA).relayForSearch, true);       // http site
  assert.equal(wordpress(DOEDA_ONE).relayForSearch, false);  // https + CORS
});

test('geçmiş ve favoriler cihazda saklanır; aynı video başka sitede de tanınır', () => {
  const storage = memoryStorage();
  const store = createStore(storage);
  const seen = v('eporner', '1', 'Evening walk on the beach', 600);
  assert.equal(store.isWatched(seen), false);
  store.markWatched(seen);
  assert.ok(store.isWatched(v('pornhub', '9', 'Evening Walk On The Beach HD', 601)));
  assert.ok(!store.isWatched(v('pornhub', '8', 'Evening walk on the beach', 1500)));
  assert.equal(createStore(storage).watchedCount, 1);
  assert.equal(store.toggleFavorite(seen), true);
  assert.ok(createStore(storage).isFavorite(seen));
  assert.equal(store.toggleFavorite(seen), false);
  store.update({ dedupeLevel: 2 });
  assert.equal(createStore(storage).settings.dedupeLevel, 2);
  store.clearHistory();
  assert.equal(createStore(storage).isWatched(seen), false);
});

test('arama denetleyicisi: birleştirir, süzer, aracı gerektirenleri atlar', async () => {
  const store = createStore(memoryStorage());
  const fake = (id, relayForSearch, list, lang = 'en') => ({ id, name: id.toUpperCase(), kinds: ['real', 'hentai'], lang, relayForSearch,
    search: async (q) => (q.page === 1 ? list.map((x) => ({ ...x, kind: q.kind })) : []) });
  const a = fake('a', false, [v('a', '1', 'Morning yoga session outdoors', 900), v('a', '2', 'Blocked loli title', 100), v('a', '3', 'Unique clip from a', 300)]);
  const b = fake('b', false, [v('b', '1', 'Morning Yoga Session Outdoors HD', 901), v('b', '2', 'Unique clip from b', 400)]);
  const c = fake('c', true, [v('c', '1', 'Needs relay', 500)]);
  const failing = { ...fake('d', false, []), name: 'D', search: async () => { throw new TypeError('ağ'); } };

  const net = createNet({ fetchImpl: async () => new Response('{}') });
  let changes = 0;
  const browser = createBrowser({ net, store, getProviders: () => [a, b, c, failing], onChange: () => changes++ });
  browser.state.kindFilter = 'real';
  await browser.refresh();
  assert.deepEqual(browser.state.videos.map((x) => x.id), ['a:1', 'b:2', 'a:3']);
  assert.equal(browser.state.hiddenDuplicates, 1);
  assert.deepEqual(browser.state.alternates.get('a:1').map((x) => x.id), ['b:1']);
  assert.deepEqual(browser.state.skippedForRelay, ['C']);
  assert.match(browser.state.failures.D, /Bağlantı kurulamadı/);
  assert.equal(browser.state.loading, false);
  assert.ok(changes >= 2);

  // Aracı gelince c de aranır; izlenenler gizlenir.
  net.relayBase = 'https://app.example/r';
  store.update({ hideWatched: true });
  store.markWatched(v('a', '3', 'Unique clip from a', 300));
  await browser.refresh();
  assert.deepEqual(browser.state.videos.map((x) => x.id).sort(), ['a:1', 'b:2', 'c:1']);
  assert.equal(browser.state.hiddenWatched, 1);
  await browser.loadMore();
  assert.equal(browser.canLoadMore, false);
});

// ---------------------------------------------------------------- gerçek örnekler (isteğe bağlı)

const samples = process.env.VITRIN_SAMPLES;
const sample = (name) => (samples && existsSync(path.join(samples, name)) ? readFileSync(path.join(samples, name), 'utf8') : null);

test('gerçek site yanıtları (VITRIN_SAMPLES verilirse)', { skip: !samples }, () => {
  const check = (list, min, needDuration = true) => {
    assert.ok(list.length >= min, `en az ${min} video (${list.length})`);
    assert.equal(new Set(list.map((x) => x.id)).size, list.length);
    for (const x of list) { assert.ok(x.title && !x.title.includes('&amp;')); assert.ok(x.pageURL); }
    if (needDuration) assert.ok(list.filter((x) => x.durationSec > 0).length >= list.length * 0.9);
    assert.ok(list.filter((x) => x.thumbnail).length >= list.length * 0.9);
  };
  const ph = pornhub.parse(JSON.parse(sample('pornhub.json')), 'real'); check(ph, 20);
  const rt = redtube.parse(JSON.parse(sample('redtube.json')), 'real'); check(rt, 15);
  const xv = parseXSearch(sample('xvideos_search.html'), { id: 'xvideos', host: 'www.xvideos.com' }, 'real'); check(xv, 20);
  const xn = parseXSearch(sample('xnxx_search.html'), { id: 'xnxx', host: 'www.xnxx.com' }, 'real'); check(xn, 20);
  check(parseWordPress(JSON.parse(sample('wp_doeda_com.json')), DOEDA, 'real'), 2, false);
  check(parseWordPress(JSON.parse(sample('wp_doeda_one.json')), DOEDA_ONE, 'real'), 1, false);
  assert.match(findPlayer(sample('doeda_page.html'), 'http://www.doeda.com/x/').embed, /play\.php\?vid=[0-9a-f]{32}$/);

  const all = [...ph, ...rt, ...xv, ...xn].filter(isAllowed);
  const normal = new DuplicateFilter(1).admit(all), strict = new DuplicateFilter(2).admit(all);
  console.log(`  gerçek karışım: ${all.length} video → normal ${normal.length}, sıkı ${strict.length}`);
  assert.ok(strict.length <= normal.length && normal.length > all.length * 0.75);
});
