"""Hassas tıklama: ekranda doğru yere tıklamayı kolaylaştıran araçlar.

Özellikle yerel modeller için çok faydalıdır, çünkü koordinat tahmin etmek yerine:
  1. Izgara: ekran görüntüsü harf-rakam hücrelerine bölünür ("hücre D7'ye tıkla").
     Gerekirse hücre büyütülüp alt ızgarayla daha da inceltilir.
  2. Metin bulma (OCR): ekrandaki yazıyı bulup tam üstüne tıklar ("'File' yazısına tıkla").
  3. Arayüz öğeleri (yalnızca Windows): pencerenin düğme/menü listesini adlarıyla verir.

İsteğe bağlı paketler:  pip install rapidocr_onnxruntime   (OCR, çevrimdışı)
                        pip install uiautomation           (Windows arayüz öğeleri)
"""
from __future__ import annotations

import platform
import string

import pyautogui
from PIL import Image, ImageDraw, ImageFont

AD = "hassas_tiklama"
ACIKLAMA = "Izgara, yazı bulma (OCR) ve arayüz öğeleriyle ekranda doğru yere tıklama"
ISTEM = """Hassas tıklama: Küçük veya emin olmadığın hedeflerde koordinat tahmin etmek yerine şunları kullan:
- Hedefte bir yazı varsa (menü, düğme): önce metne_tikla.
- Yazısız simgeler için: izgarali_ekran → hucreye_tikla (gerekirse önce hucreyi_buyut ile alt hücre seç).
- Windows'ta standart pencerelerde arayuz_ogeleri → ogeye_tikla en güvenilir yoldur."""

SUTUN, SATIR = 16, 9          # ana ızgara (16:9 ekran için kareye yakın hücreler)
ALT = 4                       # alt ızgara (hücre büyütmede 4x4)

ARACLAR = [
    {"name": "izgarali_ekran",
     "description": "Üzerine harf (sütun A-P) ve rakam (satır 1-9) ızgarası çizilmiş ekran görüntüsü döndürür. "
                    "Hedefin hangi hücrede olduğunu söyleyip hucreye_tikla ile tıkla.",
     "input_schema": {"type": "object", "properties": {}, "required": []}},
    {"name": "hucreyi_buyut",
     "description": "Bir hücreyi (ör. 'D7') büyütüp üzerine a1-d4 alt ızgarası çizer. Küçük simgeler için.",
     "input_schema": {"type": "object", "properties": {"hucre": {"type": "string"}}, "required": ["hucre"]}},
    {"name": "hucreye_tikla",
     "description": "Hücrenin (ör. 'D7') veya alt hücresinin (ör. hucre 'D7', alt 'b3') ortasına tıklar.",
     "input_schema": {"type": "object", "properties": {
         "hucre": {"type": "string"}, "alt": {"type": "string", "description": "İsteğe bağlı alt hücre, ör. b3"},
         "tus": {"type": "string", "enum": ["sol", "sag", "cift"]}}, "required": ["hucre"]}},
    {"name": "metni_bul",
     "description": "Ekranda bir yazıyı OCR ile arar; bulduğu yerleri koordinatlarıyla listeler.",
     "input_schema": {"type": "object", "properties": {"metin": {"type": "string"}}, "required": ["metin"]}},
    {"name": "metne_tikla",
     "description": "Ekrandaki bir yazının (ör. 'File', 'Kaydet') tam üstüne tıklar. Birden çok eşleşme varsa 'sira' ile seç (1'den başlar).",
     "input_schema": {"type": "object", "properties": {
         "metin": {"type": "string"}, "sira": {"type": "integer"},
         "tus": {"type": "string", "enum": ["sol", "sag", "cift"]}}, "required": ["metin"]}},
    {"name": "arayuz_ogeleri",
     "description": "(Windows) Öndeki pencerenin tıklanabilir öğelerini (düğme, menü, sekme...) adları ve "
                    "koordinatlarıyla listeler. 'filtre' ile ada göre süz.",
     "input_schema": {"type": "object", "properties": {"filtre": {"type": "string"}}, "required": []}},
    {"name": "ogeye_tikla",
     "description": "(Windows) arayuz_ogeleri listesindeki bir öğeye adıyla tıklar.",
     "input_schema": {"type": "object", "properties": {
         "ad": {"type": "string"}, "tus": {"type": "string", "enum": ["sol", "sag", "cift"]}}, "required": ["ad"]}},
]


# ------------------------------------------------------------------ ızgara
def _hucre_coz(hucre: str) -> tuple[int, int]:
    h = hucre.strip().upper()
    sutun = string.ascii_uppercase.index(h[0])
    satir = int(h[1:]) - 1
    if not (0 <= sutun < SUTUN and 0 <= satir < SATIR):
        raise ValueError(f"Geçersiz hücre: {hucre} (A1–{string.ascii_uppercase[SUTUN - 1]}{SATIR})")
    return sutun, satir


