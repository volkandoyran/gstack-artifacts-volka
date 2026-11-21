# Yerel Zeka Kurulum Sihirbazı (Windows 10/11)
# Çevrimdışı çalışabilen bir yapay zekayı (Ollama + görsel model) adım adım kurar ve Usta'ya bağlar.
# Çalıştırmak için: BASLAT.bat dosyasına çift tıkla.
# Windows PowerShell 5.1 ile uyumludur.

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Yerel Zeka Kurulum Sihirbazı"

$Klasor   = $PSScriptRoot
$Katalog  = Get-Content -Raw -Encoding UTF8 (Join-Path $Klasor "modeller.json") | ConvertFrom-Json
$Gunluk   = Join-Path $Klasor "kurulum_gunlugu.txt"
$OllamaApi = "http://localhost:11434"
$script:Donanim = $null
$script:Oneri = $null

try { Start-Transcript -Path $Gunluk -Append | Out-Null } catch {}

# ----------------------------------------------------------------- yardımcılar
function Baslik($metin) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  $metin" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}
function Bilgi($m)  { Write-Host "  $m" }
function Iyi($m)    { Write-Host "  [OK] $m" -ForegroundColor Green }
function Uyari($m)  { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Hata($m)   { Write-Host "  [X]  $m" -ForegroundColor Red }
function Bekle      { Write-Host ""; Read-Host "  Devam etmek için Enter'a bas" | Out-Null }

function Evet($soru, $varsayilan = "E") {
    $c = Read-Host "  $soru (E/H) [$varsayilan]"
    if ([string]::IsNullOrWhiteSpace($c)) { $c = $varsayilan }
    return $c.Trim().ToUpper().StartsWith("E")
}

function Yolu-Yenile {
    # Yeni kurulan programların (ollama, python, git) bu pencerede de bulunması için
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Komut-Var($ad) { return [bool](Get-Command $ad -ErrorAction SilentlyContinue) }

function Internet-Var {
    try { Invoke-WebRequest -Uri "https://ollama.com" -Method Head -UseBasicParsing -TimeoutSec 8 | Out-Null; return $true }
    catch { return $false }
}

function Winget-Kur($id, $ad, $yedekUrl) {
    if (-not (Evet "$ad bilgisayarına kurulacak. Onaylıyor musun?")) { Uyari "$ad kurulmadı (senin seçimin)."; return $false }
    if ($id -and (Komut-Var "winget")) {
        Bilgi "$ad winget ile kuruluyor ($id)…"
        & winget install --id $id -e --accept-package-agreements --accept-source-agreements | Out-Host
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {  # -1978335189: zaten kurulu
            Yolu-Yenile; Iyi "$ad kuruldu."; return $true
        }
        Uyari "winget başarısız oldu (kod $LASTEXITCODE)."
    }
    if ($yedekUrl) {
        Uyari "$ad için resmi indirme sayfasını açıyorum. Kurulumu tamamlayıp buraya dön."
        Start-Process $yedekUrl
        Bekle
        Yolu-Yenile
    }
    return $false
}

function Ollama-Calisiyor {
    try { Invoke-RestMethod -Uri "$OllamaApi/api/version" -TimeoutSec 5 | Out-Null; return $true } catch { return $false }
}

function Ollama-Baslat {
    if (Ollama-Calisiyor) { return $true }
    $uygulama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama app.exe"
    if (Test-Path $uygulama) { Start-Process $uygulama } elseif (Komut-Var "ollama") { Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden }
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; if (Ollama-Calisiyor) { return $true } }
    return $false
}

function Python-Bul {
    # Windows'taki 'python' komutu Microsoft Store kısayolu olabilir; gerçek python.exe'yi bul
    $adaylar = @()
    foreach ($s in @("312", "313", "311", "310")) {
        $adaylar += Join-Path $env:LOCALAPPDATA "Programs\Python\Python$s\python.exe"
        $adaylar += Join-Path $env:ProgramFiles "Python$s\python.exe"
    }
    foreach ($a in $adaylar) { if (Test-Path $a) { return $a } }
    $k = Get-Command python -ErrorAction SilentlyContinue
    if ($k -and $k.Source -notmatch "WindowsApps") { return $k.Source }
    if (Komut-Var "py") {
        $eski = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $yol = (& py -3 -c "import sys; print(sys.executable)" 2>$null) | Select-Object -First 1
        $ErrorActionPreference = $eski
        if ($yol -and (Test-Path $yol)) { return $yol }
    }
    return $null
}

# ------------------------------------------------------------ 1. donanım
function Donanim-Incele {
    Baslik "1) Bilgisayarını inceliyorum"
    $cs  = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os  = Get-CimInstance Win32_OperatingSystem
    $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $disk = [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB)

    $gpular = @()
    if (Komut-Var "nvidia-smi") {
        foreach ($satir in (& nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits)) {
            $p = $satir.Split(",")
            $gpular += [pscustomobject]@{ Ad = $p[0].Trim(); VramGB = [math]::Round([double]$p[1].Trim() / 1024); Tur = "NVIDIA" }
        }
    }
    if ($gpular.Count -eq 0) {
        # Win32_VideoController 4 GB üstünü gösteremez; kayıt defterindeki qwMemorySize daha doğrudur
        $anahtar = "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        Get-ChildItem $anahtar -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $o = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($o.DriverDesc -and $o.'HardwareInformation.qwMemorySize') {
                $tur = "Diger"
                if ($o.DriverDesc -match "NVIDIA") { $tur = "NVIDIA" }
                elseif ($o.DriverDesc -match "AMD|Radeon") { $tur = "AMD" }
                elseif ($o.DriverDesc -match "Intel") { $tur = "Intel" }
                $gpular += [pscustomobject]@{ Ad = $o.DriverDesc; VramGB = [math]::Round([double]$o.'HardwareInformation.qwMemorySize' / 1GB); Tur = $tur }
            }
        }
    }
    $enIyi = $gpular | Where-Object { $_.Tur -in @("NVIDIA", "AMD") } | Sort-Object VramGB -Descending | Select-Object -First 1

    Bilgi "Windows      : $($os.Caption)"
    Bilgi "İşlemci      : $($cpu.Name.Trim()) ($($cpu.NumberOfCores) çekirdek)"
    Bilgi "RAM          : $ram GB"
    Bilgi "Boş disk     : $disk GB ($env:SystemDrive)"
    if ($gpular.Count -eq 0) { Bilgi "Ekran kartı  : bulunamadı" }
    foreach ($g in $gpular) { Bilgi "Ekran kartı  : $($g.Ad) – $($g.VramGB) GB" }

    $script:Donanim = [pscustomobject]@{ RamGB = $ram; DiskGB = $disk; Gpu = $enIyi }
    Oneri-Hesapla
    Oneri-Goster
}

