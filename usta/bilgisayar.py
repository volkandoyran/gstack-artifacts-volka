"""Ekranı görme ve fare/klavye kontrolü.

Claude'un computer_toolset_20260801 üye araçlarını (screenshot, left_click, type, ...)
gerçek fare ve klavye hareketlerine çevirir.
"""
from __future__ import annotations

import base64
import io
import math
import platform
import threading
import time

import mss
import pyautogui
from PIL import Image

# Windows'ta yüksek DPI ekranlarda koordinatların kaymaması için
if platform.system() == "Windows":
    try:
        import ctypes

        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        pass

pyautogui.FAILSAFE = True  # fareyi sol üst köşeye çekmek her şeyi durdurur
pyautogui.PAUSE = 0.05

# Claude'un kullandığı tuş adlarını pyautogui adlarına çevir
TUS_ESLEME = {
    "return": "enter", "enter": "enter", "escape": "esc", "esc": "esc",
    "ctrl": "ctrl", "control": "ctrl", "control_l": "ctrl", "control_r": "ctrl",
    "alt": "alt", "alt_l": "alt", "alt_r": "alt", "shift": "shift",
    "shift_l": "shift", "shift_r": "shift", "super": "win", "super_l": "win",
    "win": "win", "cmd": "command", "meta": "win", "backspace": "backspace",
    "delete": "delete", "del": "delete", "tab": "tab", "space": "space",
    "page_up": "pageup", "prior": "pageup", "page_down": "pagedown",
    "next": "pagedown", "home": "home", "end": "end", "insert": "insert",
    "up": "up", "down": "down", "left": "left", "right": "right",
    "kp_add": "add", "kp_subtract": "subtract", "kp_multiply": "multiply",
    "kp_divide": "divide", "kp_enter": "enter", "kp_decimal": "decimal",
    "caps_lock": "capslock", "print": "printscreen", "minus": "-", "plus": "+",
    "equal": "=", "comma": ",", "period": ".", "slash": "/", "grave": "`",
}
for i in range(10):
    TUS_ESLEME[f"kp_{i}"] = f"num{i}"
for i in range(1, 25):
    TUS_ESLEME[f"f{i}"] = f"f{i}"

# Opus 5.5 görüntü sınırları: uzun kenar <= 2576 px ve ~4784 görsel jeton.
# Maliyeti düşük tutmak için varsayılan olarak daha küçük bir uzun kenar kullanıyoruz.
GORSEL_JETON_SINIRI = 4784


class Durduruldu(Exception):
    """Kullanıcı durdur'a bastığında fırlatılır."""


def _tus_cevir(ad: str) -> str:
    ad = ad.strip()
    return TUS_ESLEME.get(ad.lower(), ad.lower() if len(ad) > 1 else ad)


def _kombinasyon(metin: str | None) -> list[str]:
    if not metin:
        return []
    return [_tus_cevir(p) for p in metin.split("+") if p.strip()]


