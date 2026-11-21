"""Usta – karmaşık uygulamaları (Blender, Photoshop, ...) kullanmayı öğrenen asistan.

Çalıştır:  python usta.py
"""
from __future__ import annotations

import json
import os
import platform
import queue
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, scrolledtext, simpledialog, ttk

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hafiza  # noqa: E402
from ajan import Ajan, Ayarlar  # noqa: E402

AYAR_DOSYASI = Path(__file__).resolve().parent / "ayarlar.json"
UYGULAMALAR = ["Blender", "Photoshop", "GIMP", "Krita", "Inkscape", "Genel"]
RENKLER = {"bilgi": "#9aa4b2", "dusunce": "#e6e6e6", "eylem": "#7cc4ff",
           "hata": "#ff8a80", "basari": "#8be28b", "sen": "#ffd479"}


def ayarlari_oku() -> dict:
    try:
        return json.loads(AYAR_DOSYASI.read_text(encoding="utf-8"))
    except Exception:
        return {}


def ayarlari_yaz(d: dict):
    AYAR_DOSYASI.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")


class UstaPenceresi:
    def __init__(self):
        self.kok = tk.Tk()
        self.kok.title("Usta")
        self.kok.geometry("600x660")
        self.kok.configure(bg="#1e1f24")
        self.kuyruk: queue.Queue = queue.Queue()
        self.durdur = threading.Event()
        self.calisiyor = False
        self.ayar = ayarlari_oku()
        self._arayuz()
        self.kok.after(100, self._kuyrugu_isle)
        self.kok.after(300, self._ekran_kaydindan_gizle)

    # ------------------------------------------------------------- arayüz
    def _arayuz(self):
        stil = ttk.Style()
        stil.theme_use("clam")
        for w in ("TFrame", "TLabel", "TRadiobutton", "TCheckbutton"):
            stil.configure(w, background="#1e1f24", foreground="#e6e6e6")
        stil.configure("TButton", padding=6)

        ust = ttk.Frame(self.kok, padding=10)
        ust.pack(fill="x")
        ttk.Label(ust, text="Uygulama:").grid(row=0, column=0, sticky="w")
        self.uygulama = ttk.Combobox(ust, values=UYGULAMALAR, width=18)
        self.uygulama.set(self.ayar.get("uygulama", "Blender"))
        self.uygulama.grid(row=0, column=1, sticky="w", padx=6)
        ttk.Button(ust, text="📘 Hafıza", command=self._hafizayi_ac).grid(row=0, column=3, sticky="e", padx=4)
        ttk.Button(ust, text="⚙ Ayarlar", command=self._ayarlar).grid(row=0, column=4, sticky="e")
        ust.columnconfigure(2, weight=1)

        ttk.Label(self.kok, text="Ne yapayım?", padding=(10, 0)).pack(anchor="w")
        self.girdi = tk.Text(self.kok, height=4, wrap="word", bg="#2a2c33", fg="#ffffff",
                             insertbackground="#ffffff", relief="flat", font=("Segoe UI", 11))
        self.girdi.pack(fill="x", padx=10, pady=4)
        self.girdi.insert("1.0", "Örn: Blender'da kırmızı bir küre ekle ve render al")
        self.girdi.bind("<FocusIn>", self._ornek_sil)
        self.girdi.bind("<Control-Return>", lambda e: (self._baslat(), "break")[1])

        mod = ttk.Frame(self.kok, padding=(10, 2))
        mod.pack(fill="x")
        self.israrla = tk.BooleanVar(value=self.ayar.get("israrla", True))
        ttk.Radiobutton(mod, text="Bir kez dene", variable=self.israrla, value=False).pack(side="left")
        ttk.Radiobutton(mod, text="Başarana kadar dene", variable=self.israrla, value=True).pack(side="left", padx=10)
        ttk.Label(mod, text="en fazla").pack(side="left")
        self.maks_deneme = tk.Spinbox(mod, from_=0, to=100, width=4)
        self.maks_deneme.delete(0, "end")
        self.maks_deneme.insert(0, str(self.ayar.get("maks_deneme", 5)))
        self.maks_deneme.pack(side="left", padx=4)
        ttk.Label(mod, text="deneme (0 = sınırsız)").pack(side="left")

        dugmeler = ttk.Frame(self.kok, padding=10)
        dugmeler.pack(fill="x")
        self.baslat_d = ttk.Button(dugmeler, text="▶ Yap", command=self._baslat)
        self.baslat_d.pack(side="left")
        self.ses_d = ttk.Button(dugmeler, text="🎤 Söyle", command=self._sesle)
        self.ses_d.pack(side="left", padx=6)
        self.kesfet_d = ttk.Button(dugmeler, text="🧭 Keşfet ve öğren", command=self._kesfet)
        self.kesfet_d.pack(side="left")
        self.durdur_d = ttk.Button(dugmeler, text="■ Durdur", command=self._durdur, state="disabled")
        self.durdur_d.pack(side="left", padx=6)

        self.gunluk = scrolledtext.ScrolledText(self.kok, wrap="word", bg="#15161a", fg="#e6e6e6",
                                                relief="flat", font=("Consolas", 10), state="disabled")
        self.gunluk.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        for tur, renk in RENKLER.items():
            self.gunluk.tag_config(tur, foreground=renk)
        self._yaz("bilgi", "Merhaba! Bir uygulama seç, ne yapmamı istediğini yaz (veya 🎤 ile söyle) ve ▶ Yap'a bas.\n"
                           "Acil durdurma: fareyi ekranın SOL ÜST köşesine götür veya ■ Durdur'a bas.")

    def _ornek_sil(self, _):
        if self.girdi.get("1.0", "end").strip().startswith("Örn:"):
            self.girdi.delete("1.0", "end")

    def _ekran_kaydindan_gizle(self):
        """Windows 10 (2004+) ve 11'de bu pencere ekran görüntülerine çıkmaz; Claude onu görmez."""
        if platform.system() != "Windows":
            return
        try:
            import ctypes

            hwnd = ctypes.windll.user32.GetParent(self.kok.winfo_id())
            ctypes.windll.user32.SetWindowDisplayAffinity(hwnd, 0x11)  # WDA_EXCLUDEFROMCAPTURE
        except Exception:
            pass

    # ---------------------------------------------------- iş parçacığı köprüsü
    def _yaz(self, tur: str, metin: str):
        self.gunluk.configure(state="normal")
        self.gunluk.insert("end", metin.rstrip() + "\n", tur)
        self.gunluk.see("end")
        self.gunluk.configure(state="disabled")

    def _log(self, tur: str, metin: str):  # arka plan iş parçacığından çağrılır
        self.kuyruk.put(("log", tur, metin))

    def _sor(self, soru: str) -> str:  # arka plan iş parçacığından çağrılır
        cevap_kutusu: dict = {}
        hazir = threading.Event()
        self.kuyruk.put(("sor", soru, (cevap_kutusu, hazir)))
        while not hazir.wait(0.2):
            if self.durdur.is_set():
                return ""
        return cevap_kutusu.get("cevap", "")

    def _kuyrugu_isle(self):
        try:
            while True:
                is_ = self.kuyruk.get_nowait()
                if is_[0] == "log":
                    self._yaz(is_[1], is_[2])
                elif is_[0] == "sor":
                    kutu, hazir = is_[2]
                    self.kok.attributes("-topmost", True)
                    kutu["cevap"] = simpledialog.askstring("Usta soruyor", is_[1], parent=self.kok) or ""
                    hazir.set()
                elif is_[0] == "bitti":
                    self._bitti()
                elif is_[0] == "ses":
                    self.girdi.delete("1.0", "end")
                    self.girdi.insert("1.0", is_[1])
                    self.ses_d.configure(state="normal", text="🎤 Söyle")
        except queue.Empty:
            pass
        self.kok.after(100, self._kuyrugu_isle)

    # --------------------------------------------------------------- eylemler
    def _api_anahtari(self) -> str | None:
        anahtar = self.ayar.get("api_anahtari") or os.environ.get("ANTHROPIC_API_KEY")
        if not anahtar:
            anahtar = simpledialog.askstring(
                "API anahtarı", "Anthropic API anahtarınızı girin (console.anthropic.com):", show="*", parent=self.kok)
            if anahtar:
                self.ayar["api_anahtari"] = anahtar.strip()
                ayarlari_yaz(self.ayar)
        return anahtar

    def _calistir(self, gorev: str, israrla: bool, maks_deneme: int):
        if self.calisiyor:
            return
        anahtar = self._api_anahtari()
        if not anahtar:
            messagebox.showwarning("Usta", "API anahtarı olmadan çalışamam.")
            return
        uyg = self.uygulama.get().strip() or "Genel"
        self.ayar.update(uygulama=uyg, israrla=israrla, maks_deneme=maks_deneme)
        ayarlari_yaz(self.ayar)
        ayar = Ayarlar(model=self.ayar.get("model", "claude-opus-5-5"), efor=self.ayar.get("efor", "medium"),
                       maks_adim=int(self.ayar.get("maks_adim", 80)),
                       maks_uzun_kenar=int(self.ayar.get("maks_uzun_kenar", 1568)))
        self.durdur.clear()
        self.calisiyor = True
        self.baslat_d.configure(state="disabled")
        self.kesfet_d.configure(state="disabled")
        self.durdur_d.configure(state="normal")
        self._yaz("sen", f"\n▶ [{uyg}] {gorev}")
        self._kucult()

        def is_():
            try:
                ajan = Ajan(ayar, self._log, self._sor, self.durdur, api_anahtari=anahtar)
                ajan.gorev(gorev, uyg, israrla=israrla, maks_deneme=maks_deneme)
            except Exception as e:
                self._log("hata", f"Beklenmeyen hata: {type(e).__name__}: {e}")
            finally:
                self.kuyruk.put(("bitti",))

        threading.Thread(target=is_, daemon=True).start()

    def _baslat(self):
        gorev = self.girdi.get("1.0", "end").strip()
        if not gorev or gorev.startswith("Örn:"):
            messagebox.showinfo("Usta", "Önce ne yapmamı istediğini yaz.")
            return
        try:
            maks = int(self.maks_deneme.get())
        except ValueError:
            maks = 5
        self._calistir(gorev, self.israrla.get(), maks)

    def _kesfet(self):
        uyg = self.uygulama.get().strip() or "Genel"
        gorev = (f"{uyg} uygulamasını keşfet ve kullanmayı öğren. Uygulamayı aç (açık değilse), ana menüleri, "
                 "panelleri, araç çubuklarını ve önemli kısayolları incele; birkaç basit deneme işlemi yap "
                 "(yeni/boş bir belgede veya sahnede – kullanıcının mevcut çalışmasını değiştirme). "
                 "Öğrendiğin her önemli şeyi ders_kaydet ile kaydet. Kaydetmeye değer en az 10 ders "
                 "topladığında gorev_bitti çağır.")
        self._calistir(gorev, israrla=False, maks_deneme=1)

    def _durdur(self):
        self.durdur.set()
        self._yaz("bilgi", "Durduruluyor… (mevcut adım bitince)")

    def _bitti(self):
        self.calisiyor = False
        self.baslat_d.configure(state="normal")
        self.kesfet_d.configure(state="normal")
        self.durdur_d.configure(state="disabled")
        self._buyut()

    def _kucult(self):
        """Çalışırken pencere küçük, hep üstte ve sağ altta durur; uygulamanın önünü kapatmaz."""
        self._eski_geo = self.kok.geometry()
        g, y = 420, 260
        self.kok.geometry(f"{g}x{y}+{self.kok.winfo_screenwidth() - g - 10}+{self.kok.winfo_screenheight() - y - 60}")
        self.kok.attributes("-topmost", True)

    def _buyut(self):
        self.kok.attributes("-topmost", False)
        if getattr(self, "_eski_geo", None):
            self.kok.geometry(self._eski_geo)

    def _hafizayi_ac(self):
        hafiza.KLASOR.mkdir(exist_ok=True)
        yol = str(hafiza.KLASOR)
        if platform.system() == "Windows":
            os.startfile(yol)  # noqa
        elif platform.system() == "Darwin":
            subprocess.Popen(["open", yol])
        else:
            subprocess.Popen(["xdg-open", yol])

    def _sesle(self):
        """Mikrofondan Türkçe komut al (Google konuşma tanıma; internet gerekir)."""
        try:
            import speech_recognition as sr
        except ImportError:
            messagebox.showinfo("Usta", "Sesli komut için: pip install SpeechRecognition pyaudio")
            return
        self.ses_d.configure(state="disabled", text="🎤 Dinliyorum…")

        def dinle():
            r = sr.Recognizer()
            try:
                with sr.Microphone() as kaynak:
                    r.adjust_for_ambient_noise(kaynak, duration=0.5)
                    ses = r.listen(kaynak, timeout=8, phrase_time_limit=20)
                metin = r.recognize_google(ses, language="tr-TR")
            except Exception as e:
                metin = ""
                self._log("hata", f"Ses anlaşılamadı: {e}")
            self.kuyruk.put(("ses", metin))

        threading.Thread(target=dinle, daemon=True).start()

    def _ayarlar(self):
        p = tk.Toplevel(self.kok)
        p.title("Ayarlar")
        p.configure(bg="#1e1f24")
        alanlar = {
            "api_anahtari": ("API anahtarı", self.ayar.get("api_anahtari", ""), True),
            "model": ("Model", self.ayar.get("model", "claude-opus-5-5"), False),
            "efor": ("Efor (low/medium/high/xhigh/max)", self.ayar.get("efor", "medium"), False),
            "maks_adim": ("Deneme başına en fazla adım", self.ayar.get("maks_adim", 80), False),
            "maks_uzun_kenar": ("Ekran görüntüsü uzun kenarı (px)", self.ayar.get("maks_uzun_kenar", 1568), False),
        }
        girisler = {}
        for i, (anahtar, (etiket, deger, gizli)) in enumerate(alanlar.items()):
            ttk.Label(p, text=etiket).grid(row=i, column=0, sticky="w", padx=8, pady=4)
            e = ttk.Entry(p, width=36, show="*" if gizli else "")
            e.insert(0, str(deger))
            e.grid(row=i, column=1, padx=8, pady=4)
            girisler[anahtar] = e

        def kaydet():
            for k, e in girisler.items():
                v = e.get().strip()
                self.ayar[k] = int(v) if k in ("maks_adim", "maks_uzun_kenar") and v.isdigit() else v
            ayarlari_yaz(self.ayar)
            p.destroy()

        ttk.Button(p, text="Kaydet", command=kaydet).grid(row=len(alanlar), column=1, sticky="e", padx=8, pady=8)

    def calis(self):
        self.kok.mainloop()


if __name__ == "__main__":
    UstaPenceresi().calis()