function Oneri-Hesapla {
    $d = $script:Donanim
    $vram = 0
    if ($d.Gpu) { $vram = $d.Gpu.VramGB }
    $modeller = $Katalog.modeller
    # Ekran kartına sığarsa hızlı; sığmazsa RAM'de (CPU) yavaş çalışır
    function Sigar($m) {
        if ($vram -ge 4 -and ($m.boyut_gb + 1.5) -le $vram) { return "GPU" }   # +1.5 GB: bağlam (KV önbelleği)
        if (($m.boyut_gb * 1.3) -le ($d.RamGB * 0.6)) { return "CPU" }
        return $null
    }
    $gorsel = @($modeller | Where-Object { $_.tur -eq "gorsel" -and $_.tiklama -in @("iyi", "cok_iyi", "orta") } |
              ForEach-Object { $y = Sigar $_; if ($y) { $_ | Add-Member -NotePropertyName yer -NotePropertyValue $y -Force -PassThru } })
    $metin  = @($modeller | Where-Object { $_.tur -eq "metin" } |
              ForEach-Object { $y = Sigar $_; if ($y) { $_ | Add-Member -NotePropertyName yer -NotePropertyValue $y -Force -PassThru } })
    # Usta için: GPU'ya sığanlar arasında ekranda tıklaması en iyi olan, eşitse daha büyüğü, o da eşitse
    # katalogda önce gelen (daha yeni nesil). Hiçbiri GPU'ya sığmıyorsa işlemcide en hızlısı (en küçüğü).
    $sira = @{ "cok_iyi" = 0; "iyi" = 1; "orta" = 2 }
    $katalogSira = @{}; for ($i = 0; $i -lt $modeller.Count; $i++) { $katalogSira[$modeller[$i].tag] = $i }
    $gpuda = @($gorsel | Where-Object { $_.yer -eq "GPU" })
    if ($gpuda.Count -gt 0) {
        $usta = $gpuda | Sort-Object @{e = { $sira[$_.tiklama] } }, @{e = { $_.boyut_gb }; Descending = $true }, @{e = { $katalogSira[$_.tag] } } | Select-Object -First 1
    } else {
        $usta = $gorsel | Where-Object { $_.tiklama -ne "orta" -or $_.boyut_gb -lt 5 } | Sort-Object @{e = { $_.boyut_gb } }, @{e = { $katalogSira[$_.tag] } } | Select-Object -First 1
    }
    $sohbet = $metin | Sort-Object @{e = { if ($_.yer -eq "GPU") { 0 } else { 1 } } }, @{e = { $_.boyut_gb }; Descending = $true } | Select-Object -First 1
    $kademe = "Zayıf"
    if ($vram -ge 20) { $kademe = "Çok güçlü" } elseif ($vram -ge 12) { $kademe = "Güçlü" } elseif ($vram -ge 8) { $kademe = "Orta-iyi" } elseif ($d.RamGB -ge 16) { $kademe = "Orta (yalnızca işlemci)" }
    $script:Oneri = [pscustomobject]@{ Kademe = $kademe; Usta = $usta; Sohbet = $sohbet; Vram = $vram }
}