class Bilgisayar:
    def __init__(self, maks_uzun_kenar: int = 1568, durdur: threading.Event | None = None,
                 eylem_gecikmesi: float = 0.4):
        self.durdur = durdur or threading.Event()
        self.eylem_gecikmesi = eylem_gecikmesi
        with mss.mss() as sct:
            mon = sct.monitors[1]  # birincil ekran
        self.mon = {k: mon[k] for k in ("left", "top", "width", "height")}
        w, h = self.mon["width"], self.mon["height"]
        olcek_kenar = min(maks_uzun_kenar, 2576) / max(w, h)
        olcek_jeton = math.sqrt(GORSEL_JETON_SINIRI * 28 * 28 / (w * h)) * 0.97
        self.olcek = min(1.0, olcek_kenar, olcek_jeton)
        self.ss_boyut = (int(w * self.olcek), int(h * self.olcek))
        self.son_goruntu: Image.Image | None = None   # yapay zekanın gördüğü son ekran (eğitim kaydı için)
        self.goruntu_no = 0

    # ---------- yardımcılar ----------
    def _kontrol(self):
        if self.durdur.is_set():
            raise Durduruldu()

    def _ekrana(self, koord) -> tuple[int, int]:
        """Ekran görüntüsü koordinatını gerçek ekran koordinatına çevir."""
        x, y = koord
        return (int(round(x / self.olcek)) + self.mon["left"],
                int(round(y / self.olcek)) + self.mon["top"])

    def _gorsel_blok(self, img: Image.Image) -> list[dict]:
        tampon = io.BytesIO()
        img.save(tampon, format="PNG", optimize=True)
        veri = base64.standard_b64encode(tampon.getvalue()).decode()
        return [{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": veri}}]

    def _yakala(self, bolge: dict | None = None) -> Image.Image:
        with mss.mss() as sct:
            ham = sct.grab(bolge or self.mon)
        return Image.frombytes("RGB", ham.size, ham.bgra, "raw", "BGRX")

    def ekran_goruntusu_pil(self) -> Image.Image:
        self.son_goruntu = self._yakala().resize(self.ss_boyut, Image.LANCZOS)
        self.goruntu_no += 1
        return self.son_goruntu

    def ekran_goruntusu(self) -> list[dict]:
        return self._gorsel_blok(self.ekran_goruntusu_pil())

    def _basili_tut(self, tuslar: list[str]):
        for t in tuslar:
            pyautogui.keyDown(t)

    def _birak(self, tuslar: list[str]):
        for t in reversed(tuslar):
            pyautogui.keyUp(t)

    def _tikla(self, girdi: dict, dugme: str, sayi: int):
        mod = _kombinasyon(girdi.get("text"))
        if girdi.get("coordinate"):
            x, y = self._ekrana(girdi["coordinate"])
            pyautogui.moveTo(x, y, duration=0.15)
        self._basili_tut(mod)
        try:
            pyautogui.click(button=dugme, clicks=sayi, interval=0.08)
        finally:
            self._birak(mod)
        return "OK"

    def _bekle(self, saniye: float):
        bitis = time.time() + min(float(saniye), 300)
        while time.time() < bitis:
            self._kontrol()
            time.sleep(0.1)

    # ---------- ana giriş ----------
    def calistir(self, ad: str, girdi: dict):
        """Bir üye aracı çalıştırır. Sonuç: tool_result içeriği (metin veya görsel blokları)."""
        self._kontrol()
        sonuc = self._calistir(ad, girdi or {})
        if ad not in ("screenshot", "zoom", "cursor_position", "wait"):
            time.sleep(self.eylem_gecikmesi)  # arayüzün tepki vermesine zaman tanı
        return sonuc

    def _calistir(self, ad: str, g: dict):
        if ad == "screenshot":
            return self.ekran_goruntusu()
        if ad == "zoom":
            x0, y0 = self._ekrana(g["region"][:2])
            x1, y1 = self._ekrana(g["region"][2:])
            if x1 <= x0 or y1 <= y0:
                raise ValueError("Geçersiz bölge: sağ alt köşe sol üst köşeden büyük olmalı")
            img = self._yakala({"left": x0, "top": y0, "width": x1 - x0, "height": y1 - y0})
            # Bölgeyi tam çözünürlükte al, en-boy oranını koruyarak ekran görüntüsü boyutuna sığdır (büyüt)
            k = min(self.ss_boyut[0] / img.width, self.ss_boyut[1] / img.height)
            img = img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)
            return self._gorsel_blok(img)
        if ad == "left_click":
            return self._tikla(g, "left", 1)
        if ad == "right_click":
            return self._tikla(g, "right", 1)
        if ad == "middle_click":
            return self._tikla(g, "middle", 1)
        if ad == "double_click":
            return self._tikla(g, "left", 2)
        if ad == "triple_click":
            return self._tikla(g, "left", 3)
        if ad == "left_click_drag":
            mod = _kombinasyon(g.get("text"))
            sx, sy = self._ekrana(g["start_coordinate"])
            ex, ey = self._ekrana(g["coordinate"])
            pyautogui.moveTo(sx, sy, duration=0.15)
            self._basili_tut(mod)
            try:
                pyautogui.mouseDown()
                pyautogui.moveTo(ex, ey, duration=0.5)
                pyautogui.mouseUp()
            finally:
                self._birak(mod)
            return "OK"
        if ad == "mouse_move":
            x, y = self._ekrana(g["coordinate"])
            pyautogui.moveTo(x, y, duration=0.15)
            return "OK"
        if ad == "left_mouse_down":
            pyautogui.mouseDown()
            return "OK"
        if ad == "left_mouse_up":
            pyautogui.mouseUp()
            return "OK"
        if ad == "cursor_position":
            px, py = pyautogui.position()
            x = int((px - self.mon["left"]) * self.olcek)
            y = int((py - self.mon["top"]) * self.olcek)
            return f"X={x}, Y={y}"
        if ad == "scroll":
            mod = _kombinasyon(g.get("text"))
            if g.get("coordinate"):
                x, y = self._ekrana(g["coordinate"])
                pyautogui.moveTo(x, y, duration=0.1)
            miktar = int(g.get("scroll_amount", 3))
            yon = g.get("scroll_direction", "down")
            self._basili_tut(mod)
            try:
                if yon in ("up", "down"):
                    pyautogui.scroll(miktar * (1 if yon == "up" else -1) * 100)
                else:
                    pyautogui.hscroll(miktar * (1 if yon == "right" else -1) * 100)
            finally:
                self._birak(mod)
            return "OK"
        if ad == "type":
            metin = g["text"]
            # write() ASCII dışı karakterlerde (ç, ğ, ş...) sorun çıkarır: pano ile yapıştır
            if metin.isascii():
                pyautogui.write(metin, interval=0.01)
            else:
                import pyperclip

                eski = pyperclip.paste()
                pyperclip.copy(metin)
                pyautogui.hotkey("ctrl", "v")
                time.sleep(0.1)
                pyperclip.copy(eski)
            return "OK"
        if ad == "key":
            tuslar = _kombinasyon(g["text"])
            for _ in range(max(1, min(int(g.get("repeat", 1)), 100))):
                self._kontrol()
                pyautogui.hotkey(*tuslar) if len(tuslar) > 1 else pyautogui.press(tuslar[0])
            return "OK"
        if ad == "hold_key":
            tuslar = _kombinasyon(g["text"])
            self._basili_tut(tuslar)
            try:
                self._bekle(g.get("duration", 1))
            finally:
                self._birak(tuslar)
            return "OK"
        if ad == "wait":
            self._bekle(g.get("duration", 1))
            return "OK"
        raise ValueError(f"Bilinmeyen eylem: {ad}")
