// Aracı (Cloudflare Worker) ve kurulum profili testleri.
import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { relay, imageProxy } from '../relay/worker.js';
import { buildProfile } from '../relay/profile.js';

const APP = 'https://vitrin.example.workers.dev';
const req = (path, init = {}) => new Request(APP + path, init);
const upstream = (body = '{"ok":1}', type = 'application/json') => {
  const calls = [];
  const fn = async (url, init) => { calls.push({ url, init }); return new Response(body, { status: 200, headers: { 'Content-Type': type } }); };
  fn.calls = calls;
  return fn;
};

test('ping ve izin listesi', async () => {
  assert.deepEqual(await (await relay(req('/r?ping=1'), {})).json(), { vitrin: 'relay' });

  const up = upstream();
  const ok = await relay(req('/r?u=' + encodeURIComponent('https://www.pornhub.com/webmasters/search?search=a')), {}, up);
  assert.equal(ok.status, 200);
  assert.equal(await ok.text(), '{"ok":1}');
  assert.equal(up.calls[0].url, 'https://www.pornhub.com/webmasters/search?search=a');
  assert.match(up.calls[0].init.headers['User-Agent'], /iPhone/);
  assert.equal(ok.headers.get('X-Robots-Tag'), 'noindex, nofollow, noarchive');

  for (const bad of ['https://example.com/', 'https://evil.pornhub.com.example.org/', 'ftp://www.pornhub.com/', 'http://169.254.169.254/', 'bozuk']) {
    const res = await relay(req('/r?u=' + encodeURIComponent(bad)), {}, up);
    assert.ok(res.status === 403 || res.status === 400, bad);
  }
  assert.equal(up.calls.length, 1, 'izinsiz adreslere hiç istek gitmemeli');

  // Kullanıcının eklediği site: EXTRA_HOSTS ile açılır
  assert.equal((await relay(req('/r?u=' + encodeURIComponent('https://ornek.com/a')), { EXTRA_HOSTS: 'ornek.com, www.ornek.com' }, up)).status, 200);
});

test('POST gövdesi ve Referer iletilir; videolar geçmez; yalnızca GET/POST', async () => {
  const up = upstream('{"source":[]}');
  const res = await relay(req('/r?u=' + encodeURIComponent('https://www.doeda.com/x') + '&ref=' + encodeURIComponent('https://www.doeda.com/'), {
    method: 'POST', body: 'vid=abc&ord=0', headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }), {}, up);
  assert.equal(res.status, 200);
  const sent = up.calls[0].init;
  assert.equal(sent.method, 'POST');
  assert.equal(new TextDecoder().decode(sent.body), 'vid=abc&ord=0');
  assert.equal(sent.headers.Referer, 'https://www.doeda.com/');
  assert.equal(sent.headers['X-Requested-With'], 'XMLHttpRequest');

  const video = await relay(req('/r?u=' + encodeURIComponent('https://www.xvideos.com/v.mp4')), {}, upstream('xx', 'video/mp4'));
  assert.equal(video.status, 415);
  assert.equal((await relay(req('/r?u=' + encodeURIComponent('https://www.xvideos.com/')), {}, upstream('#EXTM3U', 'application/vnd.apple.mpegurl'))).status, 415);
  assert.equal((await relay(req('/r?u=' + encodeURIComponent('https://www.xvideos.com/'), { method: 'DELETE' }), {}, upstream())).status, 405);
});

test('CORS: yalnızca kendi adresi ve izin verilen adresler', async () => {
  const target = '/r?u=' + encodeURIComponent('https://api.redtube.com/?a=1');
  const same = await relay(req(target, { headers: { Origin: APP } }), {}, upstream());
  assert.equal(same.headers.get('Access-Control-Allow-Origin'), APP);
  const foreign = await relay(req(target, { headers: { Origin: 'https://baska.example' } }), {}, upstream());
  assert.equal(foreign.status, 403);
  const allowed = await relay(req(target, { headers: { Origin: 'https://kullanici.github.io' } }), { ALLOWED_ORIGINS: 'https://kullanici.github.io' }, upstream());
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://kullanici.github.io');
  const pre = await relay(req(target, { method: 'OPTIONS', headers: { Origin: APP } }), {}, upstream());
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get('Access-Control-Allow-Methods'), /POST/);
});

test('worker: dosyaları sunar ve kurulum profilini kendi adresiyle üretir', async () => {
  const env = { ASSETS: { fetch: async (r) => new URL(r.url).pathname === '/apple-touch-icon.png'
    ? new Response(new Uint8Array([137, 80, 78, 71]), { headers: { 'Content-Type': 'image/png' } })
    : new Response('<html>uygulama</html>', { headers: { 'Content-Type': 'text/html' } }) } };

  const page = await worker.fetch(req('/'), env);
  assert.equal(await page.text(), '<html>uygulama</html>');
  assert.equal(page.headers.get('X-Robots-Tag'), 'noindex, nofollow, noarchive');

  const profile = await worker.fetch(req('/vitrin.mobileconfig'), env);
  assert.equal(profile.headers.get('Content-Type'), 'application/x-apple-aspen-config');
  const xml = await profile.text();
  assert.ok(xml.includes(`<key>URL</key><string>${APP}/</string>`));
  assert.ok(xml.includes('<key>Icon</key><data>iVBORw==</data>'));
  assert.ok(xml.includes('com.apple.webClip.managed') && xml.includes('<key>FullScreen</key><true/>'));

  assert.deepEqual(await (await worker.fetch(req('/r?ping=1'), env)).json(), { vitrin: 'relay' });
});