function Oneri-Goster {
    $o = $script:Oneri; $d = $script:Donanim
    Baslik "Öneriler"
    Bilgi "Bilgisayar sınıfı: $($o.Kademe)"
    Bilgi "Önerilen motor   : Ollama  (arka planda çalışır, Usta doğrudan bağlanır, çok kolay)"
    if ($o.Usta) {
        Bilgi "Usta için model  : $($o.Usta.tag)  (~$($o.Usta.boyut_gb) GB, $($o.Usta.yer) üzerinde)"
        Bilgi "                   $($o.Usta.not)"
    } else {
        Uyari "Bu bilgisayara ekranı kullanabilecek bir görsel model sığmıyor. Usta için Claude (internet) kullan."
    }
    if ($o.Sohbet) { Bilgi "Sohbet/yazı için : $($o.Sohbet.tag)  (~$($o.Sohbet.boyut_gb) GB)" }
    if ($o.Usta -and $o.Usta.yer -eq "CPU") {
        Uyari "Model ekran kartına sığmadığı için işlemcide çalışacak: her adım 10-60 sn sürebilir."
    }
    if ($d.Gpu -and $d.Gpu.Tur -eq "AMD") {
        Uyari "AMD ekran kartlarında Ollama yalnızca desteklenen modellerde GPU kullanır (ollama.com/blog/amd-preview)."
    }
    if ($d.DiskGB -lt 40) { Uyari "Boş disk az ($($d.DiskGB) GB). Modeller için en az 40 GB boş yer önerilir." }
    Bilgi ""
    Bilgi "Not: Yerel modeller Claude kadar başarılı değildir; özellikle ekranda doğru yere tıklamada."
    Bilgi "     En iyi düzen: internet varken Claude ekranı kullanır, kontrol ve hafıza yerel modelde"
    Bilgi "     (ucuz); internet yoksa Usta otomatik olarak tamamen yerel modele geçer."
}

