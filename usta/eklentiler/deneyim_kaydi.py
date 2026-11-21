"""Deneyim kaydı: yerel modeli gerçekten EĞİTMEK için veri toplar.

Başarıyla doğrulanan her görevin adımlarını (o anki ekran görüntüsü + yapılan eylem) kaydeder.
Biriken veri, yerel görsel modele ince ayar (LoRA fine-tuning) yapmak için kullanılabilir:
böylece model senin uygulamalarında, senin ekranında doğru yere tıklamayı öğrenir.
Ayrıntılar: egitim_verisi/EGITIM.md

Veri biçimi (LLaMA-Factory / ShareGPT çok kipli biçimi):
  egitim_verisi/veri.jsonl   → her satır: {"messages": [...], "images": ["bolumler/.../adim_003.png"]}
  egitim_verisi/bolumler/    → görev başına klasör: ekran görüntüleri + adimlar.jsonl

Uyarı: Ekran görüntüleri ekranda görünen her şeyi (açık belgeler, isimler) içerir. Bu klasörü
paylaşmadan önce gözden geçir.
"""
from __future__ import annotations

import datetime as dt
import json
import shutil
from pathlib import Path

AD = "deneyim_kaydi"
ACIKLAMA = "Başarılı görevleri (ekran + eylem) kaydeder: yerel modele ince ayar (eğitim) verisi"
ARACLAR: list = []   # araç eklemez, yalnızca olayları dinler

KLASOR = Path(__file__).resolve().parent.parent / "egitim_verisi"
KAYDEDILECEK = {"left_click", "right_click", "middle_click", "double_click", "triple_click", "left_click_drag",
                "mouse_move", "scroll", "type", "key", "hold_key", "hucreye_tikla", "metne_tikla", "ogeye_tikla",
                "blender_python", "photoshop_js"}

_bolum: dict | None = None


def calistir(ad, girdi, ajan):  # araç yok
    raise ValueError("Bu eklentinin aracı yok")


def olay(ad: str, ajan, **v):
    global _bolum
    if ad == "deneme_basladi":
        _bolum = {"gorev": v["gorev"], "uygulama": v["uygulama"], "adimlar": [],
                  "ss_boyut": list(ajan.pc.ss_boyut), "beyin": ajan.ay.eylem_saglayici}
    elif ad == "eylem" and _bolum is not None:
        if v["arac"] in KAYDEDILECEK and not v.get("hata"):
            # Aynı turda art arda yapılan eylemlerde ekran değişmiş olabilir: yalnızca taze bir
            # ekran görüntüsünden sonraki ilk eylem eğitim örneği olur, diğerleri yalnızca kayda geçer.
            img, no = getattr(ajan.pc, "son_goruntu", None), getattr(ajan.pc, "goruntu_no", 0)
            taze = img is not None and no != _bolum.get("son_no")
            _bolum["son_no"] = no
            eylem, girdi = v["arac"], dict(v["girdi"])
            if eylem in ("hucreye_tikla", "metne_tikla", "ogeye_tikla"):
                # Yardımcı tıklamaları gerçek koordinatlı tıklamaya çevir: model doğrudan konumu öğrensin
                import pyautogui
                px, py = pyautogui.position()
                pc = ajan.pc
                xy = [round((px - pc.mon["left"]) * pc.olcek), round((py - pc.mon["top"]) * pc.olcek)]
                eylem = {"sag": "right_click", "cift": "double_click"}.get(girdi.get("tus"), "left_click")
                girdi = {"coordinate": xy}
            _bolum["adimlar"].append({"eylem": eylem, "girdi": girdi, "goruntu": img.copy() if taze else None})
    elif ad == "gorev_bitti" and _bolum is not None:
        if v.get("basarili") and _bolum["adimlar"]:
            yol = _kaydet(_bolum)
            ajan.log("basari", f"🎓 Eğitim verisine eklendi: {len(_bolum['adimlar'])} adım ({yol.name})")
        _bolum = None


def _kaydet(b: dict) -> Path:
    zaman = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    klasor = KLASOR / "bolumler" / f"{zaman}_{b['uygulama'].lower()}"
    klasor.mkdir(parents=True, exist_ok=True)
    satirlar, egitim = [], []
    gecmis: list[str] = []
    for i, a in enumerate(b["adimlar"], 1):
        resim = None
        if a["goruntu"] is not None:
            resim = f"adim_{i:03d}.png"
            a["goruntu"].save(klasor / resim)
        eylem = {"ad": a["eylem"], **a["girdi"]}
        satirlar.append({"adim": i, "goruntu": resim, "eylem": eylem})
        if resim:
            onceki = ("\nÖnceki adımlar: " + "; ".join(gecmis[-5:])) if gecmis else ""
            egitim.append({
                "messages": [
                    {"role": "user", "content": f"<image>Uygulama: {b['uygulama']}\nGörev: {b['gorev']}{onceki}\n"
                                                f"Ekran {b['ss_boyut'][0]}x{b['ss_boyut'][1]} piksel. Sıradaki eylem nedir?"},
                    {"role": "assistant", "content": json.dumps({"eylemler": [eylem]}, ensure_ascii=False)},
                ],
                "images": [str(Path("bolumler") / klasor.name / resim).replace("\\", "/")],
            })
        gecmis.append(a["eylem"])
    meta = {"gorev": b["gorev"], "uygulama": b["uygulama"], "ss_boyut": b["ss_boyut"], "beyin": b["beyin"]}
    with (klasor / "adimlar.jsonl").open("w", encoding="utf-8") as f:
        f.write(json.dumps(meta, ensure_ascii=False) + "\n")
        for s in satirlar:
            f.write(json.dumps(s, ensure_ascii=False) + "\n")
    with (KLASOR / "veri.jsonl").open("a", encoding="utf-8") as f:
        for e in egitim:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    rehber = Path(__file__).resolve().parent / "_EGITIM.md"
    if rehber.exists() and not (KLASOR / "EGITIM.md").exists():
        shutil.copy(rehber, KLASOR / "EGITIM.md")
    return klasor
