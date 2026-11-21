bl_info = {
    "name": "Usta Köprüsü",
    "author": "Usta",
    "version": (1, 0, 0),
    "blender": (3, 0, 0),
    "location": "Arka planda çalışır (127.0.0.1:8765)",
    "description": "Usta uygulamasının çalışan Blender'a Python (bpy) kodu göndermesini sağlar",
    "category": "Development",
}

# Güvenlik: sunucu yalnızca 127.0.0.1 (bu bilgisayar) üzerinden bağlantı kabul eder.

import contextlib
import io
import json
import queue
import socket
import threading
import traceback

import bpy

ADRES = ("127.0.0.1", 8765)
_istekler: "queue.Queue" = queue.Queue()
_sunucu = None
_calisiyor = False


def _istemci(baglanti):
    with baglanti:
        tampon = b""
        while not tampon.endswith(b"\n"):
            parca = baglanti.recv(65536)
            if not parca:
                return
            tampon += parca
        istek = json.loads(tampon.decode("utf-8"))
        yanit_kuyrugu: "queue.Queue" = queue.Queue()
        _istekler.put((istek.get("kod", ""), yanit_kuyrugu))
        yanit = yanit_kuyrugu.get()
        baglanti.sendall((json.dumps(yanit) + "\n").encode("utf-8"))


def _dinle():
    global _sunucu
    _sunucu = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    _sunucu.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    _sunucu.bind(ADRES)
    _sunucu.listen(4)
    while _calisiyor:
        try:
            baglanti, _ = _sunucu.accept()
        except OSError:
            break
        threading.Thread(target=_istemci, args=(baglanti,), daemon=True).start()


def _isle():
    """Blender ana iş parçacığında kuyruktaki kodları çalıştırır (bpy güvenli)."""
    while not _istekler.empty():
        kod, yanit_kuyrugu = _istekler.get()
        cikti = io.StringIO()
        try:
            with contextlib.redirect_stdout(cikti):
                exec(kod, {"bpy": bpy, "__name__": "__usta__"})
            yanit = {"ok": True, "cikti": cikti.getvalue()}
        except Exception:
            yanit = {"ok": False, "hata": traceback.format_exc(), "cikti": cikti.getvalue()}
        yanit_kuyrugu.put(yanit)
    return 0.1 if _calisiyor else None


def register():
    global _calisiyor
    _calisiyor = True
    threading.Thread(target=_dinle, daemon=True).start()
    bpy.app.timers.register(_isle, persistent=True)
    print("Usta Köprüsü dinliyor:", ADRES)


def unregister():
    global _calisiyor
    _calisiyor = False
    if _sunucu:
        _sunucu.close()
