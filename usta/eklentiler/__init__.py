"""Usta eklenti sistemi.

Bu klasöre bırakılan her .py dosyası bir eklentidir (adı _ ile başlayanlar hariç).
Bir eklenti şunları tanımlar:

    AD = "internet"                      # dosya adıyla aynı olması önerilir
    ACIKLAMA = "Kısa açıklama (ayarlarda görünür)"
    ISTEM = "Yapay zekaya bu eklentiyi ne zaman kullanacağını anlatan metin"   # isteğe bağlı
    ARACLAR = [                          # yapay zekanın çağırabileceği araçlar
        {"name": "web_ara", "description": "...",
         "input_schema": {"type": "object", "properties": {...}, "required": [...]}},
    ]
    def calistir(ad: str, girdi: dict, ajan) -> str | list:   # araç çağrıldığında
        ...                                                    # metin veya görsel blokları döndür
    def olay(ad: str, ajan, **veri):                           # isteğe bağlı: olayları dinle
        ...   # olaylar: "deneme_basladi"(gorev, uygulama), "eylem"(arac, girdi, hata), "gorev_bitti"(gorev, uygulama, basarili)

Araçlar hem Claude'a hem yerel modele otomatik olarak tanıtılır.
"""
from __future__ import annotations

import importlib
import pkgutil
import traceback
from pathlib import Path
from types import ModuleType

KLASOR = Path(__file__).resolve().parent


def mevcut() -> list[tuple[str, str]]:
    """(ad, açıklama) listesi – ayarlar penceresi için."""
    sonuc = []
    for m in pkgutil.iter_modules([str(KLASOR)]):
        if m.name.startswith("_"):
            continue
        try:
            mod = importlib.import_module(f"eklentiler.{m.name}")
            sonuc.append((m.name, getattr(mod, "ACIKLAMA", "")))
        except Exception as e:
            sonuc.append((m.name, f"(yüklenemedi: {e})"))
    return sonuc


def yukle(adlar: list[str], log=None) -> list[ModuleType]:
    moduller = []
    for ad in adlar:
        ad = ad.strip()
        if not ad:
            continue
        try:
            moduller.append(importlib.import_module(f"eklentiler.{ad}"))
        except Exception:
            if log:
                log("hata", f"Eklenti yüklenemedi: {ad}\n{traceback.format_exc(limit=2)}")
    return moduller
