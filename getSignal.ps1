
$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   ZZZ Signal URL Extractor" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Dossiers possibles pour Player.log (pour en deduire le chemin du jeu)
$localLowBase = [System.IO.Path]::Combine($env:APPDATA, "..", "LocalLow", "miHoYo")
$playerLogPaths = @(
    (Join-Path $localLowBase "ZenlessZoneZero\Player.log"),
    (Join-Path $localLowBase "ZenlessZoneZero\Player-prev.log"),
    (Join-Path $localLowBase "ZenlessZoneZero_Oversea\Player.log"),
    (Join-Path $localLowBase "ZenlessZoneZero_Oversea\Player-prev.log"),
    (Join-Path $localLowBase "$([char]0x7edd)$([char]0x533a)$([char]0x96f6)\Player.log"),
    (Join-Path $localLowBase "$([char]0x7edd)$([char]0x533a)$([char]0x96f6)\Player-prev.log")
)

function Get-GamePathFromLog {
    foreach ($logPath in $playerLogPaths) {
        $full = [System.IO.Path]::GetFullPath($logPath)
        if (-not (Test-Path $full)) { continue }
        try {
            # Ligne type: [Subsystems] Discovering subsystems at path C:\...\Zenless Zone Zero\UnitySubsystems
            $lines = Get-Content $full -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -match '\[Subsystems\].*?path\s+(.+?)UnitySubsystems') {
                    $path = $matches[1].Trim().TrimEnd('\')
                    if (Test-Path $path) {
                        Write-Host "[INFO] Chemin jeu depuis log: $path" -ForegroundColor DarkGray
                        return $path
                    }
                }
            }
        } catch {}
    }
    return $null
}

function Get-CacheData2Path {
    param([string]$gamePath)
    # Structure 1: GamePath\webCaches\2.0.1.0\Cache\Cache_Data\data_2
    $webCaches = Join-Path $gamePath "webCaches"
    if (Test-Path $webCaches) {
        $versionDirs = Get-ChildItem -Path $webCaches -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [Version]$_.Name } -Descending
        foreach ($v in $versionDirs) {
            $data2 = Join-Path $v.FullName "Cache\Cache_Data\data_2"
            if (Test-Path $data2) { return $data2 }
        }
        # Structure 2: GamePath\webCaches\Cache\Cache_Data\data_2
        $data2 = Join-Path $webCaches "Cache\Cache_Data\data_2"
        if (Test-Path $data2) { return $data2 }
    }
    return $null
}

