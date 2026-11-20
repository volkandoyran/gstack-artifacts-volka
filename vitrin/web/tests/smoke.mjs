// Uçtan uca deneme: uygulamayı gerçek bir tarayıcıda (Chromium, iPhone boyutunda) açar.
// Siteler yerine SAHTE, nötr veriler kullanılır; hiçbir gerçek siteye istek gitmez.
// Aracı kodu (relay/worker.js) aynen çalışır; yalnızca "dış dünya" sahtedir.
//   node tests/smoke.mjs [ekran görüntüsü klasörü]
import http from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import worker, { relay, imageProxy } from '../relay/worker.js';

// Playwright hem yerel node_modules'tan hem de genel kurulumdan (NODE_PATH) yüklenebilsin.
const { chromium } = createRequire(import.meta.url)('playwright');

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'site');
const shots = process.argv[2] || null;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };

// ---------------------------------------------------------------- sahte veriler (başlıklar nötr)

const thumb = (label, hue) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180"><rect width="320" height="180" fill="hsl(${hue} 45% 32%)"/><text x="160" y="98" font-family="sans-serif" font-size="22" fill="#fff" text-anchor="middle">${label}</text></svg>`;
const hueOf = (s) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 360, 7);

const EPORNER = { videos: [
  { id: 'e1', title: 'Sabah yürüyüşü sahil boyunca', keywords: 'outdoor, beach', views: 12000, rate: '4.4', url: 'https://www.eporner.com/video-e1/x/', added: '2026-11-10 10:00:00', length_sec: 725, embed: 'https://www.eporner.com/embed/e1/', default_thumb: { src: 'https://img.test/e1.jpg' } },
  { id: 'e2', title: 'Ofiste uzun bir gün', keywords: 'office', views: 800, rate: '3.9', url: 'https://www.eporner.com/video-e2/x/', added: '2026-11-12 10:00:00', length_sec: 1310, embed: 'https://www.eporner.com/embed/e2/', default_thumb: { src: 'https://img.test/e2.jpg' } },
  { id: 'e3', title: 'Engellenmesi gereken liseli başlığı', keywords: '', views: 5, rate: '1', url: 'https://www.eporner.com/video-e3/x/', added: '2026-11-12 10:00:00', length_sec: 100, embed: 'https://www.eporner.com/embed/e3/', default_thumb: { src: 'https://img.test/e3.jpg' } },
] };
const PORNHUB = { videos: [
  { duration: '12:06', views: 90000, video_id: 'p1', rating: 88, title: 'Sabah Yürüyüşü Sahil Boyunca - HD', url: 'https://www.pornhub.com/view_video.php?viewkey=p1', default_thumb: 'https://ei.phncdn.com/p1.jpg', publish_date: '2026-11-09 10:00:00', tags: [{ tag_name: 'outdoor' }] },
  { duration: '8:20', views: 4000, video_id: 'p2', rating: 71, title: 'Havuz başında öğleden sonra', url: 'https://www.pornhub.com/view_video.php?viewkey=p2', default_thumb: 'https://img.test/p2.jpg', publish_date: '2026-11-11 10:00:00', tags: [] },
] };
const REDTUBE = { videos: [
  { video: { duration: '8:20', views: 300, video_id: 'r1', rating: 60, title: 'Havuz Başında Öğleden Sonra', url: 'https://www.redtube.com/r1', embed_url: 'https://embed.redtube.com/?id=r1', default_thumb: 'https://img.test/r1.jpg', publish_date: '2026-11-11 12:00:00', tags: [] } },
] };
const xBlock = (host, id, eid, title, minutes, hd) => `<div id="video_${eid}" data-id="${id}" data-eid="${eid}" class="thumb-block"><div class="thumb"><a href="/video.${eid}/x"><img src="https://img.test/${eid}.jpg"><span class="video-hd-mark">${hd}p</span></a></div><p class="title"><a href="/video.${eid}/x" title="${title}">${title} <span class="duration">${minutes} min</span></a></p><p class="metadata"><span class="duration">${minutes} min</span> 1.2M <span class="sprfluous">Views</span></p></div>`;
const XVIDEOS = '<html><body>' + xBlock('xv', 101, 'xv1', 'Dağ evinde hafta sonu', 21, 1080) + xBlock('xv', 102, 'xv2', 'Yağmurlu bir akşam', 9, 720) + '</body></html>';
const XNXX = '<html><body>' + xBlock('xn', 201, 'xn1', 'Şehir turu ve akşam yemeği', 15, 720) + '</body></html>';
const wpPost = (id, base, title) => ({ id, date_gmt: '2026-11-14T10:10:22', link: `${base}/yazi-${id}/`, title: { rendered: title }, views: String(id * 3),
  class_list: ['post', 'category-konulu', 'category-masaj-1'], _embedded: { 'wp:featuredmedia': [{ source_url: `${base}/wp-content/uploads/g${id}.jpeg` }] } });
