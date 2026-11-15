// Kaynak siteler. Her kaynak: { id, name, kinds, lang, relayForSearch, search(q, net), playback(v, net) }
// q = { terms: [..], kind: 'real'|'hentai', sort, page }  (page 1'den başlar)
// playback -> { embed: url } (korumalı çerçevede açılır) ya da { video: url } (doğrudan <video>)
import { htmlDecode, stripTags, secondsFromClock, secondsFromLoose, countFromCompact, parseUTC } from './text.js';

function video(v) {
  return {
    id: `${v.providerID}:${v.remoteID}`, title: '', thumbnail: null, durationSec: 0, views: 0, rating: 0,
    addedAt: null, tags: [], embedURL: null, pageURL: null, maxHeight: null, ...v,
  };
}

const mixedTerms = (q) => (q.kind === 'hentai' ? ['hentai', ...q.terms] : q.terms);
const first = (re, s) => { const m = re.exec(s); return m ? m[1] : null; };

// ---------------------------------------------------------------- Eporner (resmi JSON API, CORS açık)

export const eporner = {
  id: 'eporner', name: 'Eporner', kinds: ['real', 'hentai'], lang: 'en', relayForSearch: false,
  parse(data, kind) {
    return (data.videos || []).map((v) => video({
      providerID: 'eporner', remoteID: String(v.id), kind, title: v.title,
      thumbnail: v.default_thumb?.src || null,
      durationSec: Number(v.length_sec) || 0, views: Number(v.views) || 0, rating: (parseFloat(v.rate) || 0) * 20,
      addedAt: parseUTC(v.added),
      tags: String(v.keywords || '').split(',').map((t) => t.trim()).filter(Boolean),
      embedURL: v.embed || null, pageURL: v.url || null,
    }));
  },
  async search(q, net) {
    const order = { newest: 'latest', mostViewed: 'most-popular', topRated: 'top-rated', longest: 'longest', shortest: 'shortest' }[q.sort] || 'most-popular';
    const p = new URLSearchParams({ query: mixedTerms(q).join(' ') || 'all', per_page: '30', page: String(q.page),
      thumbsize: 'big', order, gay: '0', lq: '1', format: 'json' });
    return this.parse(await net.json(`https://www.eporner.com/api/v2/video/search/?${p}`), q.kind);
  },
  async playback(v) { return { embed: v.embedURL }; },
};

// ---------------------------------------------------------------- Pornhub / RedTube (webmaster JSON API)

function webmasterParse(data, providerID, kind, embedFor) {
  return (data.videos || []).map((entry) => {
    const v = entry.video || entry;
    return video({
      providerID, remoteID: String(v.video_id), kind, title: v.title,
      thumbnail: v.default_thumb || v.thumb || null,
      durationSec: secondsFromClock(v.duration), views: Number(v.views) || 0, rating: parseFloat(v.rating) || 0,
      addedAt: parseUTC(v.publish_date), tags: (v.tags || []).map((t) => t.tag_name),
      embedURL: v.embed_url || embedFor(v.video_id), pageURL: v.url || null,
    });
  });
}
const wmOrder = (s) => ({ newest: 'newest', topRated: 'rating' }[s] || 'mostviewed');

export const pornhub = {
  id: 'pornhub', name: 'Pornhub', kinds: ['real', 'hentai'], lang: 'en', relayForSearch: true,
  parse: (data, kind) => webmasterParse(data, 'pornhub', kind, (id) => `https://www.pornhub.com/embed/${id}`),
  async search(q, net) {
    const p = new URLSearchParams({ search: mixedTerms(q).join(' '), ordering: wmOrder(q.sort), page: String(q.page), thumbsize: 'large_hd' });
    return this.parse(await net.json(`https://www.pornhub.com/webmasters/search?${p}`, { relay: true }), q.kind);
  },
  async playback(v) { return { embed: v.embedURL }; },
};

export const redtube = {
  id: 'redtube', name: 'RedTube', kinds: ['real', 'hentai'], lang: 'en', relayForSearch: true,
  parse: (data, kind) => webmasterParse(data, 'redtube', kind, (id) => `https://embed.redtube.com/?id=${id}`),
  async search(q, net) {
    const p = new URLSearchParams({ data: 'redtube.Videos.searchVideos', output: 'json', search: mixedTerms(q).join(' '),
      ordering: wmOrder(q.sort), page: String(q.page), thumbsize: 'big' });
    return this.parse(await net.json(`https://api.redtube.com/?${p}`, { relay: true }), q.kind);
  },
  async playback(v) { return { embed: v.embedURL }; },
};

