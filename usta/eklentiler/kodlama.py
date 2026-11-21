"""Kodlama: Python kodu yazıp çalıştırma ve dosya işlemleri.

Usta küçük yardımcı programlar yazabilir: toplu dosya adlandırma, görsel işleme, Blender
için betik hazırlama, hesaplama... Her şey `usta_calisma/` klasöründe olur; bu klasörün
dışına dosya yazamaz. Varsayılan olarak her kod çalıştırmadan önce sana sorar.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

AD = "kodlama"
ACIKLAMA = "Python kodu yazma/çalıştırma ve çalışma klasöründe dosya işlemleri (çalıştırmadan önce sorar)"
ISTEM = """Kodlama: Tekrarlayan veya hesap gerektiren işler için (toplu dosya işlemi, görsel düzenleme,
Blender/Photoshop betiği hazırlama) python_calistir ile kısa Python programları yazabilirsin.
Dosyalar yalnızca çalışma klasöründe oluşturulur. Hata alırsan hatayı okuyup kodu düzelt."""

KLASOR = Path(__file__).resolve().parent.parent / "usta_calisma"
ONAY_ISTE = True   # False yaparsan kod sormadan çalışır (önerilmez)

ARACLAR = [
    {"name": "python_calistir",
     "description": "Python kodunu çalışma klasöründe çalıştırır (en fazla 120 sn); çıktıyı ve hataları döndürür.",
     "input_schema": {"type": "object", "properties": {
         "kod": {"type": "string"}, "aciklama": {"type": "string", "description": "Kod ne yapacak (kullanıcıya gösterilir)"}},
         "required": ["kod", "aciklama"]}},
    {"name": "dosya_yaz",
     "description": "Çalışma klasörüne metin dosyası yazar (ör. betik, not, ayar dosyası).",
     "input_schema": {"type": "object", "properties": {"yol": {"type": "string"}, "icerik": {"type": "string"}},
                      "required": ["yol", "icerik"]}},
    {"name": "dosya_oku",
     "description": "Çalışma klasöründeki bir metin dosyasını okur.",
     "input_schema": {"type": "object", "properties": {"yol": {"type": "string"}}, "required": ["yol"]}},
    {"name": "dosyalari_listele",
     "description": "Çalışma klasöründeki dosyaları listeler.",
     "input_schema": {"type": "object", "properties": {}, "required": []}},
]


def _guvenli_yol(yol: str) -> Path:
    KLASOR.mkdir(exist_ok=True)
    p = (KLASOR / yol).resolve()
    if KLASOR.resolve() not in p.parents and p != KLASOR.resolve():
        raise PermissionError(f"Yalnızca çalışma klasörüne ({KLASOR}) erişebilirsin.")
    return p


def calistir(ad: str, g: dict, ajan):
    if ad == "python_calistir":
        if ONAY_ISTE:
            onizleme = g["kod"] if len(g["kod"]) < 1500 else g["kod"][:1500] + "\n…"
            cevap = ajan.sor(f"Usta şu kodu çalıştırmak istiyor:\n{g.get('aciklama', '')}\n\n{onizleme}\n\n"
                             "Çalıştırılsın mı? (evet / hayır)")
            if not cevap.strip().lower().startswith(("e", "y")):
                return "Kullanıcı bu kodun çalıştırılmasına izin vermedi."
        KLASOR.mkdir(exist_ok=True)
        dosya = KLASOR / "_son_kod.py"
        dosya.write_text(g["kod"], encoding="utf-8")
        try:
            s = subprocess.run([sys.executable, "-I", str(dosya)], cwd=KLASOR, capture_output=True,
                               text=True, timeout=120, encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            return "Zaman aşımı: kod 120 saniyede bitmedi."
        cikti = (s.stdout or "")[-6000:]
        hata = (s.stderr or "")[-4000:]
        return f"Çıkış kodu: {s.returncode}\n--- çıktı ---\n{cikti or '(yok)'}" + (f"\n--- hata ---\n{hata}" if hata else "")
    if ad == "dosya_yaz":
        p = _guvenli_yol(g["yol"])
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(g["icerik"], encoding="utf-8")
        return f"Yazıldı: {p}"
    if ad == "dosya_oku":
        p = _guvenli_yol(g["yol"])
        return p.read_text(encoding="utf-8", errors="replace")[:20000]
    if ad == "dosyalari_listele":
        KLASOR.mkdir(exist_ok=True)
        dosyalar = [str(p.relative_to(KLASOR)) for p in sorted(KLASOR.rglob("*")) if p.is_file()]
        return f"{KLASOR}\n" + ("\n".join(dosyalar) or "(boş)")
    raise ValueError(f"Bilinmeyen araç: {ad}")