const DOEDA = [wpPost(11, 'http://www.doeda.com', 'Komşuyla kahve sohbeti'), wpPost(12, 'http://www.doeda.com', 'Tatil dönüşü sürpriz')];
const DOEDA_ONE = [wpPost(21, 'https://www.doeda.one', 'Eski arkadaşlar buluşması')];
const DOEDA_PAGE = '<html><body><div id="video"><iframe src="https://oynatici.test/player/play.php?vid=0123456789abcdef0123456789abcdef"></iframe></div></body></html>';

const seen = [];   // aracıya gelen dış istekler
const sawMedia = [];   // tarayıcının doğrudan istediği video dosyaları
async function fakeUpstream(url) {
  seen.push(url);
  const u = new URL(url);
  const respond = (body, type) => new Response(body, { status: 200, headers: { 'Content-Type': type } });
  if (u.hostname === 'www.pornhub.com') return respond(JSON.stringify(PORNHUB), 'application/json');
  if (u.hostname === 'api.redtube.com') return respond(JSON.stringify(REDTUBE), 'application/json');
  if (u.hostname === 'www.xvideos.com' && u.pathname.startsWith('/video.')) {
    return respond("<script>html5player.setVideoHLS('https://media.test/hls.m3u8');html5player.setVideoUrlHigh('https://media.test/360.mp4');</script>", 'text/html');
  }
  if (u.hostname === 'www.xvideos.com') return respond(XVIDEOS, 'text/html');
  if (u.hostname === 'www.xnxx.com') return respond(XNXX, 'text/html');
  if (u.hostname === 'www.doeda.com' && u.pathname.startsWith('/wp-json/')) return respond(JSON.stringify(u.searchParams.get('page') === '1' ? DOEDA : []), 'application/json');
  if (u.hostname === 'www.doeda.com' && u.pathname.endsWith('.jpeg')) return respond(thumb('Doeda', hueOf(u.pathname)), 'image/svg+xml');
  // Telefonun doğrudan erişemediği (engelli) görsel sunucusu: aracı üzerinden gelir
  if (u.hostname.endsWith('phncdn.com')) return respond(thumb('aracı', 200), 'image/svg+xml');
  if (u.hostname === 'www.doeda.com' || u.hostname === 'www.doeda.one') return respond(DOEDA_PAGE, 'text/html');
  return new Response('yok', { status: 404 });
}

// ---------------------------------------------------------------- yerel sunucu (worker + dosyalar)

