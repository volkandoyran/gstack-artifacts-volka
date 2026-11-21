"""Uygulamaların kendi betik arayüzleri: tıklamaktan çok daha güvenilir.

- Blender: blender_eklentisi/usta_koprusu.py eklentisi açıkken, çalışan Blender'a
  yerel soket (127.0.0.1:8765) üzerinden bpy Python kodu gönderilir.
- Photoshop (Windows): COM üzerinden ExtendScript (JavaScript) çalıştırılır.
"""
from __future__ import annotations

import json
import platform
import socket

BLENDER_ADRES = ("127.0.0.1", 8765)


def blender_python(kod: str, zaman_asimi: float = 60) -> str:
    try:
        with socket.create_connection(BLENDER_ADRES, timeout=zaman_asimi) as s:
            s.sendall((json.dumps({"kod": kod}) + "\n").encode("utf-8"))
            tampon = b""
            while not tampon.endswith(b"\n"):
                parca = s.recv(65536)
                if not parca:
                    break
                tampon += parca
    except OSError as e:
        raise RuntimeError(
            "Blender'a bağlanılamadı. Blender açık mı ve 'Usta Köprüsü' eklentisi etkin mi? "
            f"(Ayrıntı: {e}). Bunun yerine arayüzü fare/klavye ile kullanabilirsin."
        )
    yanit = json.loads(tampon.decode("utf-8"))
    if not yanit.get("ok"):
        raise RuntimeError(f"Blender hatası:\n{yanit.get('hata')}\nÇıktı:\n{yanit.get('cikti', '')}")
    return yanit.get("cikti") or "OK (çıktı yok)"


def photoshop_js(kod: str) -> str:
    if platform.system() != "Windows":
        raise RuntimeError("Photoshop betik köprüsü yalnızca Windows'ta çalışır. Arayüzü fare/klavye ile kullan.")
    try:
        import win32com.client  # pywin32
    except ImportError:
        raise RuntimeError("pywin32 kurulu değil (pip install pywin32). Arayüzü fare/klavye ile kullan.")
    try:
        ps = win32com.client.Dispatch("Photoshop.Application")
        sonuc = ps.DoJavaScript(kod)
    except Exception as e:
        raise RuntimeError(f"Photoshop betik hatası: {e}")
    return str(sonuc) if sonuc not in (None, "") else "OK (çıktı yok)"
