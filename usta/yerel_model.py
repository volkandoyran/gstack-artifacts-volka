"""Yerel (çevrimdışı) yapay zeka bağlantısı.

OpenAI uyumlu sohbet API'si sunan her yerel sunucuyla çalışır:
  - Ollama     → http://localhost:11434/v1
  - LM Studio  → http://localhost:1234/v1
  - llama.cpp  → http://localhost:8080/v1   (llama-server)
  - Jan        → http://localhost:1337/v1
Ek paket gerektirmez (yalnızca Python standart kütüphanesi).
"""
from __future__ import annotations

import base64
import io
import json
import re
import urllib.error
import urllib.request

from PIL import Image

HAZIR_ADRESLER = {
    "Ollama": "http://localhost:11434/v1",
    "LM Studio": "http://localhost:1234/v1",
    "llama.cpp": "http://localhost:8080/v1",
    "Jan": "http://localhost:1337/v1",
}


class YerelHata(RuntimeError):
    pass


class YerelModel:
    def __init__(self, url: str, model: str, zaman_asimi: float = 600):
        self.url = url.rstrip("/")
        self.model = model
        self.zaman_asimi = zaman_asimi

    def _post(self, yol: str, govde: dict) -> dict:
        istek = urllib.request.Request(
            self.url + yol, data=json.dumps(govde).encode("utf-8"),
            headers={"Content-Type": "application/json", "Authorization": "Bearer yerel"})
        try:
            with urllib.request.urlopen(istek, timeout=self.zaman_asimi) as y:
                return json.loads(y.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise YerelHata(f"Yerel model hatası {e.code}: {e.read().decode('utf-8', 'replace')[:500]}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            raise YerelHata(f"Yerel yapay zeka sunucusuna ulaşılamadı ({self.url}). Ollama / LM Studio "
                            f"çalışıyor mu? Ayrıntı: {e}")

    def modeller(self) -> list[str]:
        try:
            with urllib.request.urlopen(self.url + "/models", timeout=10) as y:
                return [m["id"] for m in json.loads(y.read().decode("utf-8")).get("data", [])]
        except Exception as e:
            raise YerelHata(f"Model listesi alınamadı ({self.url}): {e}")

    def sohbet(self, mesajlar: list[dict], maks_jeton: int = 2048, sicaklik: float = 0.2) -> str:
        y = self._post("/chat/completions", {
            "model": self.model, "messages": mesajlar,
            "max_tokens": maks_jeton, "temperature": sicaklik, "stream": False,
        })
        try:
            return y["choices"][0]["message"].get("content") or ""
        except (KeyError, IndexError):
            raise YerelHata(f"Beklenmeyen yanıt: {str(y)[:300]}")

    def sor(self, metin: str, goruntu: Image.Image | None = None, sistem: str | None = None,
            maks_jeton: int = 2048) -> str:
        mesajlar = [{"role": "system", "content": sistem}] if sistem else []
        mesajlar.append({"role": "user", "content": icerik(metin, goruntu)})
        return self.sohbet(mesajlar, maks_jeton)


def goruntu_parcasi(img: Image.Image) -> dict:
    tampon = io.BytesIO()
    img.convert("RGB").save(tampon, format="JPEG", quality=85)
    veri = base64.standard_b64encode(tampon.getvalue()).decode()
    return {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{veri}"}}


def icerik(metin: str, goruntu: Image.Image | None = None) -> list[dict] | str:
    if goruntu is None:
        return metin
    return [{"type": "text", "text": metin}, goruntu_parcasi(goruntu)]


def json_cikar(metin: str) -> dict:
    """Model yanıtındaki ilk JSON nesnesini bulur (```json bloklarını ve düşünce etiketlerini atlar)."""
    metin = re.sub(r"<think>.*?</think>", "", metin, flags=re.S)
    blok = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", metin, flags=re.S)
    adaylar = [blok.group(1)] if blok else []
    bas = metin.find("{")
    while bas != -1:
        derinlik, i = 0, bas
        for i in range(bas, len(metin)):
            if metin[i] == "{":
                derinlik += 1
            elif metin[i] == "}":
                derinlik -= 1
                if derinlik == 0:
                    break
        adaylar.append(metin[bas:i + 1])
        bas = metin.find("{", bas + 1) if derinlik else -1
    for a in adaylar:
        try:
            return json.loads(a)
        except json.JSONDecodeError:
            continue
    raise YerelHata(f"Modelin yanıtında geçerli JSON bulunamadı: {metin[:300]}")
