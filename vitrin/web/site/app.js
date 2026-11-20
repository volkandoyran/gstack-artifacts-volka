// Vitrin web sürümü — arayüz. Sitelerden gelen metinler yalnızca textContent ile yazılır (HTML olarak değil).
import { CATEGORIES, SORTS } from './core/catalog.js';
import { DEDUPE_LEVELS } from './core/dedupe.js';
import { createNet, describeError } from './core/net.js';
import { builtInProviders, wordpress, customSite } from './core/providers.js';
import { createStore } from './core/store.js';
import { createBrowser } from './core/browse.js';
import { clock, compact } from './core/text.js';

const store = createStore(localStorage);
const net = createNet();
const getProviders = () => builtInProviders().concat(store.settings.customSites.map(wordpress));
const browser = createBrowser({ net, store, getProviders, onChange: () => renderMain() });
const S = browser.state;
const ui = { view: 'browse', player: null, settingsOpen: false, relayStatus: 'aranıyor…' };

// ---------------------------------------------------------------- küçük DOM yardımcısı

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'checked' || k === 'value' || k === 'selected' || k === 'disabled') el[k] = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}
const $ = (id) => document.getElementById(id);
const providerName = (id) => getProviders().find((p) => p.id === id)?.name || id;

// ---------------------------------------------------------------- aracı (relay) bulma

async function detectRelay() {
  const custom = store.settings.relayURL.trim().replace(/\/+$/, '');
  const candidates = custom ? [custom] : [new URL('r', location.href).href.replace(/\/+$/, '')];
  for (const base of candidates) {
    try {
      const res = await fetch(`${base}?ping=1`, { credentials: 'omit' });
      if (res.ok && (await res.json()).vitrin === 'relay') {
        net.relayBase = base;
        ui.relayStatus = 'bağlı';
        return;
      }
    } catch { /* yok */ }
  }
  net.relayBase = null;
  ui.relayStatus = custom ? 'adrese ulaşılamadı' : 'yok';
}

// ---------------------------------------------------------------- ana ekran

/** Safari'de (ana ekrandan değil) açıldıysa kurulum profilini öner. */
function installBanner() {
  const standalone = navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
  if (standalone || sessionStorage.getItem('vitrin.kurulumGizle')) return null;
  return h('div', { class: 'install' },
    h('div', { class: 'grow' },
      h('strong', {}, 'Ana ekrana kur'),
      h('small', {}, 'Profili indir → Ayarlar > Profil İndirildi > Yükle. Simge ana ekrana gelir, uygulama tam ekran açılır.')),
    h('a', { class: 'btn primary', href: 'vitrin.mobileconfig' }, 'Kur'),
    h('button', { class: 'icon', type: 'button', 'aria-label': 'Gizle',
      onclick: () => { sessionStorage.setItem('vitrin.kurulumGizle', '1'); renderMain(); } }, '✕'));
}

function chip(label, on, onclick, extraClass = '') {
  return h('button', { class: `chip ${on ? 'on' : ''} ${extraClass}`, type: 'button', onclick }, label);
}

/** Video kapağı: önce doğrudan yüklenir; görsel sunucusu erişilemezse aracı üzerinden yeniden denenir. */
function thumbImage(url) {
  const img = h('img', { src: net.asset(url), alt: '', loading: 'lazy', decoding: 'async', referrerpolicy: 'no-referrer' });
  img.addEventListener('error', () => {
    const proxied = net.imageProxyURL(url);
    if (proxied && img.dataset.proxied !== '1') { img.dataset.proxied = '1'; img.src = proxied; }
    else img.remove();   // gri kutu kalır
  });
  return img;
}

function card(v) {
  const extra = S.alternates.get(v.id)?.length || 0;
  const meta = [];
  if (v.views > 0) meta.push(`👁 ${compact(v.views)}`);
  if (v.rating > 0) meta.push(`👍 %${Math.round(v.rating)}`);
  return h('button', { class: 'card', type: 'button', onclick: () => openPlayer(v) },
    h('span', { class: 'thumb' },
      v.thumbnail && thumbImage(v.thumbnail),
      h('span', { class: 'badge tl' }, providerName(v.providerID) + (extra ? ` +${extra}` : '')),
      v.maxHeight && h('span', { class: 'badge tr dark' }, `${v.maxHeight}p`),
      v.durationSec > 0 && h('span', { class: 'badge br dark' }, clock(v.durationSec)),
      store.isFavorite(v) && h('span', { class: 'badge bl dark' }, '★')),
    h('span', { class: 'title' }, v.title),
    h('span', { class: 'meta' }, meta.join('  ')));
}