# ------------------------------------------------------- 2. karşılaştırma
function Araclari-Karsilastir {
    Baslik "2) Yerel yapay zeka araçları – neden, artılar, eksiler"
    foreach ($a in $Katalog.araclar) {
        $isaret = ""; if ($a.onerilen) { $isaret = "  ← ÖNERİLEN" }
        Write-Host ""
        Write-Host "  ■ $($a.ad)$isaret" -ForegroundColor Cyan
        Bilgi "  Neden: $($a.neden)"
        foreach ($x in $a.artilar) { Write-Host "    + $x" -ForegroundColor Green }
        foreach ($x in $a.eksiler) { Write-Host "    - $x" -ForegroundColor Yellow }
    }
    Write-Host ""
    if (Evet "Ayrıntılı rehberi (rehber.html) tarayıcıda açayım mı?" "H") { Start-Process (Join-Path $Klasor "rehber.html") }
}

# -------------------------------------------------------------- 3. Ollama
function Ollama-Kur {
    Baslik "3) Ollama kurulumu"
    if (Komut-Var "ollama") { Iyi "Ollama zaten kurulu: $(& ollama --version)" }
    else {
        if (-not (Internet-Var)) { Hata "Kurulum için bir kez internet gerekli. Sonrasında her şey çevrimdışı çalışır."; return }
        Winget-Kur "Ollama.Ollama" "Ollama" "https://ollama.com/download/windows" | Out-Null
        if (-not (Komut-Var "ollama")) { Hata "Ollama bulunamadı. Kurulumu tamamladıysan bu pencereyi kapatıp BASLAT.bat'ı yeniden aç."; return }
    }

    # Bağlam penceresi: Ollama varsayılanı 4096 jeton; ekran görüntüleri için yetersiz
    $mevcut = [Environment]::GetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "User")
    $oneri = 16384
    if ($script:Oneri -and $script:Oneri.Vram -ge 16) { $oneri = 32768 }
    if (-not $mevcut) {
        Bilgi "Ollama'nın bağlam penceresini $oneri jetona çıkarıyorum (varsayılan 4096; ekran görüntüleri için az)."
        [Environment]::SetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "$oneri", "User")
        $env:OLLAMA_CONTEXT_LENGTH = "$oneri"
        Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
    } else { Bilgi "OLLAMA_CONTEXT_LENGTH zaten ayarlı: $mevcut" }

    if (Ollama-Baslat) { Iyi "Ollama çalışıyor ($OllamaApi)." } else { Uyari "Ollama başlatılamadı. Başlat menüsünden 'Ollama'yı açıp tekrar dene." }
}