test('profil: adres ve ad güvenli biçimde yazılır', () => {
  const xml = buildProfile({ url: 'https://a.example/app?x=1&y=2', iconBase64: 'QUJD', name: 'A & B' });
  assert.ok(xml.includes('<string>https://a.example/app?x=1&amp;y=2/</string>'));
  assert.ok(xml.includes('<string>A &amp; B</string>'));
  assert.ok(xml.startsWith('<?xml version="1.0"'));
});

test('IPA dağıtımı: SideStore/AltStore kaynağı ve indirme başlıkları', async () => {
  const surum = { name: 'Vitrin', bundleIdentifier: 'com.example.vitrin', version: '1.2', buildVersion: '3',
    minOSVersion: '17.0', size: 1234567, sha256: 'ab', date: '2026-11-19T10:00:00Z', note: '' };
  const assets = (has) => ({ ASSETS: { fetch: async (r) => {
    const p = new URL(r.url).pathname;
    if (p === '/ipa/surum.json' && has) return new Response(JSON.stringify(surum), { headers: { 'Content-Type': 'application/json' } });
    if (p === '/ipa/Vitrin.ipa' && has) return new Response(new Uint8Array([80, 75]), { headers: { 'Content-Type': 'text/plain' } });
    return new Response('yok', { status: 404 });
  } } });

  const src = await (await worker.fetch(req('/ipa/kaynak.json'), assets(true))).json();
  assert.equal(src.identifier, 'app.vitrin.kaynak');
  const app = src.apps[0];
  assert.equal(app.bundleIdentifier, 'com.example.vitrin');
  assert.equal(app.versions[0].downloadURL, `${APP}/ipa/Vitrin.ipa`);
  assert.equal(app.versions[0].version, '1.2');
  assert.equal(app.versions[0].size, 1234567);
  assert.equal(app.versions[0].minOSVersion, '17.0');
  assert.equal(app.downloadURL, `${APP}/ipa/Vitrin.ipa`, 'eski istemciler için tek sürüm alanı');
  assert.equal(src.iconURL, `${APP}/icon-512.png`);

  const ipa = await worker.fetch(req('/ipa/Vitrin.ipa'), assets(true));
  assert.equal(ipa.headers.get('Content-Type'), 'application/octet-stream');
  assert.match(ipa.headers.get('Content-Disposition'), /attachment; filename="Vitrin.ipa"/);

  assert.equal((await worker.fetch(req('/ipa/kaynak.json'), assets(false))).status, 404, 'IPA yokken kaynak 404');
});

test('görsel aracısı: yalnızca izinli görsel sunucuları ve yalnızca resim', async () => {
  const up = upstream('<svg/>', 'image/jpeg');
  const res = await worker.fetch(req('/img?u=' + encodeURIComponent('https://pix-fl.phncdn.com/a/b.jpg?x=1')), {});
  assert.ok([200, 502].includes(res.status), 'gerçek ağ olmadan 502 de olabilir');

  const ok = await imageProxy(req('/img?u=' + encodeURIComponent('https://pix-fl.phncdn.com/a/b.jpg?x=1')), {}, up);
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get('Content-Type'), 'image/jpeg');
  assert.match(ok.headers.get('Cache-Control'), /max-age=86400/);
  assert.equal(up.calls[0].init.headers.Referer, 'https://www.pornhub.com/');

  for (const bad of ['https://evil.example/a.jpg', 'https://phncdn.com.evil.example/a.jpg', 'ftp://x.phncdn.com/a', 'bozuk']) {
    const r = await imageProxy(req('/img?u=' + encodeURIComponent(bad)), {}, up);
    assert.ok(r.status === 403 || r.status === 400, bad);
  }
  assert.equal(up.calls.length, 1, 'izinsiz adreslere istek gitmemeli');

  assert.equal((await imageProxy(req('/img?u=' + encodeURIComponent('https://x.xvideos-cdn.com/v.mp4')), {}, upstream('x', 'video/mp4'))).status, 415, 'video geçmemeli');
  assert.equal((await imageProxy(req('/img?u=' + encodeURIComponent('https://x.xvideos-cdn.com/a.jpg'), { method: 'POST', body: 'x' }), {}, up)).status, 405);
  assert.equal((await imageProxy(req('/img?u=' + encodeURIComponent('https://ornek.com/a.jpg')), { EXTRA_HOSTS: 'ornek.com' }, upstream('<svg/>', 'image/png'))).status, 200);
});