let renderedIds = [];   // ızgarada şu an duran kartlar (yenileri sona eklenir, liste baştan kurulmaz)

function renderMain() {
  const root = $('main');
  if (!root) return;
  const showFav = ui.view === 'favorites';
  const list = showFav ? store.favorites : S.videos;
  const cats = CATEGORIES;

  // Yeniden çizimde yazılmakta olan aramayı, odağı ve kategori şeridinin kaydırmasını koru.
  const oldInput = root.querySelector('input[name=q]');
  const draft = oldInput ? oldInput.value : S.freeText;
  const hadFocus = oldInput && document.activeElement === oldInput;
  const chipScroll = root.querySelector('.chips')?.scrollLeft || 0;

  const notes = [];
  if (!showFav) {
    const hidden = [];
    if (S.hiddenDuplicates) hidden.push(`${S.hiddenDuplicates} yinelenen`);
    if (S.hiddenWatched) hidden.push(`${S.hiddenWatched} izlenmiş`);
    if (hidden.length) notes.push(h('p', { class: 'note' }, `${hidden.join(' · ')} video gizlendi`));
    if (S.skippedForRelay.length) {
      notes.push(h('p', { class: 'note' }, `Aracı olmadığı için kapalı: ${S.skippedForRelay.join(', ')}. Ayrıntı Ayarlar'da.`));
    }
    const fails = Object.entries(S.failures);
    if (fails.length) notes.push(h('div', { class: 'warn' }, fails.map(([n, m]) => h('p', {}, `${n}: ${m}`))));
  }

  const head = h('div', { id: 'head' },
    h('header', { class: 'top' },
      h('h1', {}, 'Vitrin'),
      h('button', { class: `icon ${showFav ? 'on' : ''}`, type: 'button', 'aria-label': 'Favoriler',
        onclick: () => { ui.view = showFav ? 'browse' : 'favorites'; renderMain(); } }, '★'),
      h('button', { class: 'icon', type: 'button', 'aria-label': 'Ayarlar', onclick: () => { ui.settingsOpen = true; renderSettings(); } }, '⚙')),

    !showFav && installBanner(),

    !showFav && h('form', { class: 'search', onsubmit: (e) => { e.preventDefault(); S.freeText = e.target.q.value; e.target.q.blur(); browser.refresh(); } },
      h('input', { name: 'q', type: 'search', value: draft, placeholder: 'Ara (Türkçe ya da İngilizce)', autocomplete: 'off', enterkeyhint: 'search' })),

    !showFav && h('div', { class: 'chips' },
      S.selected.size > 0 && chip('✕ Temizle', false, () => { S.selected.clear(); browser.refresh(); }, 'clear'),
      cats.map((c) => chip(c.title, S.selected.has(c.id), () => {
        S.selected.has(c.id) ? S.selected.delete(c.id) : S.selected.add(c.id);
        browser.refresh();
      }))),

    !showFav && h('div', { class: 'controls' },
      S.selected.size > 1 && h('select', { 'aria-label': 'Birleştirme', onchange: (e) => { S.combine = e.target.value; browser.refresh(); } },
        h('option', { value: 'all', selected: S.combine === 'all' }, 'Hepsi birlikte (VE)'),
        h('option', { value: 'any', selected: S.combine === 'any' }, 'Herhangi biri (VEYA)')),
      h('span', { class: 'grow' }),
      h('select', { 'aria-label': 'Sıralama', onchange: (e) => { S.sort = e.target.value; browser.refresh(); } },
        SORTS.map((s) => h('option', { value: s.id, selected: S.sort === s.id }, `⇅ ${s.title}`)))),

    showFav && h('h2', { class: 'section' }, `Favoriler (${list.length})`),
    notes);

  const foot = h('div', { id: 'foot' },
    !showFav && S.loading && h('p', { class: 'loading' }, 'Yükleniyor…'),
    !(S.loading && !showFav) && !list.length && h('p', { class: 'empty' }, showFav ? 'Henüz favori yok. Oynatıcıdaki ★ ile ekleyebilirsin.' : 'Sonuç yok. Farklı kategori ya da kaynak dene.'),
    !showFav && h('div', { id: 'sentinel' }));

  // Izgara: liste öncekinin devamıysa yalnızca yeni kartlar eklenir (görseller yeniden yüklenmez).
  let grid = $('grid');
  const ids = list.map((v) => v.id);
  const continues = grid && renderedIds.length <= ids.length && renderedIds.every((id, i) => id === ids[i]);
  if (!grid) { grid = h('div', { id: 'grid', class: 'grid' }); root.replaceChildren(head, grid, foot); }
  else { $('head').replaceWith(head); $('foot').replaceWith(foot); }
  if (continues) grid.append(...list.slice(renderedIds.length).map(card));
  else grid.replaceChildren(...list.map(card));
  renderedIds = ids;

  const chips = root.querySelector('.chips');
  if (chips) chips.scrollLeft = chipScroll;
  if (hadFocus) root.querySelector('input[name=q]')?.focus();
  const sentinel = $('sentinel');
  if (sentinel) scrollWatcher.observe(sentinel);
}