// ---------------------------------------------------------------- XVideos / XNXX (arama sayfası HTML'i)

export function parseXSearch(html, site, kind) {
  const out = [];
  const starts = [...html.matchAll(/<div[^>]*\bid="video_[^"]*"[^>]*>/gi)];
  starts.forEach((m, i) => {
    const end = i + 1 < starts.length ? starts[i + 1].index : Math.min(html.length, m.index + 6000);
    const openTag = m[0], block = html.slice(m.index, end);
    const numericID = first(/data-id="(\d+)"/i, openTag);
    const eid = first(/data-eid="([0-9a-z]+)"/i, openTag);
    const href = first(/href="([^"]*\/video[.\-][^"]+)"/i, block);
    const title = htmlDecode(first(/<a[^>]*\btitle="([^"]+)"/i, block) || '');
    if (!numericID || !href || !title) return;
    let thumb = first(/<img[^>]*\bdata-src="(https?:\/\/[^"]+)"/i, block);
    if (!thumb) { const src = first(/<img[^>]*\bsrc="(https?:\/\/[^"]+)"/i, block); if (src && !src.includes('blank')) thumb = src; }
    const meta = stripTags(first(/<p class="metadata">([\s\S]*?)<\/p>/i, block) || '');
    const duration = secondsFromLoose(first(/class="duration">([^<]+)</i, block) || '') || secondsFromLoose(meta);
    const viewsText = first(/([\d.,]+\s*[kKmM]?)\s*Views/i, meta) || first(/^\s*([\d.,]+[kKmM]?)\s/, meta);
    const height = first(/>\s*(\d{3,4})p\s*</, block);
    out.push(video({
      providerID: site.id, remoteID: numericID, kind, title,
      thumbnail: thumb ? htmlDecode(thumb) : null, durationSec: duration,
      views: viewsText ? countFromCompact(viewsText) : 0, rating: parseFloat(first(/(\d{1,3})\s*%/, meta) || '0') || 0,
      embedURL: `https://${site.host}/embedframe/${eid || numericID}`,
      pageURL: new URL(htmlDecode(href), `https://${site.host}/`).href,
      maxHeight: height ? parseInt(height, 10) : null,
    }));
  });
  return out;
}

function xProvider(site) {
  return {
    id: site.id, name: site.name, kinds: ['real', 'hentai'], lang: 'en', relayForSearch: true,
    searchURL: site.searchURL,
    async search(q, net) {
      const url = site.searchURL(mixedTerms(q).join(' '), q.page, q.sort);
      if (!url) return [];
      return parseXSearch(await net.text(url, { relay: true }), site, q.kind);
    },
    // Sitenin gömülü oynatıcısı telefonun kendi bağlantısından yüklenir (aracıdan geçmez).
    async playback(v) { return { embed: v.embedURL }; },
  };
}

export const xvideos = xProvider({
  id: 'xvideos', name: 'XVideos', host: 'www.xvideos.com',
  searchURL(terms, page, sort) {
    if (!terms) return page <= 1 ? 'https://www.xvideos.com/' : `https://www.xvideos.com/new/${page - 1}`;
    const p = new URLSearchParams({ k: terms, p: String(page - 1) });
    const s = { newest: 'uploaddate', topRated: 'rating', longest: 'length', mostViewed: 'views' }[sort];
    if (s) p.set('sort', s);
    return `https://www.xvideos.com/?${p}`;
  },
});

export const xnxx = xProvider({
  id: 'xnxx', name: 'XNXX', host: 'www.xnxx.com',
  searchURL(terms, page) {
    if (!terms) return null;
    const q = terms.split(/\s+/).map(encodeURIComponent).join('+');
    return `https://www.xnxx.com/search/${q}` + (page > 1 ? `/${page - 1}` : '');
  },
});

// ---------------------------------------------------------------- WordPress siteleri (Doeda vb.)

const IGNORED_FRAME_HOSTS = ['exoclick.com', 'exosrv.com', 'juicyads.com', 'trafficjunky.net', 'trafficjunky.com', 'popads.net',
  'doubleclick.net', 'googlesyndication.com', 'facebook.com', 'twitter.com', 'google.com', 'googletagmanager.com',
  'youtube.com', 'histats.com', 'yandex.ru', 'adsterra.com', 'clickadu.com', 'propellerads.com', 'tsyndicate.com'];

