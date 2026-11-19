# Vitrin

Kişisel kullanım için, birden çok yetişkin video sitesinden içerik toplayan uygulama. İki sürümü var:

| | Yerel uygulama (bu klasör) | Web sürümü (`web/`) |
|---|---|---|
| Kurulum | `.ipa` — Sideloadly/AltStore ile, bilgisayar gerekir, ücretsiz Apple ID ile 7 günde bir yenilenir | **Profil (Web Clip)** — Safari'den, bilgisayarsız, süresi dolmaz |
| Kaynaklar | 7 kaynağın hepsi doğrudan | Aracı (ücretsiz Cloudflare Worker) ile 7 kaynak; aracısız yalnızca Eporner |
| Oynatma | XVideos, XNXX, Doeda: uygulamanın kendi oynatıcısı + kalite menüsü; diğerleri kilitli gömülü oynatıcı | Her zaman korumalı gömülü oynatıcı |
| Durum | Xcode'da derleniyor, simülatörde çalışıyor (GitHub Actions) | Testleri ve tarayıcı denemesi geçiyor; henüz yayınlanmadı |

Web sürümünün kurulumu: [`web/README.md`](web/README.md). App Store bu tür uygulamaları kabul etmez.

## Özellikler

| İstek | Nasıl yapıldı |
|---|---|
| DNS/VPN'den etkilensin, engellemesin | Yalnızca `URLSession` varsayılan ayarı kullanılır; özel DNS/DoH/proxy yok (`Core/HTTP.swift`). iOS'taki DNS profili ve VPN tüneli olduğu gibi kullanılır. Engelli bir kaynak için hata mesajı "VPN/DNS'i kontrol et" der. |
| Farklı siteler | 7 yerleşik kaynak (aşağıda) + Ayarlar'dan alan adı yazarak eklenen WordPress siteleri. |
| Türk siteleri | **Doeda** (doeda.com) ve **Doeda One** (doeda.one) yerleşik. Türk sitelerine arama terimleri Türkçe, yabancı sitelere İngilizce gönderilir. |
| Kategoriler + birlikte arama | 26 gerçek + 18 hentai kategori. Birden fazla seçince **VE** (hepsi birlikte) ya da **VEYA** (her biri ayrı aranıp birleştirilir). |
| Sıralama | İlgili, En yeni, En çok izlenen, En yüksek puan, En uzun, En kısa. Önce sitenin kendi sıralaması istenir, sonra birleşik liste uygulamada yeniden sıralanır. |
| Aynı video tekrar görünmesin | **Yinelenen filtresi** (Kapalı / Normal / Sıkı) + **İzlediklerimi gizle**. Ayrıntı aşağıda. |
| Favoriler | Oynatıcıdaki ★ ile kaydedilir; ayrı sekmede listelenir (cihazda saklanır). |
| Video açılırken site açılmasın | Doğrudan akış varsa uygulamanın kendi oynatıcısı (`AVPlayer`). Yoksa yalnızca oynatıcı çerçevesi, uygulamanın ürettiği boş bir sayfanın içinde açılır: siteye hiç istek yapılmaz, çıkış linkleri / pop-up'lar / `window.open` engellenir, reklam ağları bloklanır, çerez saklanmaz. |
| Kalite ayarı | Ayarlar'da varsayılan kalite; oynatıcının sağ üstünde Otomatik / 1080p / 720p… menüsü (izlerken değişir, kaldığı yerden devam eder). Gömülü oynatıcılarda o oynatıcının kendi ⚙︎ menüsü. |
| Ücretsiz yapay zekâ | **Gemini** ve **GPT** (aşağıda). ✨ düğmesi yazdığın tarifi iki dilde etiketlere çevirir. |

**Güvenlik:** Reşit olmayanları çağrıştıran içerikler (loli, shota, liseli, "16 yaşında" vb.) ve hayvan içeren içerikler
başlık/etiket/arama terimi düzeyinde her zaman süzülür; bu kapatılamaz. Açılışta 18+ onayı istenir.

## Kaynaklar

Aşağıdaki sonuçlar GitHub Actions'taki **canlı denemeden** (sitelere gerçek istek) alınmıştır:

| Kaynak | Yöntem | Canlı deneme sonucu |
|---|---|---|
| XVideos | Arama sayfası HTML'i | 24 sonuç; yerel oynatıcı: Otomatik, 480p, 360p, 250p; akışa erişildi |
| XNXX | Arama sayfası HTML'i | 36 sonuç; yerel oynatıcı: Otomatik, 480p, 360p; akışa erişildi |
| Eporner | Resmi JSON API | 30 sonuç; gömülü oynatıcı |
| Pornhub | Webmaster JSON API | 30 sonuç; gömülü oynatıcı |
| RedTube | Webmaster JSON API | 20 sonuç; gömülü oynatıcı |
| Doeda (doeda.com) | WordPress JSON API | 20 sonuç; yerel oynatıcı: 720p |
| Doeda One (doeda.one) | WordPress JSON API | 20 sonuç; gömülü oynatıcı çerçevesi (jetplayer) |