/** Favori yıldızı gibi kart içi değişikliklerde ızgarayı baştan kurmak için. */
function redrawGrid() { renderedIds = []; $('grid')?.replaceChildren(); renderMain(); }

const scrollWatcher = new IntersectionObserver((entries) => {
  if (entries.some((e) => e.isIntersecting) && S.videos.length && !S.loading && ui.view === 'browse') browser.loadMore();
}, { rootMargin: '600px' });

// ---------------------------------------------------------------- oynatıcı

async function openPlayer(video) {
  const sources = [video].concat(S.alternates.get(video.id) || []);
  ui.player = { video, sources, current: video, status: 'loading', source: null, error: null, guarded: true, variant: 0 };
  renderPlayer();
  await loadPlayback();
}

const unguardedSites = () => store.settings.unguarded || [];

/** Bu tarayıcının oynatabileceği akışlar (iPhone'da HLS dahil), en iyisi başta. */
function playableVariants(videos) {
  const probe = document.createElement('video');
  const hls = !!probe.canPlayType('application/vnd.apple.mpegurl');
  return (videos || []).filter((v) => !v.hls || hls);
}

async function loadPlayback() {
  const p = ui.player;
  if (!p) return;
  const target = p.current;
  Object.assign(p, { status: 'loading', source: null, error: null, note: null, variant: 0, resumeAt: 0,
    guarded: !unguardedSites().includes(target.providerID) });
  renderPlayer();
  try {
    const provider = getProviders().find((x) => x.id === target.providerID);
    if (!provider) throw new Error('Kaynak bulunamadı.');
    let source = await provider.playback(target, net);
    if (ui.player !== p || p.current !== target) return;
    if (source?.videos) {
      const videos = playableVariants(source.videos);
      source = videos.length ? { ...source, videos } : source.fallback ? { embed: source.fallback } : null;
    }
    if (!source || (!source.embed && !source.videos)) throw new Error('Oynatılabilir kaynak bulunamadı.');
    Object.assign(p, { status: 'ready', source });
    store.markWatched(p.video);   // "İzlediklerimi gizle" için
  } catch (e) {
    if (ui.player !== p || p.current !== target) return;
    Object.assign(p, { status: 'failed', error: describeError(e) });
  }
  renderPlayer();
}

/** Doğrudan akış açılamadı: sonraki kaliteyi, o da yoksa sitenin gömülü oynatıcısını dene. */
function onVideoError(p) {
  if (ui.player !== p || !p.source?.videos) return;
  if (p.variant + 1 < p.source.videos.length) {
    p.variant++;
    p.note = 'Bu kalite açılamadı, bir sonrakine geçildi.';
  } else if (p.source.fallback) {
    p.source = { embed: p.source.fallback };
    p.note = 'Video doğrudan açılamadı; sitenin oynatıcısına geçildi.';
  } else {
    Object.assign(p, { status: 'failed', error: 'Video açılamadı. Site engelliyse VPN/DNS açıkken tekrar dene.' });
  }
  renderPlayer();
}