function Find-Data2InLocalLow {
    $bases = @(
        [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA "..\LocalLow\miHoYo\ZenlessZoneZero")),
        [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA "..\LocalLow\miHoYo\ZenlessZoneZero_Oversea")),
        [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "..\LocalLow\miHoYo\ZenlessZoneZero")),
        [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "..\LocalLow\miHoYo\ZenlessZoneZero_Oversea"))
    )
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        $found = Get-ChildItem -Path $base -Recurse -Filter "data_2" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    # HoYoPlay / autre
    $hoyo = Join-Path $env:PROGRAMFILES "HoYoPlay\games"
    if (Test-Path $hoyo) {
        $found = Get-ChildItem -Path $hoyo -Recurse -Filter "data_2" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

# 1) Chemin du jeu depuis Player.log -> cache dans webCaches du jeu
$gamePath = Get-GamePathFromLog
$cacheFile = $null
if ($gamePath) {
    $cacheFile = Get-CacheData2Path -gamePath $gamePath
}

# 2) Sinon recherche data_2 sous LocalLow / HoYoPlay
if (-not $cacheFile) {
    Write-Host "[INFO] Recherche du cache dans AppData / HoYoPlay..." -ForegroundColor DarkGray
    $cacheFile = Find-Data2InLocalLow
}

if (-not $cacheFile) {
    Write-Host "[ERREUR] Fichier cache introuvable." -ForegroundColor Red
    Write-Host ""
    Write-Host "Faire ceci :" -ForegroundColor Yellow
    Write-Host "  1. Lance ZZZ et ouvre Signal Search > Signal Details (attends le chargement)."
    Write-Host "  2. Relance ce script."
    Write-Host ""
    Write-Host "Si ca echoue encore, indique le chemin du dossier d'installation du jeu" -ForegroundColor Yellow
    Write-Host "(ex: C:\Program Files\Zenless Zone Zero) pour qu'on cherche le cache dedans." -ForegroundColor Yellow
    $manualPath = Read-Host "Chemin du jeu (ou Entree pour quitter)"
    if ($manualPath) {
        $gamePath = $manualPath.Trim().Trim('"')
        $cacheFile = Get-CacheData2Path -gamePath $gamePath
    }
    if (-not $cacheFile) {
        Write-Host "Toujours pas de cache trouve. Au revoir." -ForegroundColor Red
        Read-Host "Appuie sur Entree pour quitter"
        exit 1
    }
}

Write-Host "Fichier cache : $cacheFile" -ForegroundColor Green

# Lire le cache : copie vers temp, ou lecture en partage si le jeu a le fichier ouvert
$bytes = $null
$tempPath = [System.IO.Path]::GetTempFileName()
try {
    Copy-Item -LiteralPath $cacheFile -Destination $tempPath -Force -ErrorAction Stop
    $bytes = [System.IO.File]::ReadAllBytes($tempPath)
} catch {
    # Fichier verrouillé par le jeu : ouvrir en lecture partagée (FileShare.Read)
    $fs = [System.IO.File]::Open($cacheFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $bytes = New-Object byte[] $fs.Length
        [void]$fs.Read($bytes, 0, $bytes.Length)
    } finally { $fs.Close() }
} finally {
    if (Test-Path $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
}
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

# Extraire TOUTES les URLs getGachaLog (le cache peut en contenir plusieurs, les plus recentes a la fin)
# Methode 1: comme getZZZHistoryURL.ps1 - split par 1/0/, parcourir de la fin vers le debut
$candidates = [System.Collections.Generic.List[string]]::new()
$chunks = $text -split '1/0/'
for ($i = $chunks.Count - 1; $i -ge 0; $i--) {
    $chunk = $chunks[$i]
    $line = ($chunk -split "\0")[0]
    if ($line -and $line.Trim().StartsWith('http') -and $line.Contains('getGachaLog') -and $line.Contains('authkey=')) {
        $u = $line.Trim() -replace '[\x00-\x1f]+$', ''
        if ($u.Length -gt 80 -and $candidates -notcontains $u) { $candidates.Add($u) }
    }
}

# Methode 2: regex sur tout le fichier (toutes les occurrences)
if ($candidates.Count -eq 0) {
    $pattern = 'https://[a-zA-Z0-9\-\.]+/[a-zA-Z0-9_/\-]*getGachaLog[^"\s<>]*authkey=[^\s"<>]+'
    foreach ($m in [regex]::Matches($text, $pattern)) {
        $u = $m.Value -replace '[\x00-\x1f]+$', ''
        if ($u.Length -gt 80 -and $candidates -notcontains $u) { $candidates.Add($u) }
    }
}
if ($candidates.Count -eq 0) {
    $pattern = 'https://[a-zA-Z0-9\-\.]+/[a-zA-Z0-9_/\-]*[?&]authkey=[^\s"<>]+'
    foreach ($m in [regex]::Matches($text, $pattern)) {
        $u = $m.Value -replace '[\x00-\x1f]+$', ''
        if ($u.Length -gt 80 -and $u.Contains('gacha') -and $candidates -notcontains $u) { $candidates.Add($u) }
    }
}

# Trier par timestamp= (le plus recent en premier) si present
$candidates = $candidates | Sort-Object -Descending {
    if ($_ -match 'timestamp=(\d+)') { [long]$matches[1] } else { 0 }
}

# Valider l'URL par un appel API (retcode=0 = authkey valide) - comme getZZZHistoryURL.ps1
$url = $null
foreach ($cand in $candidates) {
    try {
        $testUrl = $cand.Trim()
        if (-not $testUrl.Contains('&end_id=')) { $testUrl += '&end_id=0' }
        $r = Invoke-RestMethod -Uri $testUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
        if ($r.retcode -eq 0) {
            $url = $cand.Trim() -replace '[\x00-\x1f]+$', ''
            Write-Host "[INFO] URL validee par l'API (retcode=0)." -ForegroundColor DarkGray
            break
        }
        Write-Host "[INFO] URL expiree (retcode $($r.retcode)), essai suivant..." -ForegroundColor DarkGray
    } catch {
        Write-Host "[INFO] URL invalide ou erreur reseau, essai suivant..." -ForegroundColor DarkGray
    }
}

# Fallback: si aucune validee, prendre la plus recente (dernier candidat = dernier timestamp)
if (-not $url -and $candidates.Count -gt 0) {
    $url = ($candidates[0] -replace '[\x00-\x1f]+$', '').Trim()
    Write-Host "[ATTENTION] Aucune URL validee par l'API. Utilisation de la plus recente du cache (peut etre expiree)." -ForegroundColor Yellow
}

if (-not $url -or $url.Length -lt 50) {
    Write-Host ""
    Write-Host "[ERREUR] Aucune URL avec authkey dans le cache." -ForegroundColor Red
    Write-Host "-> Ouvre le jeu, va dans Signal Search > Signal Details, attends que la page charge, puis relance." -ForegroundColor Yellow
    Read-Host "Appuie sur Entree pour quitter"
    exit 1
}

Write-Host ""
Write-Host "URL trouvee !" -ForegroundColor Green
Write-Host ""
Write-Host "=== COPIE CETTE URL (pour /signal-log) ===" -ForegroundColor Yellow
Write-Host ""
Write-Host $url
Write-Host ""

try {
    $url | Set-Clipboard
    Write-Host "URL copiee dans le presse-papier." -ForegroundColor Green
} catch {
    Write-Host "(Copie auto impossible, copie a la main.)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "ATTENTION : URL valide 24 h. Ne partage pas cette URL." -ForegroundColor Yellow
Write-Host ""
Read-Host "Appuie sur Entree pour quitter"
