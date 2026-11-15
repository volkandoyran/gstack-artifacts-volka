// Ağ katmanı. Web sürümü tarayıcıda çalıştığı için bir siteden veri okuyabilmesi o sitenin
// CORS izni vermesine bağlıdır. İzin vermeyen siteler için istekler "aracı"dan (relay) geçer:
// aracı, uygulamayla aynı adreste çalışan küçük bir Cloudflare Worker'dır (relay/worker.js).
// Videolar ve oynatıcılar hiçbir zaman aracıdan geçmez; doğrudan telefondan yüklenir.

export class RelayNeededError extends Error {
  constructor() { super('Bu kaynak için aracı gerekli'); this.name = 'RelayNeededError'; }
}

export class HttpError extends Error {
  constructor(status, host) { super(`${host} hata döndürdü (HTTP ${status})`); this.name = 'HttpError'; this.status = status; }
}

export function createNet({ relayBase = null, fetchImpl = (...a) => fetch(...a) } = {}) {
  const net = {
    relayBase,
    get hasRelay() { return !!net.relayBase; },

    relayURL(url, referer) {
      return `${net.relayBase}?u=${encodeURIComponent(url)}` + (referer ? `&ref=${encodeURIComponent(referer)}` : '');
    },

    /** @returns {Promise<string>} yanıt gövdesi */
    async text(url, { relay = false, method = 'GET', form = null, json = null, referer = null } = {}) {
      const init = { method, credentials: 'omit', referrerPolicy: 'no-referrer', headers: {} };
      if (form) {
        init.body = new URLSearchParams(form).toString();
        init.headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
      } else if (json) {
        init.body = JSON.stringify(json);
        init.headers['Content-Type'] = 'application/json';
      }
      let target = url;
      if (relay) {
        if (!net.relayBase) throw new RelayNeededError();
        target = net.relayURL(url, referer);
      }
      const res = await fetchImpl(target, init);
      if (!res.ok) throw new HttpError(res.status, new URL(url).host);
      return res.text();
    },

    async json(url, options) {
      return JSON.parse(await net.text(url, options));
    },

    /** Şifresiz (http) görseller https sayfada yüklenemez; aracı varsa oradan geçirilir. */
    asset(url) {
      if (!url) return url;
      return url.startsWith('http://') && net.relayBase ? net.relayURL(url) : url;
    },
  };
  return net;
}

/** Kullanıcıya gösterilecek Türkçe hata metni. */
export function describeError(e) {
  if (e instanceof RelayNeededError) return 'Bu kaynak tarayıcıdan doğrudan okunamıyor; aracı (relay) gerekli.';
  if (e instanceof HttpError) {
    return e.status === 403 || e.status === 451 ? `${e.message}. VPN/DNS açık mı?` : e.message;
  }
  if (e instanceof SyntaxError) return 'Site yanıt biçimini değiştirmiş; kaynak güncellenmeli.';
  if (e instanceof TypeError) return 'Bağlantı kurulamadı — site engelli olabilir. VPN/DNS açıkken tekrar dene.';
  return e?.message || String(e);
}