# ----------------------------------------------------------- 4. model
function Model-Indir {
    Baslik "4) Model indirme"
    if (-not (Komut-Var "ollama")) { Hata "Önce Ollama'yı kur (adım 3)."; return }
    if (-not (Ollama-Baslat)) { Hata "Ollama çalışmıyor."; return }
    if (-not $script:Oneri) { Donanim-Incele }

    $liste = @($Katalog.modeller)
    for ($i = 0; $i -lt $liste.Count; $i++) {
        $m = $liste[$i]; $isaret = ""
        if ($script:Oneri.Usta -and $m.tag -eq $script:Oneri.Usta.tag) { $isaret = "  ← Usta için önerilen" }
        elseif ($script:Oneri.Sohbet -and $m.tag -eq $script:Oneri.Sohbet.tag) { $isaret = "  ← sohbet için önerilen" }
        $tur = "metin "; if ($m.tur -eq "gorsel") { $tur = "görsel" }
        Write-Host ("  {0,2}) {1,-22} {2,5} GB  {3}  {4}{5}" -f ($i + 1), $m.tag, $m.boyut_gb, $tur, $m.not, $isaret)
    }
    Bilgi ""
    Bilgi "Listede olmayan bir modeli de yazabilirsin (ollama.com/library'deki adıyla, ör. qwen3-vl:8b)."
    $vars = ""; if ($script:Oneri.Usta) { $vars = $script:Oneri.Usta.tag }
    $secim = Read-Host "  Numara(lar) veya model adı, virgülle ayır [$vars]"
    if ([string]::IsNullOrWhiteSpace($secim)) { $secim = $vars }
    $script:IndirilenModeller = @()
    foreach ($s in $secim.Split(",")) {
        $s = $s.Trim(); if (-not $s) { continue }
        $tag = $s
        if ($s -match '^\d+$' -and [int]$s -ge 1 -and [int]$s -le $liste.Count) { $tag = $liste[[int]$s - 1].tag }
        $k = $liste | Where-Object { $_.tag -eq $tag } | Select-Object -First 1
        $boyut = "?"; if ($k) { $boyut = "$($k.boyut_gb)" }
        if (-not (Evet "$tag indirilecek (~$boyut GB). Onaylıyor musun?")) { continue }
        Bilgi "İndiriliyor: $tag (büyük modeller uzun sürebilir; kesilirse tekrar çalıştır, kaldığı yerden devam eder)"
        & ollama pull $tag
        if ($LASTEXITCODE -eq 0) { Iyi "$tag hazır."; $script:IndirilenModeller += $tag } else { Hata "$tag indirilemedi." }
    }
}

