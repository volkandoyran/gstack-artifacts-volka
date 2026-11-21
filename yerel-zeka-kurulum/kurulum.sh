#!/usr/bin/env bash
# Yerel Zeka Kurulumu – macOS ve Linux
# Çalıştır:  bash kurulum.sh
set -euo pipefail

KLASOR="$(cd "$(dirname "$0")" && pwd)"
USTA="$(dirname "$KLASOR")/usta"
API="http://localhost:11434"
yesil() { printf "\033[32m[OK] %s\033[0m\n" "$*"; }
sari()  { printf "\033[33m[!]  %s\033[0m\n" "$*"; }
baslik(){ printf "\n\033[36m==== %s ====\033[0m\n" "$*"; }

baslik "1) Donanım"
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  CIP="$(sysctl -n machdep.cpu.brand_string)"
  echo "Mac: $CIP, birleşik bellek $RAM GB"
  # Apple Silicon'da bellek ekran kartıyla paylaşılır; yaklaşık %70'i modele ayrılabilir
  VRAM=$(( RAM * 70 / 100 ))
else
  RAM=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1048576 ))
  echo "Linux: RAM $RAM GB"
  VRAM=0
  if command -v nvidia-smi >/dev/null; then
    VRAM=$(( $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | sort -nr | head -1) / 1024 ))
    echo "NVIDIA ekran kartı: $VRAM GB"
  else
    sari "NVIDIA ekran kartı bulunamadı; model işlemcide (yavaş) çalışır."
  fi
fi

if   [ "$VRAM" -ge 24 ]; then MODEL="qwen3-vl:32b"
elif [ "$VRAM" -ge 10 ]; then MODEL="qwen3-vl:8b"
elif [ "$VRAM" -ge 6 ] || [ "$RAM" -ge 16 ]; then MODEL="qwen3-vl:4b"
else MODEL="qwen3-vl:2b"; fi
echo "Usta için önerilen model: $MODEL"

baslik "2) Ollama"
if ! command -v ollama >/dev/null; then
  if [ "$OS" = "Darwin" ]; then
    if command -v brew >/dev/null; then brew install --cask ollama; else
      sari "https://ollama.com/download/mac adresinden indirip kur, sonra bu betiği yeniden çalıştır."; exit 1; fi
  else
    echo "Resmi kurulum betiği indirilecek: https://ollama.com/install.sh"
    read -rp "Devam edilsin mi? (e/h) " c; [ "$c" = "e" ] || exit 1
    curl -fsSL https://ollama.com/install.sh | sh
  fi
fi
yesil "Ollama: $(ollama --version 2>/dev/null | tail -1)"
if ! curl -s "$API/api/version" >/dev/null; then
  if [ "$OS" = "Darwin" ]; then open -a Ollama; else (OLLAMA_CONTEXT_LENGTH=16384 nohup ollama serve >/dev/null 2>&1 &); fi
  sleep 5
fi
if [ "$OS" = "Darwin" ]; then
  launchctl setenv OLLAMA_CONTEXT_LENGTH 16384 || true
  sari "Bağlam ayarının (16384) etkinleşmesi için Ollama'yı menü çubuğundan kapatıp yeniden aç."
elif command -v systemctl >/dev/null && systemctl list-unit-files 2>/dev/null | grep -q '^ollama'; then
  sari "Linux servisinde bağlamı büyütmek için: sudo systemctl edit ollama  →  [Service] Environment=\"OLLAMA_CONTEXT_LENGTH=16384\""
fi

baslik "3) Model"
read -rp "İndirilecek model [$MODEL]: " m; MODEL="${m:-$MODEL}"
ollama pull "$MODEL"
yesil "$MODEL hazır."

baslik "4) Test"
curl -s "$API/v1/chat/completions" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Tek cümleyle merhaba de.\"}],\"max_tokens\":60}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" \
  && yesil "OpenAI uyumlu API çalışıyor." || sari "API testi başarısız."

baslik "5) Usta"
if [ -f "$USTA/usta.py" ]; then
  python3 -m venv "$USTA/.venv" && "$USTA/.venv/bin/pip" install -q -r "$USTA/requirements.txt"
  KOORD="0-1000"; case "$MODEL" in qwen2.5*|gemma*|llama*|mistral*) KOORD="piksel";; esac
  python3 - "$USTA/ayarlar.json" "$MODEL" "$KOORD" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); a = json.loads(p.read_text("utf-8-sig")) if p.exists() else {}
a.update(yerel_url="http://localhost:11434/v1", yerel_model=sys.argv[2], yerel_koordinat=sys.argv[3])
if not a.get("api_anahtari"):
    a.update(cevrimdisi=True, eylem_saglayici="yerel", dogrulama_saglayici="yerel", hafiza_saglayici="yerel")
p.write_text(json.dumps(a, ensure_ascii=False, indent=2), "utf-8")
PY
  yesil "Usta yerel zekaya bağlandı. Başlat: $USTA/.venv/bin/python $USTA/usta.py"
  [ "$OS" = "Darwin" ] && sari "macOS: Terminal'e Ekran Kaydı ve Erişilebilirlik izni ver (Sistem Ayarları > Gizlilik)."
else
  sari "Usta klasörü bulunamadı ($USTA)."
fi
