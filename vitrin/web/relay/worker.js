// Vitrin — Cloudflare Worker: (1) web uygulamasının dosyalarını sunar, (2) kurulum profilini üretir,
// (3) "aracı" (relay) görevi görür: tarayıcının CORS yüzünden doğrudan okuyamadığı arama
// sayfalarını/API'lerini uygulama adına getirir.
//
// Aracı neleri GEÇİRMEZ: videolar ve oynatıcılar (bunlar telefondan doğrudan yüklenir),
// izin listesinde olmayan alan adları, GET/POST dışındaki istekler. Hiçbir şey saklanmaz, kayıt tutulmaz.
import { buildProfile } from './profile.js';
import { buildSource } from './ipa.js';

const BUILT_IN_HOSTS = [
  'www.pornhub.com', 'api.redtube.com', 'www.xvideos.com', 'www.xnxx.com', 'www.eporner.com',
  'www.doeda.com', 'doeda.com', 'doe.customcdn.org', 'www.doeda.one', 'doeda.one',
  // Doeda'nın oynatıcısı (Jet Player): yalnızca video adreslerini veren kaynak servisi için
  'www.canlitvnews3.xyz', 'canlitvnews3.xyz',
];
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const SECURITY = { 'X-Robots-Tag': 'noindex, nofollow, noarchive', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };

const list = (s) => String(s || '').split(',').map((x) => x.trim().toLowerCase()).filter(Boolean);
const json = (body, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...SECURITY, ...headers } });

function corsHeaders(request, env) {
  const origin = request.headers.get('Origin');
  if (!origin) return {};
  const self = new URL(request.url).origin;
  if (origin !== self && !list(env.ALLOWED_ORIGINS).includes(origin.toLowerCase())) return null;   // yabancı site
  return { 'Access-Control-Allow-Origin': origin, 'Vary': 'Origin' };
}

export async function relay(request, env, upstreamFetch = fetch) {
  const url = new URL(request.url);
  const cors = corsHeaders(request, env);
  if (cors === null) return json({ error: 'Bu adresten kullanılamaz.' }, 403);
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, POST', 'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Max-Age': '86400' } });
  }
  if (url.searchParams.has('ping')) return json({ vitrin: 'relay' }, 200, cors);
  if (request.method !== 'GET' && request.method !== 'POST') return json({ error: 'Yalnızca GET/POST.' }, 405, cors);

  let target;
  try { target = new URL(url.searchParams.get('u') || ''); } catch { return json({ error: 'Geçersiz adres.' }, 400, cors); }
  const allowed = BUILT_IN_HOSTS.concat(list(env.EXTRA_HOSTS));
  if (!/^https?:$/.test(target.protocol) || !allowed.includes(target.hostname.toLowerCase())) {
    return json({ error: `Aracı bu alan adına izin vermiyor: ${target.hostname}` }, 403, cors);
  }

  const headers = { 'User-Agent': UA, 'Accept': '*/*', 'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8' };
  const ref = url.searchParams.get('ref');
  if (ref) headers['Referer'] = ref;
  const init = { method: request.method, headers, redirect: 'follow' };
  if (request.method === 'POST') {
    headers['Content-Type'] = request.headers.get('Content-Type') || 'application/x-www-form-urlencoded';
    headers['X-Requested-With'] = 'XMLHttpRequest';
    init.body = await request.arrayBuffer();
  }

  let upstream;
  try { upstream = await upstreamFetch(target.href, init); }
  catch { return json({ error: `${target.hostname} adresine ulaşılamadı.` }, 502, cors); }

  const type = upstream.headers.get('Content-Type') || 'application/octet-stream';
  if (/^(video|audio)\//i.test(type) || /mpegurl/i.test(type)) {
    return json({ error: 'Videolar aracıdan geçmez.' }, 415, cors);
  }
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { 'Content-Type': type, 'Cache-Control': 'private, max-age=60', ...SECURITY, ...cors },
  });
}