def _hucre_kutusu(pc, hucre: str) -> tuple[float, float, float, float]:
    """Hücrenin ekran görüntüsü koordinatlarındaki kutusu."""
    s, r = _hucre_coz(hucre)
    w, h = pc.ss_boyut
    return s * w / SUTUN, r * h / SATIR, (s + 1) * w / SUTUN, (r + 1) * h / SATIR


def _font(boyut: int):
    for ad in ("arialbd.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(ad, boyut)
        except OSError:
            continue
    return ImageFont.load_default()


def _izgara_ciz(img: Image.Image, sutun: int, satir: int, etiket) -> Image.Image:
    img = img.convert("RGB")
    ust = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ust)
    w, h = img.size
    f = _font(max(11, int(min(w / sutun, h / satir) / 4)))
    for i in range(1, sutun):
        x = i * w / sutun
        d.line([(x, 0), (x, h)], fill=(255, 0, 80, 150), width=1)
    for j in range(1, satir):
        y = j * h / satir
        d.line([(0, y), (w, y)], fill=(255, 0, 80, 150), width=1)
    for i in range(sutun):
        for j in range(satir):
            x, y = i * w / sutun + 2, j * h / satir + 1
            yazi = etiket(i, j)
            kutu = d.textbbox((x, y), yazi, font=f)
            d.rectangle(kutu, fill=(0, 0, 0, 150))
            d.text((x, y), yazi, font=f, fill=(255, 255, 0, 255))
    return Image.alpha_composite(img.convert("RGBA"), ust).convert("RGB")


def _tikla(pc, x: float, y: float, tus: str | None):
    ex, ey = pc._ekrana((x, y))
    pyautogui.moveTo(ex, ey, duration=0.15)
    if tus == "sag":
        pyautogui.click(button="right")
    elif tus == "cift":
        pyautogui.doubleClick()
    else:
        pyautogui.click()
    return f"Tıklandı: ({int(x)}, {int(y)})"


# --------------------------------------------------------------------- OCR
_ocr = None


def _ocr_motoru():
    global _ocr
    if _ocr is None:
        try:
            from rapidocr_onnxruntime import RapidOCR
        except ImportError:
            try:
                from rapidocr import RapidOCR
            except ImportError:
                raise RuntimeError("OCR kurulu değil. Kurmak için: pip install rapidocr_onnxruntime  "
                                   "(şimdilik izgarali_ekran / hucreye_tikla kullan)")
        _ocr = RapidOCR()
    return _ocr


def _ocr_calistir(img: Image.Image) -> list[tuple[str, float, float, float]]:
    """[(metin, merkez_x, merkez_y, güven, genişlik)] – ekran görüntüsü koordinatlarında."""
    import numpy as np

    sonuc = _ocr_motoru()(np.array(img.convert("RGB")))
    satirlar = sonuc[0] if isinstance(sonuc, tuple) else getattr(sonuc, "boxes", None)
    if satirlar is None:  # rapidocr 2.x nesnesi
        satirlar = list(zip(sonuc.boxes, sonuc.txts, sonuc.scores)) if sonuc.boxes is not None else []
    cikti = []
    for kutu, metin, guven in satirlar or []:
        xs = [p[0] for p in kutu]
        ys = [p[1] for p in kutu]
        cikti.append((metin, sum(xs) / 4, sum(ys) / 4, float(guven), max(xs) - min(xs)))
    return cikti


def _eslesenler(pc, aranan: str):
    import difflib

    img = pc.ekran_goruntusu_pil()
    a = aranan.strip().lower()
    sonuc = []
    for metin, x, y, guven, genislik in _ocr_calistir(img):
        m = metin.strip().lower()
        if a == m or a in m or difflib.SequenceMatcher(None, a, m).ratio() > 0.8:
            puan = 2 if a == m else (1.5 if m.startswith(a) else 1)
            # Uzun satırın içinde geçiyorsa kelimenin yaklaşık konumuna kaydır
            if a in m and len(m) > len(a) + 2:
                kayma = (m.index(a) + len(a) / 2) / len(m) - 0.5
                x += kayma * genislik
            sonuc.append((puan, metin, x, y))
    sonuc.sort(key=lambda t: (-t[0], t[3], t[2]))
    return sonuc


