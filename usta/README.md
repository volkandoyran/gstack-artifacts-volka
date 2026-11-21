# Usta 🛠️

Blender, Photoshop, GIMP gibi karmaşık uygulamaları **kullanmayı öğrenen** ve sen ne istersen
onu bu uygulamalarda **yapmaya çalışan** bir masaüstü asistanı. Claude'un bilgisayar kullanma
(computer use) yeteneğiyle ekranı görür, fareyi ve klavyeyi kullanır.

## Ne yapar?

| Özellik | Açıklama |
|---|---|
| **▶ Yap** | Yazdığın veya söylediğin görevi seçili uygulamada yapar. |
| **Başarana kadar dene** | Her denemeden sonra ayrı bir "kontrolcü" son ekranı inceler. Olmadıysa nedenini ve ipucunu bir sonraki denemeye aktarır; başarana kadar (veya deneme sınırına kadar) tekrar dener. `0` = sınırsız. |
| **🧭 Keşfet ve öğren** | Uygulamanın menülerini, panellerini ve kısayollarını kendi kendine keşfedip öğrendiklerini kaydeder. |
| **📘 Hafıza** | Öğrenilen dersler `hafiza/<uygulama>.md` dosyalarında birikir ve sonraki her görevde kullanılır; Usta zamanla daha iyi olur. Dosya büyüyünce otomatik olarak sadeleştirilir (eskisi `.yedek.md` olarak kalır). Bu dosyaları elle de düzenleyebilirsin. |
| **🎤 Söyle** | Türkçe sesli komut (isteğe bağlı). |
| **Betik köprüleri** | Blender'da `bpy` Python, Photoshop'ta (Windows) ExtendScript çalıştırabilir; karmaşık işlerde tıklamaktan çok daha güvenilirdir. |

## Kurulum (Windows)

1. [Python 3.10+](https://www.python.org/downloads/) kur ("Add to PATH" işaretli olsun).
2. Bu klasörde **`baslat.bat`**'a çift tıkla. İlk seferde gerekli paketleri kurar.
3. İlk çalıştırmada Anthropic API anahtarını sorar (console.anthropic.com → API Keys).
   Anahtar `ayarlar.json`'a kaydedilir; bu dosyayı kimseyle paylaşma.

macOS/Linux: `pip install -r requirements.txt && python usta.py`
(macOS'ta Terminal'e Ekran Kaydı ve Erişilebilirlik izni vermen gerekir.)

### Blender köprüsü (önerilir)

Blender → Edit → Preferences → Add-ons → **Install…** → `blender_eklentisi/usta_koprusu.py`
dosyasını seç ve etkinleştir. Eklenti yalnızca bu bilgisayardan (127.0.0.1:8765) bağlantı kabul eder.
Usta artık sahneyi doğrudan Python ile düzenleyebilir, sonucu yine ekranda kontrol eder.

### Photoshop köprüsü

Windows'ta `pywin32` kuruluysa (requirements ile gelir) ve Photoshop açıksa otomatik çalışır.

### Sesli komut (isteğe bağlı)

`pip install SpeechRecognition pyaudio` — ses tanıma için ses kaydın Google'a gönderilir.

## Güvenlik

- Usta **gerçek fare ve klavyeni** kullanır. Çalışırken bilgisayarı kullanma.
- **Acil durdurma:** fareyi ekranın **sol üst köşesine** götür veya **■ Durdur**'a bas.
- Dosya silme/üzerine yazma gibi riskli adımlardan önce sana sorması söylenmiştir, ama yine de
  önemli dosyalarının yedeğini al; mümkünse ayrı bir kullanıcı hesabında veya sanal makinede çalıştır.
- Çalışırken Usta penceresi sağ alta küçülür. Windows 10/11'de bu pencere ekran görüntülerine
  girmez, böylece Claude onu görmez.

## Ayarlar (⚙)

| Ayar | Varsayılan | Not |
|---|---|---|
| Model | `claude-opus-5-5` | |
| Efor | `medium` | Zor işlerde `high`; daha hızlı/ucuz için `low`. |
| Deneme başına en fazla adım | 80 | |
| Ekran görüntüsü uzun kenarı | 1568 px | Büyütmek küçük simgeleri görmeyi kolaylaştırır ama maliyeti artırır. |

## Maliyet

Her adımda bir ekran görüntüsü gönderilir (~1.800 görsel jeton). Uzun görevler ve "başarana kadar
dene" modu çok sayıda istek yapabilir; Anthropic konsolundan harcama limiti koymanı öneririm.

## Dosyalar

- `usta.py` – arayüz
- `ajan.py` – Claude ajan döngüsü, doğrulama, yeniden deneme
- `bilgisayar.py` – ekran görüntüsü, fare/klavye
- `hafiza.py` – öğrenilen dersler
- `entegrasyonlar.py` – Blender/Photoshop betik köprüleri
- `blender_eklentisi/usta_koprusu.py` – Blender eklentisi