Deneme bir kez, GitHub'ın ABD'deki sunucularından yapıldı; Türkiye'den VPN/DNS ile sonuç farklı olabilir. Siteler
yapısını değiştirirse ilgili kaynak bozulur; her gönderimde canlı deneme yeniden çalışır ve tabloyu iş özetine yazar.

**hanime.tv kaldırıldı:** arama sunucusu artık yok, yeni API'si şifreli bir el sıkışma istiyor. Hentai aramaları
karma sitelerde ("hentai …" olarak) yapılıyor. Tube8 ve YouPorn'un herkese açık API'leri kapatılmış;
hentaihaven / hentai.tv / hentaiturk standart bir API sunmuyor.

### Kendi siteni eklemek
Ayarlar → **Site ekle (WordPress)** → alan adını yaz (örn. `ornek.com`), dilini seç. Site WordPress'in standart
`/wp-json/wp/v2/posts` uç noktasını açık bırakıyorsa çalışır (ör. `maheir.com` çalışıyor ama küçük resim vermiyor;
`kopeda.com` bu uç noktayı kapatmış). Alan adı değişen sitelerde eskisini silip yenisini eklemen yeter.
Başka türden bir site için `ContentProvider` protokolünü uygulayan bir dosya yazıp `ProviderRegistry.builtIn`'e eklenir.

## Filtreler

**Yinelenen filtresi** (`Core/Filters/DuplicateFilter.swift`) her videonun başlığını sadeleştirir (küçük harf, Türkçe
karakterler, "HD / full / video / izle" gibi anlamsız kelimeler atılır) ve süresiyle birlikte karşılaştırır:

- **Normal:** Başlık kelimeleri aynı (ya da %75+ örtüşüyor) **ve** süre birkaç saniye içinde aynıysa tek kart.
  Süresi bilinmeyen (Türk siteleri) videolarda yalnızca birebir aynı ve yeterince ayırt edici başlıklar birleştirilir.
- **Sıkı:** %50 örtüşme yeter; süresi saniyesi saniyesine aynı olanlarda daha azı da. Yeniden adlandırılmış kopyaları
  da yakalar ama nadiren farklı videoları birleştirebilir.
- Aynı başlık + farklı süre, ya da "Bölüm 1 / Bölüm 2" gibi farklı numaralar **ayrı** kalır.
- Gizlenen kopya atılmaz: kartta "Pornhub +1" olarak görünür, oynatıcıdaki **Kaynak** menüsünden o siteye geçilebilir
  (bir kaynak açılmazsa diğerini dene). Aynı gruptaki kopyalardan doğrudan akış veren / çözünürlüğü yüksek olan tutulur.

Gerçek veriyle deneme: aynı aramanın Pornhub + RedTube + XVideos + XNXX sonuçlarındaki 102 videodan 8'i gerçekten
aynı videoydu (Pornhub ⇄ RedTube); Normal mod tam bu 8'ini gizledi, süresi aynı ama başlığı farklı 4 çifte dokunmadı.

**İzlediklerimi gizle:** Açtığın videolar cihazda (yalnızca cihazda) kaydedilir; aynı video başka siteden gelse de
gizlenir. Ayarlar'dan geçmiş temizlenebilir.

## Ücretsiz yapay zekâ (Gemini ve GPT)

Arama kutusuna tarifi yaz ("sarışın olgun kadın ofiste masaj"), ✨'a bas → yabancı siteler için İngilizce, Türk siteleri
için Türkçe etiketler üretilir. Ayarlar → Motor: *Otomatik (Gemini → GPT → sözlük)*.

- **Gemini:** aistudio.google.com → "Get API key" (kart gerekmez). Varsayılan model `gemini-3.5-flash-lite`.
- **GPT:** OpenAI uyumlu herhangi bir servis. Hazır seçenekler:
  - *GitHub Models* — GitHub hesabıyla ücretsiz GPT (`openai/gpt-4o`); anahtar = `models:read` izinli kişisel erişim belirteci.
  - *OpenRouter* — sonu `:free` ile biten modeller ücretsiz.
  - *Pollinations*, kendi *OpenAI* anahtarın (ücretli), evdeki bilgisayarda *Ollama* (tamamen yerel).
- Anahtar yoksa ya da servis yanıt vermezse yerleşik TR↔EN sözlük kullanılır (internet gerekmez).

Model adları ve ücretsiz kotalar zamanla değişir; Ayarlar'dan elle yazılabilir. Anahtarlar Keychain'de saklanır.
✨ kullandığında yazdığın metin seçtiğin servise gönderilir; ücretsiz katmanlarda bu metinler servis tarafından
ürün geliştirmede kullanılabilir.

## Kurulum

### Mac varsa
```bash
brew install xcodegen
xcodegen generate
open Vitrin.xcodeproj
```
Signing & Capabilities'te kendi Apple ID'ni seç, `PRODUCT_BUNDLE_IDENTIFIER`'ı benzersiz yap, iPhone'a çalıştır.
(Ücretsiz Apple ID ile imza 7 gün geçerlidir.)

### İnternetten kurulum (IPA)
Her iOS derlemesinden sonra IPA kendiliğinden sitenin `ipa/` adresine konur:

