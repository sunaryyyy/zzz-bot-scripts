$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   ZZZ Signal URL Extractor by Sunary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$possiblePaths = @(
    "$env:APPDATA\..\LocalLow\miHoYo\ZenlessZoneZero\webCaches",
    "$env:APPDATA\..\LocalLow\miHoYo\ZenlessZoneZero_Oversea\webCaches",
    "$env:LOCALAPPDATA\..\LocalLow\miHoYo\ZenlessZoneZero\webCaches",
    "$env:LOCALAPPDATA\..\LocalLow\miHoYo\ZenlessZoneZero_Oversea\webCaches"
)

$cacheFile = $null

foreach ($basePath in $possiblePaths) {
    $expanded = [System.Environment]::ExpandEnvironmentVariables($basePath)
    if (Test-Path $expanded) {
        $found = Get-ChildItem -Path $expanded -Recurse -Filter "data_2" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
        if ($found) {
            $cacheFile = $found.FullName
            break
        }
    }
}

if (-not $cacheFile) {
    Write-Host "[ERROR] Cache file not found." -ForegroundColor Red
    Write-Host "-> Open ZZZ, go to Signal Search > Signal Details, wait for the page to load, then run this script again." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Cache file found: $cacheFile" -ForegroundColor Green

$bytes = [System.IO.File]::ReadAllBytes($cacheFile)
$text  = [System.Text.Encoding]::UTF8.GetString($bytes)

$pattern = 'https://[a-zA-Z0-9\-\.]+/[a-zA-Z0-9_/\-]*[?&]authkey=[^\s"<>]+'
$match   = [regex]::Match($text, $pattern)

if (-not $match.Success) {
    Write-Host ""
    Write-Host "[ERROR] No URL with authkey found in cache." -ForegroundColor Red
    Write-Host "-> Make sure you opened Signal Details in-game and the page fully loaded." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$url = $match.Value

Write-Host ""
Write-Host "SUCCESS - URL found!" -ForegroundColor Green
Write-Host ""
Write-Host "======= COPY THIS URL =======" -ForegroundColor Yellow
Write-Host ""
Write-Host $url
Write-Host ""
Write-Host "=============================" -ForegroundColor Yellow

try {
    $url | Set-Clipboard
    Write-Host ""
    Write-Host "URL automatically copied to clipboard!" -ForegroundColor Green
} catch {
    Write-Host "(Auto-copy failed, please copy the URL above manually)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "WARNING: This URL expires after 24 hours." -ForegroundColor Yellow
Write-Host "WARNING: Do NOT share this URL with anyone." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"
