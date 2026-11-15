// Vitrin — Cloudflare Worker: (1) web uygulamasının dosyalarını sunar, (2) kurulum profilini üretir,
// (3) "aracı" (relay) görevi görür: tarayıcının CORS yüzünden doğrudan okuyamadığı arama
// sayfalarını/API'lerini uygulama adına getirir.
//
// Aracı neleri GEÇİRMEZ: videolar ve oynatıcılar (bunlar telefondan doğrudan yüklenir),
// izin listesinde olmayan alan adları, GET/POST dışındaki istekler. Hiçbir şey saklanmaz, kayıt tutulmaz.
import { buildProfile } from './profile.js';

const BUILT_IN_HOSTS = [
  'www.pornhub.com', 'api.redtube.com', 'www.xvideos.com', 'www.xnxx.com', 'www.eporner.com',
  'www.doeda.com', 'doeda.com', 'doe.customcdn.org', 'www.doeda.one', 'doeda.one',
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

    if (url.pathname === '/vitrin.mobileconfig') {
      const icon = await env.ASSETS.fetch(new Request(new URL('/apple-touch-icon.png', url)));
      const profile = buildProfile({ url: url.origin + '/', iconBase64: toBase64(await icon.arrayBuffer()) });
      return new Response(profile, { headers: { 'Content-Type': 'application/x-apple-aspen-config', 'Cache-Control': 'no-store', ...SECURITY } });
    }

    const res = await env.ASSETS.fetch(request);
    const out = new Response(res.body, res);
    for (const [k, v] of Object.entries(SECURITY)) out.headers.set(k, v);
    return out;
  },
};