- **Kurulum sayfası:** `https://vitrin.vitrin-web.workers.dev/ipa/` — iPhone'da Safari ile aç.
- **SideStore/AltStore kaynağı:** `https://vitrin.vitrin-web.workers.dev/ipa/kaynak.json` — bir kez eklenir,
  sonraki sürümler uygulamanın içinden güncellenir.
- **Doğrudan dosya:** `https://vitrin.vitrin-web.workers.dev/ipa/Vitrin.ipa` — Sideloadly ya da telefondaki bir imzalama uygulaması için.

IPA imzasızdır; Safari'den doğrudan kurulmaz. SideStore/AltStore/Sideloadly onu kendi Apple ID'nle imzalar
(ücretsiz Apple ID ile 7 gün; SideStore internetten yeniler). SideStore'un ilk kurulumu için bir kez bilgisayar gerekir.

Yeni sürümün siteye kendiliğinden yayınlanması için depoya `CLOUDFLARE_API_TOKEN` ve `CLOUDFLARE_ACCOUNT_ID`
secret'larının eklenmiş olması gerekir (adımlar `web/README.md`). Eklenmemişse IPA yine depoya işlenir,
ama site elle yayınlanana kadar eski sürümü gösterir.

### Derleme
Depoya her gönderimde `.github/workflows/vitrin-ios.yml` GitHub'ın macOS makinesinde Xcode ile derler, uygulamayı
simülatörde açıp dener ve **Vitrin.ipa** üretir (ayrıca *Actions → Vitrin iOS → Artifacts*).

Not: depo özel olduğu için macOS derlemeleri GitHub'ın ücretsiz dakika kotasından 10 kat hızlı düşer
(bir çalışma ≈ 7 dakika ≈ 70 kota dakikası; ücretsiz planda ayda 2000). Yalnızca test/yazı değişikliklerinde
commit mesajına `[ios-atla]` eklenirse macOS derlemesi atlanır.

## Geliştirme

```
Vitrin/Core/   Arayüzden bağımsız mantık: kaynaklar, filtreler, yapay zekâ, arama planı
Vitrin/App/    SwiftUI arayüzü, oynatıcılar
Tests/         Çekirdek testleri
web/           Profil ile kurulan web sürümü ve aracı
```
`swift test` çekirdeği macOS ya da Linux'ta test eder. Sitelere gerçek istek atan deneme:
`VITRIN_LIVE=1 swift test --filter LiveProviderTests`. Kaydettiğin gerçek yanıtlarla denemek için:
`VITRIN_SAMPLES=/klasör swift test` (dosya adları `Tests/VitrinCoreTests/RealSampleTests.swift` içinde).

GitHub Actions iş akışları (depo kökünde `.github/workflows/`):

| İş akışı | Ne yapar |
|---|---|
| `vitrin-ios.yml` | Çekirdek testleri (Linux), canlı kaynak denemesi, web uyumluluk ölçümü, Xcode derlemesi + simülatör denemesi + IPA |
| `vitrin-web.yml` | Web sürümünün testleri, tarayıcıda uçtan uca deneme, (anahtar varsa) Cloudflare'e yayın |
| `vitrin-ai.yml` | `.github/ai/vitrin-istem.md` dosyasındaki soruları ücretsiz yapay zekâlara sorar (aşağıya bak) |

### Geliştirirken yapay zekâya danışma
`.github/ai/vitrin-istem.md` değiştirilip gönderilince iş akışı soruları sorar, yanıtları iş özetine yazar.
- **GPT (Pollinations):** anahtarsız çalışır ama ücretsiz kullanımda 45 saniyede bir yanıt ve kısa yanıt sınırı var.
- **Gemini:** depo → *Settings → Secrets and variables → Actions* → `GEMINI_API_KEY` eklenirse sorulur
  (anahtar aistudio.google.com'dan ücretsiz).
- **GitHub Models (ücretsiz GPT-4.1):** şu an bu depodan erişilemiyor (uç nokta yalnızca "OK" döndürüyor).

## Bilinen sınırlamalar

- XVideos/XNXX ve Türk siteleri sayfa yapısına bağlıdır; site tasarımını değiştirirse ilgili dosya güncellenmelidir.
  Bir kaynak bozulursa yalnızca o hata verir, diğerleri çalışmaya devam eder.
- Web sürümünde oynatma her zaman gömülü oynatıcıyladır; uygulama içi kalite menüsü yalnızca yerel sürümde var.
- Türk sitelerinin API'si video süresi vermez: bu kaynaklarda "en uzun/en kısa" sıralaması ve süreye dayalı
  yinelenen tespiti çalışmaz.
- Türk siteleri başlıkları Türkçe yeniden yazdığı için, aynı videonun yabancı sitedeki kopyasıyla eşleştirilemez.
- doeda.com yalnızca şifresiz `http` sunuyor; bu siteyle trafiğin VPN yoksa ağ sağlayıcına açık olur.
- Bazı siteler belirli ülkeleri kendileri engelliyor; bu durumda VPN konumunu değiştirmek gerekir.
- İndirme özelliği yoktur; yalnızca izleme.
