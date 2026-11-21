"""Uygulama başına öğrenilen dersler (kalıcı hafıza).

Her uygulama için hafiza/<uygulama>.md dosyasında madde madde dersler tutulur.
Ajan her görevde bunları okur, yeni öğrendiklerini ekler. Dosya büyüyünce
Claude ile özetlenip sadeleştirilir.
"""
from __future__ import annotations

import datetime as dt
import re
from pathlib import Path

KLASOR = Path(__file__).resolve().parent / "hafiza"
MAKS_KARAKTER = 12000  # bunu aşınca sadeleştir


def _dosya(uygulama: str) -> Path:
    ad = re.sub(r"[^a-z0-9ğüşıöç_-]+", "_", uygulama.strip().lower()) or "genel"
    return KLASOR / f"{ad}.md"


def oku(uygulama: str) -> str:
    d = _dosya(uygulama)
    return d.read_text(encoding="utf-8") if d.exists() else ""


def tumunu_oku() -> dict[str, str]:
    if not KLASOR.exists():
        return {}
    return {d.stem: d.read_text(encoding="utf-8") for d in sorted(KLASOR.glob("*.md")) if not d.stem.endswith(".yedek")}


def ekle(uygulama: str, ders: str) -> str:
    KLASOR.mkdir(exist_ok=True)
    d = _dosya(uygulama)
    tarih = dt.date.today().isoformat()
    with d.open("a", encoding="utf-8") as f:
        if d.stat().st_size == 0:
            f.write(f"# {uygulama} – öğrenilenler\n\n")
        f.write(f"- ({tarih}) {ders.strip()}\n")
    return str(d)


def yaz(uygulama: str, icerik: str):
    KLASOR.mkdir(exist_ok=True)
    _dosya(uygulama).write_text(icerik, encoding="utf-8")


def sadelestirilmesi_gerekenler() -> list[str]:
    return [ad for ad, icerik in tumunu_oku().items() if len(icerik) > MAKS_KARAKTER]