# --------------------------------------------------- Windows arayüz öğeleri
def _ogeler(pc, filtre: str = ""):
    if platform.system() != "Windows":
        raise RuntimeError("Arayüz öğeleri yalnızca Windows'ta çalışır. Izgara veya metne_tikla kullan.")
    try:
        import uiautomation as auto
    except ImportError:
        raise RuntimeError("uiautomation kurulu değil (pip install uiautomation). Izgara veya metne_tikla kullan.")
    pencere = auto.GetForegroundControl().GetTopLevelControl()
    sonuc = []

    def gez(k, derinlik):
        if derinlik > 25 or len(sonuc) >= 300:
            return
        for c in k.GetChildren():
            r = c.BoundingRectangle
            if c.Name and r.width() > 2 and r.height() > 2 and (not filtre or filtre.lower() in c.Name.lower()):
                x = ((r.left + r.right) / 2 - pc.mon["left"]) * pc.olcek
                y = ((r.top + r.bottom) / 2 - pc.mon["top"]) * pc.olcek
                sonuc.append((c.Name.strip(), c.ControlTypeName.replace("Control", ""), x, y))
            gez(c, derinlik + 1)

    gez(pencere, 0)
    return pencere.Name, sonuc


# ----------------------------------------------------------------- giriş
def calistir(ad: str, g: dict, ajan):
    pc = ajan.pc
    if ad == "izgarali_ekran":
        img = _izgara_ciz(pc.ekran_goruntusu_pil(), SUTUN, SATIR,
                          lambda i, j: f"{string.ascii_uppercase[i]}{j + 1}")
        return pc._gorsel_blok(img)
    if ad == "hucreyi_buyut":
        x0, y0, x1, y1 = _hucre_kutusu(pc, g["hucre"])
        k = 1 / pc.olcek
        ex0, ey0 = pc._ekrana((x0, y0))
        parca = pc._yakala({"left": ex0, "top": ey0, "width": max(1, int((x1 - x0) * k)),
                            "height": max(1, int((y1 - y0) * k))})
        olcek = min(800 / parca.width, 800 / parca.height)
        parca = parca.resize((int(parca.width * olcek), int(parca.height * olcek)), Image.LANCZOS)
        img = _izgara_ciz(parca, ALT, ALT, lambda i, j: f"{'abcd'[i]}{j + 1}")
        return pc._gorsel_blok(img)
    if ad == "hucreye_tikla":
        x0, y0, x1, y1 = _hucre_kutusu(pc, g["hucre"])
        if g.get("alt"):
            a = g["alt"].strip().lower()
            i, j = "abcd".index(a[0]), int(a[1:]) - 1
            if not (0 <= j < ALT):
                raise ValueError("Alt hücre a1–d4 arasında olmalı")
            gw, gh = (x1 - x0) / ALT, (y1 - y0) / ALT
            x0, y0, x1, y1 = x0 + i * gw, y0 + j * gh, x0 + (i + 1) * gw, y0 + (j + 1) * gh
        return _tikla(pc, (x0 + x1) / 2, (y0 + y1) / 2, g.get("tus"))
    if ad == "metni_bul":
        bulunan = _eslesenler(pc, g["metin"])
        if not bulunan:
            return f"'{g['metin']}' ekranda bulunamadı."
        return "\n".join(f"{i + 1}. '{m}' → ({int(x)}, {int(y)})" for i, (_, m, x, y) in enumerate(bulunan[:10]))
    if ad == "metne_tikla":
        bulunan = _eslesenler(pc, g["metin"])
        if not bulunan:
            raise RuntimeError(f"'{g['metin']}' ekranda bulunamadı (yazım farklı olabilir; metni_bul veya ızgara dene).")
        sira = max(1, int(g.get("sira") or 1))
        if sira > len(bulunan):
            raise RuntimeError(f"Yalnızca {len(bulunan)} eşleşme var.")
        _, m, x, y = bulunan[sira - 1]
        return _tikla(pc, x, y, g.get("tus")) + f" ('{m}')"
    if ad == "arayuz_ogeleri":
        pencere, ogeler = _ogeler(pc, g.get("filtre", ""))
        if not ogeler:
            return f"'{pencere}' penceresinde adlı öğe bulunamadı (bu uygulama standart arayüz kullanmıyor olabilir)."
        return f"Pencere: {pencere}\n" + "\n".join(f"- {ad_} [{tur}] → ({int(x)}, {int(y)})"
                                                   for ad_, tur, x, y in ogeler[:150])
    if ad == "ogeye_tikla":
        _, ogeler = _ogeler(pc, g["ad"])
        if not ogeler:
            raise RuntimeError(f"'{g['ad']}' adlı öğe bulunamadı.")
        tam = [o for o in ogeler if o[0].lower() == g["ad"].lower()] or ogeler
        ad_, tur, x, y = tam[0]
        return _tikla(pc, x, y, g.get("tus")) + f" ({ad_} [{tur}])"
    raise ValueError(f"Bilinmeyen araç: {ad}")