# ------------------------------------------------------------- 5. test
function Test-Et {
    Baslik "5) Kurulum testi"
    if (-not (Ollama-Baslat)) { Hata "Ollama çalışmıyor."; return }
    Iyi "Ollama sunucusu yanıt veriyor."
    $yuklu = @()
    try { $yuklu = @((Invoke-RestMethod "$OllamaApi/api/tags").models | ForEach-Object { $_.name }) } catch {}
    if ($yuklu.Count -eq 0) { Uyari "Hiç model yok. Adım 4 ile indir."; return }
    Bilgi "Yüklü modeller: $($yuklu -join ', ')"
    $model = $yuklu[0]
    if ($yuklu.Count -gt 1) { $g = Read-Host "  Hangisini test edeyim? [$model]"; if ($g) { $model = $g.Trim() } }

    # Usta'nın kullandığı OpenAI uyumlu uç nokta
    try {
        $govde = @{ model = $model; stream = $false; max_tokens = 100
                    messages = @(@{ role = "user"; content = "Tek cümleyle Türkçe merhaba de." }) } | ConvertTo-Json -Depth 5
        $sure = Measure-Command {
            $y = Invoke-RestMethod -Uri "$OllamaApi/v1/chat/completions" -Method Post -ContentType "application/json; charset=utf-8" `
                 -Body ([System.Text.Encoding]::UTF8.GetBytes($govde)) -TimeoutSec 600
        }
        Iyi "OpenAI uyumlu API çalışıyor ($([math]::Round($sure.TotalSeconds,1)) sn): $($y.choices[0].message.content)"
    } catch {
        Hata "OpenAI uyumlu API ($OllamaApi/v1) yanıt vermedi: $($_.Exception.Message)"
        Uyari "Ollama'yı güncelle (winget upgrade Ollama.Ollama) veya Usta ayarlarında LM Studio'yu dene."
        return
    }
    $ps = ""
    try { $ps = (& ollama ps) -join "`n" } catch {}
    if ($ps) { Bilgi "Çalışan model (PROCESSOR sütunu GPU/CPU kullanımını gösterir):"; Write-Host $ps }
    Iyi "Test tamam. Bu noktadan sonra internet olmadan da kullanabilirsin."
}

# ----------------------------------------------------- 6. diğer araçlar
function Diger-Araclar {
    Baslik "6) Diğer araçlar (isteğe bağlı)"
    $digerleri = @($Katalog.araclar | Where-Object { -not $_.onerilen })
    for ($i = 0; $i -lt $digerleri.Count; $i++) { Write-Host ("  {0}) {1} – {2}" -f ($i + 1), $digerleri[$i].ad, $digerleri[$i].neden) }
    $s = Read-Host "  Kurmak istediğin numara (boş = geri)"
    if (-not ($s -match '^\d+$') -or [int]$s -lt 1 -or [int]$s -gt $digerleri.Count) { return }
    $a = $digerleri[[int]$s - 1]
    if ($a.winget) { Winget-Kur $a.winget $a.ad $a.indirme | Out-Null }
    else { Bilgi "$($a.ad) için resmi sayfayı açıyorum."; Start-Process $a.indirme }
    if ($a.api) { Bilgi "Usta'ya bağlamak için Ayarlar > Yerel sunucu adresi: $($a.api)" }
    if ($a.ad -eq "LM Studio") { Uyari "LM Studio'da modeli yükleyip Developer sekmesinden sunucuyu başlatmayı unutma." }
}

# --------------------------------------------------------- 7. Usta
function Usta-Kur {
    Baslik "7) Usta'yı kur ve yerel zekaya bağla"
    $ustaKlasor = Join-Path (Split-Path $Klasor -Parent) "usta"
    if (-not (Test-Path (Join-Path $ustaKlasor "usta.py"))) {
        Uyari "Usta klasörü bulunamadı ($ustaKlasor)."
        if (-not (Komut-Var "git")) { Winget-Kur "Git.Git" "Git" "https://git-scm.com/download/win" | Out-Null }
        $hedef = Join-Path $HOME "UstaDepo"
        Bilgi "Depoyu $hedef klasörüne indiriyorum (GitHub girişi istenebilir)…"
        & git clone -b claude/gallant-faraday-uonps7 https://github.com/volkandoyran/gstack-artifacts-volka $hedef
        $ustaKlasor = Join-Path $hedef "usta"
        if (-not (Test-Path (Join-Path $ustaKlasor "usta.py"))) { Hata "Usta indirilemedi."; return }
    }
    Iyi "Usta klasörü: $ustaKlasor"

    $python = Python-Bul
    if (-not $python) {
        Winget-Kur "Python.Python.3.12" "Python 3.12" "https://www.python.org/downloads/" | Out-Null
        $python = Python-Bul
    }
    if (-not $python) { Hata "Python bulunamadı. python.org'dan kurup ('Add to PATH' işaretli) tekrar dene."; return }
    Iyi "Python: $python"
    $venv = Join-Path $ustaKlasor ".venv"
    if (-not (Test-Path $venv)) { Bilgi "Python ortamı hazırlanıyor…"; & $python -m venv $venv }
    & (Join-Path $venv "Scripts\pip.exe") install -q -r (Join-Path $ustaKlasor "requirements.txt")
    if ($LASTEXITCODE -ne 0) { Hata "Paketler kurulamadı."; return }
    Iyi "Usta paketleri kuruldu."

    # Yerel model seçimi
    $yuklu = @()
    try { $yuklu = @((Invoke-RestMethod "$OllamaApi/api/tags").models | ForEach-Object { $_.name }) } catch {}
    $model = ""
    if ($script:Oneri -and $script:Oneri.Usta -and ($yuklu -contains $script:Oneri.Usta.tag)) { $model = $script:Oneri.Usta.tag }
    elseif ($yuklu.Count -gt 0) { $model = $yuklu[0] }
    if ($yuklu.Count -gt 0) { Bilgi "Yüklü modeller: $($yuklu -join ', ')" }
    $g = Read-Host "  Usta hangi yerel modeli kullansın? [$model]"; if ($g) { $model = $g.Trim() }
    $kayit = $Katalog.modeller | Where-Object { $_.tag -eq $model } | Select-Object -First 1
    $koord = "0-1000"
    if ($kayit -and $kayit.koordinat) { $koord = $kayit.koordinat } elseif ($model -match "qwen2\.5") { $koord = "piksel" }

    $ayarYolu = Join-Path $ustaKlasor "ayarlar.json"
    $ayar = @{}
    if (Test-Path $ayarYolu) {
        $eski = Get-Content -Raw -Encoding UTF8 $ayarYolu | ConvertFrom-Json
        foreach ($p in $eski.PSObject.Properties) { $ayar[$p.Name] = $p.Value }
    }
    $ayar["yerel_url"] = "$OllamaApi/v1"
    $ayar["yerel_model"] = $model
    $ayar["yerel_koordinat"] = $koord

    Bilgi ""
    Bilgi "Claude API anahtarın varsa: Claude ekranı kullanır (çok daha başarılı), kontrol ve hafıza"
    Bilgi "yerel modelde yapılır (ucuz). İnternet kesilirse Usta otomatik olarak yerel modele geçer."
    if (Evet "Claude API anahtarın var mı?" "H") {
        $anahtar = Read-Host "  API anahtarı (boş bırakırsan Usta ilk açılışta sorar)"
        if ($anahtar) { $ayar["api_anahtari"] = $anahtar.Trim() }
        $ayar["eylem_saglayici"] = "claude"; $ayar["dogrulama_saglayici"] = "yerel"; $ayar["hafiza_saglayici"] = "yerel"
        $ayar["cevrimdisi"] = $false
    } else {
        $ayar["eylem_saglayici"] = "yerel"; $ayar["dogrulama_saglayici"] = "yerel"; $ayar["hafiza_saglayici"] = "yerel"
        $ayar["cevrimdisi"] = $true
    }
    $json = $ayar | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ayarYolu, $json, (New-Object System.Text.UTF8Encoding $false))
    Iyi "Usta ayarları yazıldı: model=$model, koordinat=$koord"

    if (Evet "Masaüstüne 'Usta' kısayolu oluşturayım mı?") {
        $ws = New-Object -ComObject WScript.Shell
        $k = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "Usta.lnk"))
        $k.TargetPath = Join-Path $ustaKlasor "baslat.bat"
        $k.WorkingDirectory = $ustaKlasor
        $k.Save()
        Iyi "Kısayol oluşturuldu."
    }
    if (Evet "Usta'yı şimdi açayım mı?") { Start-Process (Join-Path $ustaKlasor "baslat.bat") -WorkingDirectory $ustaKlasor }
}

