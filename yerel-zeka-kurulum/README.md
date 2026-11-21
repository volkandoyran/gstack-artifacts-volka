# Yerel Zeka Kurulumu

İnternetsiz çalışan bir yapay zekayı (Ollama + Qwen3-VL gibi görsel modeller) kendi bilgisayarına
adım adım kuran ve **Usta**'ya bağlayan kurulum asistanı.

## Başlarken

- **Windows:** `BASLAT.bat`'a çift tıkla → **9 – Hepsini sırayla yap**.
- **macOS / Linux:** `bash kurulum.sh`
- **Rehber** (internetsiz açılır): `rehber.html`. Bilgisayar alma önerileri, araç karşılaştırması,
  model seçimi ve sorun giderme burada.

## Dosyalar

| Dosya | Ne işe yarar |
|---|---|
| `BASLAT.bat` | Sihirbazı açar (PowerShell izin ayarı gerektirmeden) |
| `kurulum_sihirbazi.ps1` | Menülü Windows sihirbazı: donanım analizi → öneri → kurulum → model → test → Usta bağlantısı |
| `kurulum.sh` | macOS / Linux için aynı adımlar |
| `modeller.json` | Araç ve model kataloğu (neden / artılar / eksiler). Yeni model çıkınca buraya ekle |
| `rehber.html` | Ayrıntılı, çevrimdışı rehber |

## Sihirbaz menüsü

1. Bilgisayarımı incele ve öneri al
2. Araçları karşılaştır (Ollama, LM Studio, llama.cpp, Jan, GPT4All, Open WebUI)
3. Ollama'yı kur (+ bağlam penceresini büyütür)
4. Model indir
5. Kurulumu test et
6. Diğer araçları kur
7. Usta'yı kur ve yerel zekaya bağla (hibrit veya tamamen çevrimdışı)
8. Gelişmiş: modelleri başka diske taşı, bağlam, ağ erişimi, güncelleme
9. Hepsini sırayla yap

Kurulum dosyaları (.exe) bilerek eklenmedi: hem çok büyükler hem de çabuk eskiyorlar. Sihirbaz
her seferinde en güncel sürümü resmi kaynaktan indirir. Kurulumdan sonra internet gerekmez.
