# Vitrin — web sürümü (profil ile kurulum)

iPhone'a bilgisayarsız, **profil (Web Clip)** olarak kurulan sürüm. Safari'de uygulamanın adresi açılır,
**Kur**'a basılır, profil yüklenir; simge ana ekrana gelir ve uygulama tam ekran açılır. Süresi dolmaz,
Apple ID ya da bilgisayar gerekmez.

## Web sürümü neden ayrı ve neyi farklı yapıyor

Web sürümü tarayıcıda çalışır. Tarayıcı, bir siteden veri okuyabilmek için o sitenin izin vermesini ister (CORS).
GitHub Actions'taki ölçüme göre (`Vitrin iOS` → *Web sürümü için uyumluluk ölçümü*):

| Kaynak | Tarayıcıdan doğrudan arama | Oynatma |
|---|---|---|
| Eporner | ✅ izin veriyor | gömülü oynatıcı |
| Doeda One | ✅ izin veriyor | oynatıcıyı bulmak için aracı gerekir |
| Doeda (doeda.com) | ❌ site yalnızca şifresiz http | aracı gerekir |
| Pornhub, RedTube | ❌ izin yok | gömülü oynatıcı (arama aracıdan) |
| XVideos, XNXX | ❌ izin yok | gömülü oynatıcı (arama aracıdan) |

İzin vermeyen kaynaklar için istekler **aracı**dan (relay) geçer: uygulamayla aynı adreste çalışan küçük bir
Cloudflare Worker (`relay/worker.js`). Aracı yalnızca arama sayfalarını/API'lerini getirir.

- Videolar ve oynatıcılar **aracıdan geçmez**; telefonundan doğrudan yüklenir (DNS/VPN ayarın geçerlidir).
- Aracı yalnızca izin listesindeki alan adlarına gider, hiçbir şey saklamaz, kayıt tutmaz.
- Arama istekleri aracıdan geçtiği için aramalar Türkiye'deki site engellerinden etkilenmez; videoyu oynatırken
  ise telefonunun bağlantısı kullanılır (site engelliyse VPN/DNS gerekir).
- Aracı yoksa uygulama yine çalışır ama yalnızca Eporner'da arayıp oynatabilir.

Yerel (IPA) sürümden farkları: oynatma her zaman sitenin gömülü oynatıcısıyladır (kalite o oynatıcının ⚙ menüsünden
seçilir); çerçeve korumalıdır (`sandbox`: yeni pencere açamaz, uygulamayı başka sayfaya götüremez). Yapay zekâ
düğmesi yoktur; Türkçe↔İngilizce çeviri yerleşik sözlükle yapılır.

## Yayınlama (bir kez, ~10 dakika)

GitHub Pages bu uygulama için uygun değil: aracı çalıştıramaz, depoyu herkese açık yapmayı gerektirir ve
GitHub'ın kuralları yetişkin içerik sitelerini barındırmaya izin vermez. Bunun yerine ücretsiz Cloudflare kullanılır;
dosyalar ve aracı tek bir adreste durur.

1. **cloudflare.com**'da ücretsiz hesap aç. Sol menüden **Workers & Pages**'e bir kez gir (hesabına bir
   `…workers.dev` alt alan adı tanımlanır).
2. **Account ID**: Workers & Pages sayfasının sağ tarafında yazar; kopyala.
3. **API Token**: sağ üst profil → *My Profile → API Tokens → Create Token* → **Edit Cloudflare Workers** şablonu →
   oluştur ve kopyala.
4. GitHub'da bu depo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `CLOUDFLARE_ACCOUNT_ID` = 2. adımdaki değer
   - `CLOUDFLARE_API_TOKEN` = 3. adımdaki değer
5. **Actions → Vitrin web → en son çalışma → Re-run all jobs**. Bitince iş özetinde adres yazar:
   `https://vitrin.<senin-adın>.workers.dev`
6. iPhone'da **Safari** ile o adresi aç → **Kur** → profil indirme uyarısında **İzin Ver**.
7. **Ayarlar → Profil İndirildi → Yükle** (görünmezse *Ayarlar → Genel → VPN ve Aygıt Yönetimi*). Simge ana ekrana gelir.

Profil imzasız olduğu için iOS "Doğrulanmadı" yazar; beklenen bir durumdur. Profil yalnızca ana ekrana simge ekler,
başka ayar değiştirmez ve *VPN ve Aygıt Yönetimi*'nden kaldırılabilir.

Adres herkese açıktır ama arama motorlarına kapalıdır (`noindex`) ve kimseyle paylaşmadığın sürece bilinmez.
Daha zor tahmin edilsin istersen `wrangler.toml` içindeki `name = "vitrin"` satırını rastgele bir adla değiştir.

### Kendi eklediğin siteler
Ayarlar'dan eklediğin WordPress sitelerinin oynatıcısını bulabilmesi için aracıya o alan adına izin vermen gerekir:
Cloudflare → Worker → *Settings → Variables* → `EXTRA_HOSTS` = `ornek.com,www.ornek.com`.

## Geliştirme

```
site/            Uygulama (derleme adımı yok; düz HTML/CSS/JS modülleri)
  core/          Arayüzden bağımsız mantık: kaynaklar, filtreler, sözlük, arama planı
relay/           Cloudflare Worker (dosya sunumu + aracı + profil üretimi)
tools/           Sabit barındırma için profil dosyası üretici
tests/           Birim testleri ve tarayıcıda uçtan uca deneme
```

```bash
node --test tests/*.test.mjs        # 16 birim testi
node tests/smoke.mjs ekranlar/       # gerçek tarayıcıda uçtan uca deneme (Playwright gerekir)
npx wrangler dev                     # yerelde çalıştır
npx wrangler deploy                  # elle yayınla
```

Uçtan uca denemede siteler yerine sahte, nötr veriler kullanılır; aracı kodu aynen çalışır.