function startServer({ withRelay }) {
  const env = { ASSETS: { fetch: async (request) => {
    let p = new URL(request.url).pathname;
    if (p.endsWith('/')) p += 'index.html';
    try {
      return new Response(await readFile(path.join(root, p)), { headers: { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream' } });
    } catch { return new Response('bulunamadı', { status: 404 }); }
  } } };
  const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const request = new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers: req.headers,
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks) });
    const pathname = new URL(request.url).pathname;
    const response = pathname === '/r'
      ? (withRelay ? await relay(request, env, fakeUpstream) : new Response('yok', { status: 404 }))
      : pathname === '/img'
        ? (withRelay ? await imageProxy(request, env, fakeUpstream) : new Response('yok', { status: 404 }))
        : await worker.fetch(request, env);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function openApp(browser, base) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  const problems = [];
  page.on('pageerror', (e) => problems.push(`sayfa hatası: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) problems.push(`konsol: ${m.text()}`); });
  // Tarayıcının doğrudan gittiği adresler (CORS izni olan API'ler, görseller, oynatıcılar)
  await context.route((url) => !url.href.startsWith(base), async (route) => {
    const u = new URL(route.request().url());
    const json = (body) => route.fulfill({ status: 200, contentType: 'application/json', headers: { 'Access-Control-Allow-Origin': '*' }, body: JSON.stringify(body) });
    if (u.hostname === 'www.eporner.com' && u.pathname.startsWith('/api/')) return json(u.searchParams.get('page') === '1' ? EPORNER : { videos: [] });
    if (u.hostname === 'www.doeda.one' && u.pathname.startsWith('/wp-json/')) return json(u.searchParams.get('page') === '1' ? DOEDA_ONE : []);
    if (u.hostname === 'img.test' || u.pathname.endsWith('.jpeg')) return route.fulfill({ status: 200, contentType: 'image/svg+xml', body: thumb(u.pathname.replace(/\W/g, '').slice(0, 6), hueOf(u.pathname)) });
    if (u.hostname === 'media.test') { sawMedia.push(u.href); return route.fulfill({ status: 404, body: 'yok' }); }
    if (/embed|play\.php/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/html', body: `<meta charset="utf-8"><body style="margin:0;background:#111;color:#fff;font:16px sans-serif;display:grid;place-items:center;height:100vh;text-align:center">▶ sahte oynatıcı<br>${u.hostname}</body>` });
    return route.abort();
  });
  await page.goto(base + '/');
  return { context, page, problems };
}

const shot = async (page, name) => { if (shots) { await mkdir(shots, { recursive: true }); await page.screenshot({ path: path.join(shots, name) }); } };
const titles = (page) => page.$$eval('#grid .card .title', (els) => els.map((e) => e.textContent));

// ---------------------------------------------------------------- senaryolar

const browser = await chromium.launch();
let failed = false;
try {
  // === 1) Aracı varken: tüm kaynaklar
  const server = await startServer({ withRelay: true });
  const base = `http://127.0.0.1:${server.address().port}`;
  const { context, page, problems } = await openApp(browser, base);

  await page.waitForSelector('.gate');
  assert.equal(await page.$('#grid'), null, '18+ onayından önce içerik görünmemeli');
  await shot(page, '1-yas-onayi.png');
  await page.click('.gate .btn.primary');
  await page.waitForFunction(() => document.querySelectorAll('#grid .card').length >= 8 && !document.querySelector('.loading'));

  const list = await titles(page);
  assert.equal(list.length, 8, `8 kart beklenirdi: ${list.join(' | ')}`);
  assert.ok(!list.some((t) => /liseli/i.test(t)), 'güvenlik filtresi');
  assert.equal(list.filter((t) => /sahil boyunca/i.test(t)).length, 1, 'aynı video (Eporner + Pornhub) tek kart');
  assert.equal(list.filter((t) => /havuz/i.test(t)).length, 1, 'aynı video (Pornhub + RedTube) tek kart');
  assert.match(await page.textContent('#head'), /2 yinelenen video gizlendi/);
  const badges = await page.$$eval('#grid .badge.tl', (els) => els.map((e) => e.textContent));
  assert.ok(badges.some((b) => / \+1$/.test(b)), 'kopyası olan kartta +1 görünmeli');
  assert.ok(await page.$('.install'), 'Safari\'de kurulum önerisi görünmeli');
  // Görsel sunucusu engelli (ei.phncdn.com tarayıcıdan açılmıyor): kapak aracıdan gelmeli
  await page.waitForFunction(() => [...document.querySelectorAll('#grid img')].some((i) => i.src.includes('/img?u=') && i.naturalWidth > 0));
  const proxied = await page.$$eval('#grid img', (els) => els.filter((i) => i.src.includes('/img?u=')).map((i) => decodeURIComponent(i.src)));
  assert.ok(proxied.some((s) => s.includes('ei.phncdn.com/p1.jpg')), proxied.join(' | '));
  await shot(page, '2-kesfet.png');

  // Kategori + arama: Türk sitesine Türkçe, yabancıya İngilizce terim
  seen.length = 0;
  await page.click('.chip:has-text("Sarışın")');
  await page.waitForFunction(() => !document.querySelector('.loading'));
  await page.fill('input[name=q]', 'ofis');
  await page.press('input[name=q]', 'Enter');
  await page.waitForFunction(() => !document.querySelector('.loading'));
  const sent = seen.map(decodeURIComponent).join('\n');
  assert.match(sent, /pornhub\.com\/webmasters\/search\?search=blonde\+office/, sent);
  assert.match(sent, /doeda\.com\/wp-json\/wp\/v2\/posts\?.*search=sarışın\+ofis/, sent);
  await page.click('.chip.clear');
  await page.fill('input[name=q]', '');
  await page.press('input[name=q]', 'Enter');
  await page.waitForFunction(() => document.querySelectorAll('#grid .card').length === 8 && !document.querySelector('.loading'));

  // Oynatıcı: korumalı çerçeve, kaynak değiştirme, favori
  await page.click('#grid .card:has-text("Sahil Boyunca")');
  await page.waitForSelector('#player iframe');
  const frame = await page.$eval('#player iframe', (f) => ({ src: f.src, sandbox: f.getAttribute('sandbox'), ref: f.getAttribute('referrerpolicy') }));
  assert.ok(/pornhub\.com\/embed\/p1|eporner\.com\/embed\/e1/.test(frame.src), frame.src);
  assert.equal(frame.sandbox, 'allow-scripts allow-same-origin allow-presentation allow-forms', 'açılır pencere / üst sayfa izni olmamalı');
  assert.equal(frame.ref, 'origin');
  assert.equal(await page.$$eval('#player select option', (o) => o.length), 2, 'iki kaynak seçilebilmeli');
  await page.selectOption('#player select', '1');
  await page.waitForFunction((old) => document.querySelector('#player iframe')?.src !== old, frame.src);
  await page.click('#player [aria-label="Favori"]');
  await shot(page, '3-oynatici.png');
  await page.click('#player [aria-label="Kapat"]');

  // Türk sitesi: sayfa aracıdan okunur, yalnızca oynatıcı çerçevesi açılır
  await page.click('#grid .card:has-text("Komşuyla")');
  await page.waitForSelector('#player iframe');
  assert.match(await page.$eval('#player iframe', (f) => f.src), /^https:\/\/oynatici\.test\/player\/play\.php\?vid=[0-9a-f]{32}$/);
  await page.click('#player [aria-label="Kapat"]');

  // XVideos: video sayfası aracıdan okunur, akış doğrudan <video> ile açılır; açılmazsa gömülüye geçilir.
  await page.click('#grid .card:has-text("Dağ evinde")');
  await page.waitForSelector('#player iframe');   // sahte akış 404 verir -> gömülü oynatıcıya düşülmeli
  assert.match(await page.$eval('#player iframe', (f) => f.src), /^https:\/\/www\.xvideos\.com\/embedframe\/xv1$/);
  assert.match(await page.textContent('#player'), /doğrudan açılamadı/);
  assert.ok(sawMedia.some((u) => u.endsWith('/360.mp4')), 'önce doğrudan akış denenmeli');
  await page.click('#player [aria-label="Kapat"]');

  // Favoriler ve izlenenleri gizleme
  await page.click('[aria-label="Favoriler"]');
  assert.equal((await titles(page)).length, 1);
  await page.click('[aria-label="Favoriler"]');
  await page.click('[aria-label="Ayarlar"]');
  await page.waitForSelector('#settings h3');
  assert.match(await page.textContent('#settings'), /Durum: bağlı/);
  assert.match(await page.textContent('#settings'), /İzleme geçmişini temizle \(3 video\)/);
  await shot(page, '4-ayarlar.png');
  await page.click('#settings label:has-text("İzlediklerimi gizle") input');
  await page.click('#settings [aria-label="Kapat"]');
  await page.waitForFunction(() => document.querySelectorAll("#grid .card").length === 5 && !document.querySelector('.loading'));
  assert.match(await page.textContent('#head'), /izlenmiş/);

  // Kurulum profili
  const profile = await page.request.get(base + '/vitrin.mobileconfig');
  assert.equal(profile.headers()['content-type'], 'application/x-apple-aspen-config');
  assert.ok((await profile.text()).includes(`<key>URL</key><string>${base}/</string>`));
  assert.deepEqual(problems, [], problems.join('\n'));
  await context.close();
  server.close();

  // === 2) Aracı yokken: yalnızca tarayıcıdan doğrudan okunabilen kaynaklar
  const bare = await startServer({ withRelay: false });
  const bareBase = `http://127.0.0.1:${bare.address().port}`;
  const second = await openApp(browser, bareBase);
  await second.page.click('.gate .btn.primary');
  await second.page.waitForFunction(() => document.querySelectorAll('#grid .card').length >= 3 && !document.querySelector('.loading'));
  const direct = await titles(second.page);
  assert.equal(direct.length, 3, direct.join(' | '));   // Eporner (2) + Doeda One (1)
  assert.match(await second.page.textContent('#head'), /Aracı olmadığı için kapalı: XVideos, XNXX, Pornhub, RedTube, Doeda\./);
  assert.equal(await second.page.$('.seg'), null, 'Hentai/tür seçimi kalmamalı');
  await second.page.click('#grid .card:has-text("Eski arkadaşlar")');
  await second.page.waitForSelector('#player .frame.center');
  assert.match(await second.page.textContent('#player'), /aracı \(relay\) gerekli/);
  assert.deepEqual(second.problems, [], second.problems.join('\n'));
  await second.context.close();
  bare.close();

  console.log('Uçtan uca deneme başarılı: 18+ kapısı, güvenlik filtresi, yinelenen birleştirme, iki dilli arama, korumalı oynatıcı, doğrudan akış + gömülüye düşme, kaynak değiştirme, favoriler, izlenenleri gizleme, profil, aracısız kip.');
} catch (e) {
  failed = true;
  console.error('DENEME BAŞARISIZ:\n', e);
} finally {
  await browser.close();
}
process.exit(failed ? 1 : 0);