// Küçük resimler (video kapakları) için görsel aracısı. Görsel sunucuları bazı ülkelerde/ağlarda
// erişime kapalı olduğundan, telefon görseli doğrudan alamazsa uygulama onu buradan ister.
// Yalnızca aşağıdaki alan adlarından (ve alt alan adlarından) yalnızca resim dosyaları geçer;
// Cloudflare'de bir gün önbellekte tutulur.
const IMAGE_HOST_SUFFIXES = [
  'phncdn.com', 'rdtcdn.com', 'xvideos-cdn.com', 'xnxx-cdn.com', 'eporner.com',
  'doeda.com', 'doeda.one', 'customcdn.org',
];
const IMAGE_REFERERS = { 'phncdn.com': 'https://www.pornhub.com/', 'rdtcdn.com': 'https://www.redtube.com/',
  'xvideos-cdn.com': 'https://www.xvideos.com/', 'xnxx-cdn.com': 'https://www.xnxx.com/', 'eporner.com': 'https://www.eporner.com/' };

export async function imageProxy(request, env, upstreamFetch = fetch) {
  if (request.method !== 'GET') return json({ error: 'Yalnızca GET.' }, 405);
  let target;
  try { target = new URL(new URL(request.url).searchParams.get('u') || ''); } catch { return json({ error: 'Geçersiz adres.' }, 400); }
  const host = target.hostname.toLowerCase();
  const suffixes = IMAGE_HOST_SUFFIXES.concat(list(env.EXTRA_HOSTS));
  const match = suffixes.find((s) => host === s || host.endsWith('.' + s));
  if (!/^https?:$/.test(target.protocol) || !match) return json({ error: `Görsel aracısı bu alan adına izin vermiyor: ${host}` }, 403);

  const headers = { 'User-Agent': UA, 'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8' };
  if (IMAGE_REFERERS[match]) headers['Referer'] = IMAGE_REFERERS[match];
  let upstream;
  try { upstream = await upstreamFetch(target.href, { headers, redirect: 'follow', cf: { cacheTtl: 86400, cacheEverything: true } }); }
  catch { return json({ error: `${host} adresine ulaşılamadı.` }, 502); }
  const type = upstream.headers.get('Content-Type') || '';
  if (!upstream.ok) return new Response(null, { status: upstream.status, headers: SECURITY });
  if (!/^image\//i.test(type)) return json({ error: 'Yalnızca görseller geçer.' }, 415);
  return new Response(upstream.body, { status: 200, headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=86400', ...SECURITY } });
}

function toBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/r') return relay(request, env);
    if (url.pathname === '/img') return imageProxy(request, env);

    if (url.pathname === '/vitrin.mobileconfig') {
      const icon = await env.ASSETS.fetch(new Request(new URL('/apple-touch-icon.png', url)));
      const profile = buildProfile({ url: url.origin + '/', iconBase64: toBase64(await icon.arrayBuffer()) });
      return new Response(profile, { headers: { 'Content-Type': 'application/x-apple-aspen-config', 'Cache-Control': 'no-store', ...SECURITY } });
    }

    // SideStore / AltStore kaynağı: adresler bu sitenin kendi adresiyle üretilir.
    if (url.pathname === '/ipa/kaynak.json') {
      const res = await env.ASSETS.fetch(new Request(new URL('/ipa/surum.json', url)));
      if (!res.ok) return json({ error: 'Henüz yayınlanmış bir IPA yok.' }, 404);
      return json(buildSource(url.origin, await res.json()), 200, { 'Cache-Control': 'no-cache' });
    }

    const res = await env.ASSETS.fetch(request);
    const out = new Response(res.body, res);
    for (const [k, v] of Object.entries(SECURITY)) out.headers.set(k, v);
    if (url.pathname.endsWith('.ipa') && res.ok) {
      out.headers.set('Content-Type', 'application/octet-stream');
      out.headers.set('Content-Disposition', 'attachment; filename="Vitrin.ipa"');
      out.headers.set('Cache-Control', 'no-cache');
    }
    if (url.pathname === '/ipa/surum.json') out.headers.set('Cache-Control', 'no-cache');
    return out;
  },
};
