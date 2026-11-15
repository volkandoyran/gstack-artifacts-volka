// Uygulama kabuğunu önbelleğe alır (çevrimdışı açılış ve hızlı başlatma için).
// Yalnızca kendi dosyalarımız önbelleğe girer; sitelere giden istekler ve aracı (r) asla.
const CACHE = 'vitrin-kabuk-v1';
const SHELL = ['./', 'index.html', 'style.css', 'app.js', 'manifest.webmanifest', 'icon.svg', 'apple-touch-icon.png',
  'core/text.js', 'core/safety.js', 'core/dedupe.js', 'core/catalog.js', 'core/net.js', 'core/providers.js',
  'core/planner.js', 'core/store.js', 'core/browse.js'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  const scope = new URL(self.registration.scope);
  const own = url.origin === scope.origin && url.pathname.startsWith(scope.pathname);
  if (e.request.method !== 'GET' || !own || url.pathname === scope.pathname + 'r' || url.pathname.endsWith('.mobileconfig')) return;
  // Önce ağ (yeni sürüm hemen gelsin), ağ yoksa önbellek.
  e.respondWith(fetch(e.request).then((res) => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); }
    return res;
  }).catch(() => caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || caches.match('index.html'))));
});