function playerFrame(p) {
  if (p.status === 'loading') return h('div', { class: 'frame center' }, 'Yükleniyor…');
  if (p.status === 'failed') {
    return h('div', { class: 'frame center' }, h('div', {},
      h('p', {}, `Oynatılamadı: ${p.error}`),
      p.sources.filter((s) => s !== p.current).map((s) =>
        h('button', { class: 'btn', type: 'button', onclick: () => { p.current = s; loadPlayback(); } }, `${providerName(s.providerID)} kaynağını dene`))));
  }
  if (p.source.videos) {
    const variant = p.source.videos[p.variant];
    const el = h('video', { src: variant.url, controls: true, playsinline: true, autoplay: true, preload: 'auto',
      referrerpolicy: 'no-referrer', onerror: () => onVideoError(p) });
    if (p.resumeAt > 0) el.addEventListener('loadedmetadata', () => { el.currentTime = p.resumeAt; }, { once: true });
    return h('div', { class: 'frame' }, el);
  }
  // Korumalı çerçeve: site açılmaz; yeni pencere ve üst sayfayı değiştirme izni verilmez.
  // Bazı oynatıcılar korumalı çerçevede çalışmaz; kullanıcı o site için korumasız modu seçebilir.
  return h('div', { class: 'frame' }, h('iframe', {
    src: p.source.embed, title: 'Oynatıcı', referrerpolicy: 'origin', allowfullscreen: true,
    allow: 'autoplay; fullscreen; encrypted-media; picture-in-picture',
    sandbox: p.guarded ? 'allow-scripts allow-same-origin allow-presentation allow-forms' : null,
  }));
}

function setGuarded(p, guarded) {
  const list = new Set(unguardedSites());
  guarded ? list.delete(p.current.providerID) : list.add(p.current.providerID);
  store.update({ unguarded: [...list] });
  p.guarded = guarded;
  renderPlayer();
}

function playerNotes(p) {
  if (p.status !== 'ready') return null;
  const out = [];
  if (p.note) out.push(h('p', { class: 'note' }, p.note));
  if (p.source.videos) {
    out.push(h('p', { class: 'note' }, 'Video telefonun kendi oynatıcısında açılıyor; site açılmaz.'));
    if (p.source.videos.length > 1) {
      out.push(h('label', { class: 'row' }, h('span', { class: 'grow' }, 'Kalite'),
        h('select', { onchange: (e) => {
          const video = $('player').querySelector('video');
          p.resumeAt = video ? video.currentTime : 0;
          p.variant = Number(e.target.value);
          p.note = null;
          renderPlayer();
        } }, p.source.videos.map((v, i) => h('option', { value: i, selected: i === p.variant }, v.label)))));
    }
    if (p.source.fallback) {
      out.push(h('button', { class: 'link', type: 'button', onclick: () => {
        p.source = { embed: p.source.fallback }; p.note = null; renderPlayer();
      } }, 'Açılmıyorsa sitenin oynatıcısıyla aç'));
    }
  } else {
    out.push(h('p', { class: 'note' }, p.guarded
      ? 'Kaliteyi oynatıcıdaki ⚙ menüsünden seç. Site açılmaz; çıkış linkleri ve açılır pencereler engelli. '
      : 'Korumasız mod (bu site için hatırlanır): oynatıcı açılır pencere açabilir. ',
      p.guarded
        ? h('button', { class: 'link', type: 'button', onclick: () => setGuarded(p, false) }, 'Video açılmadıysa korumasız dene')
        : h('button', { class: 'link', type: 'button', onclick: () => setGuarded(p, true) }, 'Korumalı moda dön')));
  }
  return out;
}

