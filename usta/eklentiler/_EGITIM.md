# Yerel modeli kendi verinle eğitmek (ince ayar)

`deneyim_kaydi` eklentisi açıkken Usta, başarıyla doğrulanan her görevin adımlarını buraya kaydeder.
Bu veriyle yerel görsel modele **LoRA ince ayarı** yapabilirsin. Böylece model senin ekranında ve senin
uygulamalarında (Blender, Photoshop…) doğru yere tıklamayı öğrenir.

> Bu ileri düzey bir adımdır. Üç şart var:
> - **Ekran kartı:** En az 16 GB, tercihen 24 GB belleği olan bir NVIDIA kart gerekir.
> - **Veri:** Birkaç yüz adımlık veri biriktirmen gerekir. Bunun en kolay yolu Claude ile çalışırken kaydı açık tutmaktır, çünkü Claude'un doğru eylemlerinden öğrenmek en verimli yoldur.
> - **Süre:** Eğitim birkaç saat sürebilir.

## Klasör yapısı

```
egitim_verisi/
  veri.jsonl            ← eğitim dosyası (her satır: bir ekran görüntüsü + doğru eylem)
  bolumler/<tarih>_<uygulama>/
      adim_001.png …    ← o adımdaki ekran
      adimlar.jsonl     ← görevin tüm adımları
```

## Önerilen araç: LLaMA-Factory (ücretsiz, açık kaynak)

1. Kurulum (WSL2 veya Linux önerilir; Windows'ta da çalışır):
   ```
   git clone https://github.com/hiyouga/LLaMA-Factory.git
   cd LLaMA-Factory
   pip install -e ".[torch,metrics]"
   ```
2. `data/dataset_info.json` dosyasına veri kümeni ekle:
   ```json
   "usta": {
     "file_name": "C:/…/usta/egitim_verisi/veri.jsonl",
     "formatting": "sharegpt",
     "columns": {"messages": "messages", "images": "images"},
     "tags": {"role_tag": "role", "content_tag": "content", "user_tag": "user", "assistant_tag": "assistant"}
   }
   ```
   Görüntü yolları `egitim_verisi` klasörüne göredir. Hata alırsan LLaMA-Factory ayarlarında `media_dir` değerini bu klasöre ayarla.
3. Arayüzü aç: `llamafactory-cli webui`. Şu seçimleri yap:
   - Model: `Qwen2.5-VL-7B-Instruct` veya `Qwen3-VL-8B-Instruct`
   - Yöntem: **LoRA**
   - Veri kümesi: **usta**
   - Ardından **Start**'a bas.
4. Eğitim bitince **Export** sekmesinden modeli dışa aktar. Ardından llama.cpp'nin `convert_hf_to_gguf.py` betiğiyle GGUF biçimine çevir.
5. Ollama'ya tanıt. `Modelfile` adında bir dosya oluştur ve içine `FROM ./usta-model.gguf` yaz. Sonra şu komutu çalıştır:
   ```
   ollama create usta-model -f Modelfile
   ```
6. Usta → ⚙ Ayarlar → Yerel model: `usta-model`.

Alternatif: **Unsloth** daha az bellekle ve daha hızlı eğitir. Hazır not defterleri: https://docs.unsloth.ai

## İpuçları

- **Koordinat biçimi:** Verideki koordinatlar, kayıt sırasındaki ekran görüntüsü boyutuna göre pikseldir (boyut `adimlar.jsonl`'nin ilk satırında yazar). Eğitilmiş modeli Usta'da kullanırken koordinat ayarını **piksel** yap. Yerel ekran görüntüsü boyutunu da kayıttaki boyutla aynı tut.
- **Kalite:** Az ama doğru veri, çok ama hatalı veriden iyidir. Yalnızca doğrulanmış başarılı görevler kaydedilir.
- **Gizlilik:** Ekran görüntüleri ekranda görünen her şeyi içerir. Klasörü paylaşmadan önce gözden geçir.