/** Yazı sayfasının HTML'inden oynatıcıyı bulur: { video } (doğrudan dosya) ya da { embed } (oynatıcı çerçevesi). */
export function findPlayer(html, pageURL) {
  const direct = first(/<(?:video|source)[^>]*\bsrc="(https?:[^"]+\.(?:m3u8|mp4)[^"]*)"/i, html)
    || first(/"contentUrl"\s*:\s*"(https?:[^"]+\.(?:m3u8|mp4)[^"]*)"/i, html);
  if (direct) return { video: htmlDecode(direct).replaceAll('\\/', '/') };
  for (const m of html.matchAll(/<iframe[^>]*\b(?:data-lazy-src|data-src|src)="([^"]+)"/gi)) {
    let raw = htmlDecode(m[1]);
    if (raw.startsWith('//')) raw = 'https:' + raw;
    if (!/^https?:/i.test(raw) && !raw.startsWith('/')) continue;
    let u;
    try { u = new URL(raw, pageURL); } catch { continue; }
    const host = u.hostname.toLowerCase();
    if (IGNORED_FRAME_HOSTS.some((h) => host === h || host.endsWith('.' + h))) continue;
    return { embed: u.href };
  }
  return null;
}

export function parseWordPress(posts, site, kind) {
  return posts.map((p) => {
    const title = stripTags(p.title?.rendered || '').trim();
    if (!title || !p.link) return null;
    const media = p._embedded?.['wp:featuredmedia']?.[0];
    const sizes = media?.media_details?.sizes || {};
    const thumb = sizes.medium_large?.source_url || sizes.large?.source_url || media?.source_url || sizes.medium?.source_url || null;
    const tags = (Array.isArray(p.class_list) ? p.class_list : [])
      .filter((c) => c.startsWith('category-') || c.startsWith('tag-'))
      .map((c) => c.slice(c.indexOf('-') + 1).replace(/-(\d+|x|p)$/, '').replaceAll('-', ' '));
    return video({
      providerID: site.id, remoteID: String(p.id), kind, title, thumbnail: thumb,
      views: parseInt(p.views, 10) || 0, addedAt: parseUTC(p.date_gmt), tags, pageURL: p.link,
    });
  }).filter(Boolean);
}

export function wordpress(site) {
  const insecure = site.baseURL.startsWith('http://');   // https sayfadan http okunamaz -> aracı
  return {
    id: site.id, name: site.name, kinds: site.hentaiOnly ? ['hentai'] : ['real', 'hentai'], lang: site.lang,
    relayForSearch: insecure, relayForPlayback: true, site,
    searchURL(q) {
      const terms = (site.hentaiOnly ? q.terms : mixedTerms(q)).join(' ');
      const p = new URLSearchParams({ per_page: '20', page: String(q.page), _embed: 'wp:featuredmedia',
        _fields: 'id,date_gmt,link,title,views,class_list,_links,_embedded' });
      if (terms) { p.set('search', terms); p.set('orderby', q.sort === 'newest' ? 'date' : 'relevance'); }
      return `${site.baseURL}/wp-json/wp/v2/posts?${p}`;
    },
    async search(q, net) {
      try {
        return parseWordPress(await net.json(this.searchURL(q), { relay: insecure }), site, q.kind);
      } catch (e) {
        if (e?.status === 400) return [];   // WordPress son sayfadan sonrasında 400 döndürür
        throw e;
      }
    },
    async playback(v, net) {
      const html = await net.text(v.pageURL, { relay: true });
      const player = findPlayer(html, v.pageURL);
      if (!player) throw new Error('Oynatılabilir kaynak bulunamadı.');
      return player;
    },
  };
}

export const DOEDA = { id: 'wp-doeda.com', name: 'Doeda', baseURL: 'http://www.doeda.com', lang: 'tr', hentaiOnly: false };
export const DOEDA_ONE = { id: 'wp-doeda.one', name: 'Doeda One', baseURL: 'https://www.doeda.one', lang: 'tr', hentaiOnly: false };

/** Ayarlar'dan girilen alan adından site oluşturur. */
export function customSite(name, address, lang = 'tr', hentaiOnly = false) {
  let a = String(address || '').trim();
  if (!a) return null;
  if (!/^https?:/i.test(a)) a = 'https://' + a;
  a = a.replace(/\/+$/, '');
  let host;
  try { host = new URL(a).hostname.toLowerCase(); } catch { return null; }
  if (!host.includes('.')) return null;
  return { id: `wp-${host}`, name: String(name || '').trim() || host, baseURL: a, lang, hentaiOnly };
}

export function builtInProviders() {
  return [eporner, xvideos, xnxx, pornhub, redtube, wordpress(DOEDA), wordpress(DOEDA_ONE)];
}