function renderPlayer() {
  const host = $('player');
  const p = ui.player;
  if (!p) { host.hidden = true; host.replaceChildren(); document.body.classList.remove('locked'); return; }
  const v = p.current;
  const meta = [];
  if (v.views > 0) meta.push(`👁 ${compact(v.views)}`);
  if (v.rating > 0) meta.push(`👍 %${Math.round(v.rating)}`);
  if (v.durationSec > 0) meta.push(`⏱ ${clock(v.durationSec)}`);
  if (v.addedAt) meta.push(new Date(v.addedAt).toLocaleDateString('tr-TR'));
  const fav = store.isFavorite(p.video);

  host.hidden = false;
  document.body.classList.add('locked');
  host.replaceChildren(
    h('div', { class: 'sheet-top' },
      h('button', { class: 'icon', type: 'button', 'aria-label': 'Kapat', onclick: closePlayer }, '✕'),
      h('span', { class: 'grow' }),
      h('button', { class: `icon ${fav ? 'on' : ''}`, type: 'button', 'aria-label': 'Favori',
        onclick: () => { store.toggleFavorite(p.video); renderPlayer(); redrawGrid(); } }, '★')),
    playerFrame(p),
    h('div', { class: 'sheet-body' },
      playerNotes(p),
      p.sources.length > 1 && h('label', { class: 'row' }, `Kaynak (${p.sources.length} sitede var): `,
        h('select', { onchange: (e) => { p.current = p.sources[Number(e.target.value)]; loadPlayback(); } },
          p.sources.map((s, i) => h('option', { value: i, selected: s === p.current }, providerName(s.providerID))))),
      h('h2', {}, v.title),
      h('p', { class: 'meta' }, meta.join('   ')),
      h('div', { class: 'tags' }, (v.tags || []).slice(0, 25).map((t) => h('span', {}, t)))));
}

function closePlayer() { ui.player = null; renderPlayer(); renderMain(); }

// ---------------------------------------------------------------- ayarlar

