# Vitrin

Kişisel kullanım için, birden çok yetişkin video sitesinden içerik toplayan SwiftUI (iOS 17+) uygulaması.
App Store bu tür uygulamaları kabul etmez; **yan yükleme (sideload)** ile kurulur.

## Özellikler

| İstek | Nasıl yapıldı |
|---|---|
| DNS/VPN'den etkilensin, engellemesin | Yalnızca `URLSession` varsayılan ayarı kullanılır; özel DNS/DoH/proxy yok (`Core/HTTP.swift`). iOS'taki DNS profili ve VPN tüneli olduğu gibi kullanılır. Engelli bir kaynak için hata mesajı "VPN/DNS'i kontrol et" der. |
| Farklı siteler | 8 yerleşik kaynak (aşağıda) + Ayarlar'dan alan adı yazarak eklenen WordPress siteleri. |
| Türk siteleri | **Doeda** (doeda.com) ve **Doeda One** (doeda.one) yerleşik. Türk sitelerine arama terimleri Türkçe, yabancı sitelere İngilizce gönderilir. |
| Kategoriler + birlikte arama | 26 gerçek + 18 hentai kategori. Birden fazla seçince **VE** (hepsi birlikte) ya da **VEYA** (her biri ayrı aranıp birleştirilir). |
| Sıralama | İlgili, En yeni, En çok izlenen, En yüksek puan, En uzun, En kısa. Önce sitenin kendi sıralaması istenir, sonra birleşik liste uygulamada yeniden sıralanır. |
| Aynı video tekrar görünmesin | **Yinelenen filtresi** (Kapalı / Normal / Sıkı) + **İzlediklerimi gizle**. Ayrıntı aşağıda. |
| Video açılırken site açılmasın | Doğrudan akış varsa uygulamanın kendi oynatıcısı (`AVPlayer`). Yoksa yalnızca oynatıcı çerçevesi, uygulamanın ürettiği boş bir sayfanın içinde açılır: siteye hiç istek yapılmaz, çıkış linkleri / pop-up'lar / `window.open` engellenir, reklam ağları bloklanır, çerez saklanmaz. |
| Kalite ayarı | Ayarlar'da varsayılan kalite; oynatıcının sağ üstünde Otomatik / 1080p / 720p… menüsü (izlerken değişir, kaldığı yerden devam eder). Gömülü oynatıcılarda o oynatıcının kendi ⚙︎ menüsü. |
| Ücretsiz yapay zekâ | **Gemini** ve **GPT** (aşağıda). ✨ düğmesi yazdığın tarifi iki dilde etiketlere çevirir. |

**Güvenlik:** Reşit olmayanları çağrıştıran içerikler (loli, shota, liseli, "16 yaşında" vb.) ve hayvan içeren içerikler
başlık/etiket/arama terimi düzeyinde her zaman süzülür; bu kapatılamaz. Açılışta 18+ onayı istenir.

## Kaynaklar

| Kaynak | Yöntem | Oynatma | Durum |
|---|---|---|---|
| XVideos | Arama sayfası HTML'i | Yerel oynatıcı (HLS, kalite menüsü) | Arama ve akış çıkarma gerçek sayfalarla test edildi |
| XNXX | Arama sayfası HTML'i | Yerel oynatıcı (HLS, kalite menüsü) | Arama gerçek sayfayla test edildi; video sayfası XVideos ile aynı altyapı (ayrıca denenmedi) |
| Eporner | Resmi JSON API | Gömülü oynatıcı | Gerçek yanıtla doğrulandı |
| Pornhub | Webmaster JSON API | Gömülü oynatıcı | Gerçek yanıtla test edildi |
| RedTube | Webmaster JSON API | Gömülü oynatıcı | Gerçek yanıtla test edildi |
| hanime.tv | Resmi olmayan JSON uç noktaları | Yerel oynatıcı (kalite menüsü) | **Canlı denenmedi** |
| Doeda (doeda.com) | WordPress JSON API | Akış çıkarılırsa yerel oynatıcı, yoksa kilitli oynatıcı çerçevesi | Arama ve oynatıcı bulma gerçek yanıtlarla test edildi; akış adresi adımı **canlı denenmedi** |
| Doeda One (doeda.one) | WordPress JSON API | Aynı | Arama gerçek yanıtla test edildi |

"Test edildi" = sitenin gerçek yanıtı kaydedilip ayrıştırıcıdan geçirildi. Uygulamanın kendisi henüz bir iPhone'da
çalıştırılmadı; ilk çalıştırmada küçük düzeltmeler gerekebilir.

Tube8 ve YouPorn'un herkese açık API'leri kapatılmış; hentaihaven / hentai.tv / hentaiturk standart bir API sunmuyor,
bu yüzden eklenmedi. Hentai aramaları hanime'ye ek olarak karma sitelerde de ("hentai …" olarak) yapılır.

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

### Mac yoksa
Bu klasörü bir GitHub deposuna it. `.github/workflows/build-ipa.yml` macOS'ta testleri çalıştırıp
**imzasız IPA** üretir (Actions → son çalışma → Artifacts). Bunu **SideStore**, **AltStore** veya
**Sideloadly** ile kendi Apple ID'nle imzalayıp yükle.

## Geliştirme

```
Vitrin/Core/   Arayüzden bağımsız mantık: kaynaklar, filtreler, yapay zekâ, arama planı
Vitrin/App/    SwiftUI arayüzü, oynatıcılar
Tests/         Çekirdek testleri
```
`swift test` çekirdeği macOS ya da Linux'ta test eder (47 test). Sitelerden kaydettiğin gerçek yanıtlarla denemek için:
`VITRIN_SAMPLES=/klasör swift test` (dosya adları `Tests/VitrinCoreTests/RealSampleTests.swift` içinde).

## Bilinen sınırlamalar

- XVideos/XNXX ve Türk siteleri sayfa yapısına bağlıdır; site tasarımını değiştirirse ilgili dosya güncellenmelidir.
  Bir kaynak bozulursa yalnızca o hata verir, diğerleri çalışmaya devam eder.
- Türk sitelerinin API'si video süresi vermez: bu kaynaklarda "en uzun/en kısa" sıralaması ve süreye dayalı
  yinelenen tespiti çalışmaz.
- Türk siteleri başlıkları Türkçe yeniden yazdığı için, aynı videonun yabancı sitedeki kopyasıyla eşleştirilemez.
- doeda.com yalnızca şifresiz `http` sunuyor; bu siteyle trafiğin VPN yoksa ağ sağlayıcına açık olur.
- Bazı siteler belirli ülkeleri kendileri engelliyor; bu durumda VPN konumunu değiştirmek gerekir.
- İndirme özelliği yoktur; yalnızca izleme.