# ------------------------------------------------------ 8. gelişmiş
function Gelismis {
    Baslik "8) Gelişmiş ayarlar"
    Bilgi "1) Modelleri başka bir diske taşı (OLLAMA_MODELS) – C: doluysa"
    Bilgi "2) Bağlam penceresini değiştir (OLLAMA_CONTEXT_LENGTH)"
    Bilgi "3) Ollama'yı ağdaki diğer cihazlara aç (OLLAMA_HOST=0.0.0.0) – dikkat: güvenlik"
    Bilgi "4) Ollama'yı güncelle"
    $s = Read-Host "  Seçim (boş = geri)"
    switch ($s) {
        "1" {
            $yol = Read-Host "  Yeni klasör (ör. D:\OllamaModelleri)"
            if ($yol) { New-Item -ItemType Directory -Force -Path $yol | Out-Null
                [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $yol, "User")
                Iyi "Ayarlandı. Ollama'yı yeniden başlat; eski modelleri $HOME\.ollama\models klasöründen taşıyabilirsin." }
        }
        "2" {
            $n = Read-Host "  Jeton sayısı (8192 / 16384 / 32768)"
            if ($n -match '^\d+$') { [Environment]::SetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", $n, "User"); Iyi "Ayarlandı. Ollama'yı yeniden başlat." }
        }
        "3" {
            if (Evet "Ollama'ya ağdaki herkes erişebilir. Emin misin?" "H") {
                [Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "User"); Iyi "Ayarlandı. Ollama'yı yeniden başlat." }
        }
        "4" { if (Komut-Var "winget") { & winget upgrade --id Ollama.Ollama -e | Out-Host } else { Start-Process "https://ollama.com/download/windows" } }
    }
}

# ------------------------------------------------------- P. yalnızca plan
function Plan-Goster {
    Baslik "P) Kurulum planı – hiçbir şey kurulmaz, yalnızca gösterilir"
    if (-not $script:Oneri) { Donanim-Incele }
    $o = $script:Oneri
    $adim = 1
    $durum = "kurulu değil → kurulacak"; if (Komut-Var "ollama") { $durum = "zaten kurulu" }
    Bilgi "$adim) Ollama ($durum). Kaynak: winget 'Ollama.Ollama' veya ollama.com"; $adim++
    Bilgi "$adim) OLLAMA_CONTEXT_LENGTH ortam değişkeni 16384 (güçlü kartta 32768) yapılır"; $adim++
    if ($o.Usta) { Bilgi "$adim) Model indirilir: $($o.Usta.tag) (~$($o.Usta.boyut_gb) GB)"; $adim++ }
    Bilgi "$adim) Test: Ollama API'sine kısa bir 'merhaba' isteği gönderilir"; $adim++
    $py = "bulunamadı → kurulacak (winget 'Python.Python.3.12')"; $bulunan = Python-Bul; if ($bulunan) { $py = "var: $bulunan" }
    Bilgi "$adim) Python $py"; $adim++
    Bilgi "$adim) Usta'nın Python paketleri .venv klasörüne kurulur, ayarlar.json yerel modele bağlanır"; $adim++
    Bilgi "$adim) İsteğe bağlı: masaüstü kısayolu"
    Bilgi ""
    Bilgi "Her adımda tek tek onay istenir; istemediğin adımı atlayabilirsin."
    $toplam = 1; if ($o.Usta) { $toplam += $o.Usta.boyut_gb }
    Bilgi "Tahmini toplam indirme: ~$([math]::Round($toplam)) GB. Gereken boş disk: ~$([math]::Round($toplam * 1.5 + 5)) GB"
}

# ---------------------------------------------------------------- ana menü
function Hepsi {
    Plan-Goster
    if (-not (Evet "Bu plana göre başlayalım mı?")) { return }
    Donanim-Incele; Bekle
    Ollama-Kur; Bekle
    Model-Indir; Bekle
    Test-Et; Bekle
    Usta-Kur
}

while ($true) {
    Clear-Host
    Baslik "Yerel Zeka Kurulum Sihirbazı – çevrimdışı çalışan yapay zeka"
    Bilgi " P) Sadece planı göster (hiçbir şey kurmaz)"
    Bilgi " 9) HEPSİNİ SIRAYLA YAP (her adımda onay ister)"
    Bilgi ""
    Bilgi " 1) Bilgisayarımı incele ve öneri al"
    Bilgi " 2) Araçları karşılaştır (neden / artılar / eksiler)"
    Bilgi " 3) Ollama'yı kur"
    Bilgi " 4) Model indir"
    Bilgi " 5) Kurulumu test et"
    Bilgi " 6) Diğer araçları kur (LM Studio, Jan, GPT4All, llama.cpp, Open WebUI)"
    Bilgi " 7) Usta'yı kur ve yerel zekaya bağla"
    Bilgi " 8) Gelişmiş ayarlar"
    Bilgi " 0) Çıkış"
    $secim = Read-Host "`n  Seçimin"
    try {
        switch ($secim) {
            "1" { Donanim-Incele }
            "2" { Araclari-Karsilastir }
            "3" { Ollama-Kur }
            "4" { Model-Indir }
            "5" { Test-Et }
            "6" { Diger-Araclar }
            "7" { Usta-Kur }
            "8" { Gelismis }
            "9" { Hepsi }
            { $_ -in @("P", "p") } { Plan-Goster }
            "0" { try { Stop-Transcript | Out-Null } catch {}; exit 0 }
            default { }
        }
    } catch {
        Hata "Beklenmeyen hata: $($_.Exception.Message)"
        Bilgi "Ayrıntılar: $Gunluk"
    }
    Bekle
}