function renderSettings() {
  const host = $('settings');
  if (!ui.settingsOpen) { host.hidden = true; host.replaceChildren(); document.body.classList.remove('locked'); return; }
  const st = store.settings;
  const toggle = (label, checked, onchange, sub) => h('label', { class: 'row' },
    h('span', { class: 'grow' }, label, sub && h('small', {}, sub)),
    h('input', { type: 'checkbox', checked, onchange: (e) => onchange(e.target.checked) }));

  host.hidden = false;
  document.body.classList.add('locked');
  host.replaceChildren(
    h('div', { class: 'sheet-top' }, h('h2', { class: 'grow' }, 'Ayarlar'),
      h('button', { class: 'icon', type: 'button', 'aria-label': 'Kapat', onclick: () => { ui.settingsOpen = false; renderSettings(); browser.refresh(); } }, '✕')),
    h('div', { class: 'sheet-body' },
      h('h3', {}, 'Filtreler'),
      h('label', { class: 'row' }, h('span', { class: 'grow' }, 'Yinelenenleri gizle'),
        h('select', { onchange: (e) => { store.update({ dedupeLevel: Number(e.target.value) }); renderSettings(); } },
          DEDUPE_LEVELS.map((l) => h('option', { value: l.id, selected: st.dedupeLevel === l.id }, l.title)))),
      h('p', { class: 'note' }, DEDUPE_LEVELS[st.dedupeLevel].detail + ' Gizlenen kopyalar kartta “+1” olarak görünür ve oynatıcıdaki Kaynak menüsünden seçilebilir.'),
      toggle('İzlediklerimi gizle', st.hideWatched, (on) => store.update({ hideWatched: on })),
      h('button', { class: 'btn danger', type: 'button', disabled: store.watchedCount === 0,
        onclick: () => { store.clearHistory(); renderSettings(); } }, `İzleme geçmişini temizle (${store.watchedCount} video)`),

      h('h3', {}, 'Kaynaklar'),
      getProviders().map((p) => toggle(p.name, !st.disabled.includes(p.id), (on) => {
        const d = new Set(store.settings.disabled);
        on ? d.delete(p.id) : d.add(p.id);
        store.update({ disabled: [...d] });
      }, [p.lang === 'tr' ? 'Türkçe' : 'Yabancı',
          p.relayForSearch && !net.hasRelay ? 'aracı gerekli — şu an kapalı' : null,
          !p.relayForSearch && p.relayForPlayback && !net.hasRelay ? 'oynatma için aracı gerekli' : null].filter(Boolean).join(' · '))),
      st.customSites.length > 0 && h('div', {}, st.customSites.map((site) =>
        h('button', { class: 'link', type: 'button', onclick: () => {
          store.update({ customSites: store.settings.customSites.filter((x) => x.id !== site.id) }); renderSettings();
        } }, `“${site.name}” sitesini sil`))),

      h('h3', {}, 'Site ekle (WordPress)'),
      h('form', { class: 'stack', onsubmit: (e) => {
        e.preventDefault();
        const f = e.target;
        const site = customSite(f.name.value, f.address.value, f.lang.value);
        const msg = !site ? 'Alan adı geçersiz görünüyor.' : getProviders().some((p) => p.id === site.id) ? 'Bu site zaten ekli.' : null;
        if (msg) { f.querySelector('.err').textContent = msg; return; }
        store.update({ customSites: store.settings.customSites.concat([site]) });
        renderSettings();
      } },
        h('input', { name: 'name', placeholder: 'Site adı (isteğe bağlı)', autocomplete: 'off' }),
        h('input', { name: 'address', placeholder: 'Alan adı — örn. ornek.com', autocomplete: 'off', autocapitalize: 'none', inputmode: 'url' }),
        h('label', { class: 'row' }, h('span', { class: 'grow' }, 'Arama dili'),
          h('select', { name: 'lang' }, h('option', { value: 'tr' }, 'Türkçe'), h('option', { value: 'en' }, 'İngilizce'))),
        h('button', { class: 'btn', type: 'submit' }, 'Siteyi ekle'),
        h('p', { class: 'err' })),

      h('h3', {}, 'Aracı (relay)'),
      h('p', { class: 'note' }, `Durum: ${ui.relayStatus}. Tarayıcı, izin vermeyen sitelerin arama sonuçlarını doğrudan okuyamaz; bu istekler aracıdan geçer. Videolar ve oynatıcılar aracıdan geçmez, telefonundan doğrudan yüklenir. Uygulama aracıyla aynı adreste kuruluysa burayı boş bırak.`),
      h('form', { class: 'stack', onsubmit: async (e) => {
        e.preventDefault();
        store.update({ relayURL: e.target.relay.value.trim() });
        ui.relayStatus = 'aranıyor…'; renderSettings();
        await detectRelay(); renderSettings();
      } },
        h('input', { name: 'relay', value: st.relayURL, placeholder: 'https://…workers.dev/r (isteğe bağlı)', autocomplete: 'off', autocapitalize: 'none', inputmode: 'url' }),
        h('button', { class: 'btn', type: 'submit' }, 'Kaydet ve dene')),

      h('h3', {}, 'Yerel uygulama (IPA)'),
      h('p', { class: 'note' }, 'Uygulamanın kendi oynatıcısı ve kalite menüsü olan yerel sürümü SideStore/AltStore ile internetten kurulabilir.'),
      h('a', { class: 'btn', href: 'ipa/' }, 'IPA kurulum sayfası'),

      h('h3', {}, 'Ağ, DNS ve VPN'),
      h('p', { class: 'note' }, 'Uygulama telefonunun DNS ve VPN ayarlarını olduğu gibi kullanır, onlara dokunmaz. Küçük resimler ve videolar doğrudan telefonundan yüklenir; bir site engelliyse VPN/DNS açıkken tekrar dene.'),
      h('h3', {}, 'Güvenlik'),
      h('p', { class: 'note' }, 'Reşit olmayanları çağrıştıran içerikler (loli, shota, liseli vb.) her zaman filtrelenir ve bu ayar kapatılamaz. Geçmiş ve favoriler yalnızca bu cihazda saklanır.')));
}

// ---------------------------------------------------------------- açılış

function renderAgeGate() {
  $('app').replaceChildren(h('div', { class: 'gate' },
    h('div', { class: 'gate-badge' }, '18+'),
    h('h1', {}, 'Yetişkin içerik'),
    h('p', {}, 'Bu uygulama 18 yaş ve üzeri içindir. Devam ederek 18 yaşından büyük olduğunu ve bulunduğun yerde bu içeriğe erişimin sorumluluğunun sana ait olduğunu onaylıyorsun.'),
    h('button', { class: 'btn primary', type: 'button', onclick: () => { store.update({ ageConfirmed: true }); start(); } }, '18 yaşından büyüğüm')));
}

async function start() {
  if (!store.settings.ageConfirmed) return renderAgeGate();
  $('app').replaceChildren(h('main', { id: 'main' }), h('section', { id: 'player', class: 'sheet', hidden: true }),
    h('section', { id: 'settings', class: 'sheet', hidden: true }));
  renderMain();
  await detectRelay();
  browser.refresh();
}

if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
start();
