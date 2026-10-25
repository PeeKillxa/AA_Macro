[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  AA MACRO STUDIO - PUSH UPDATE TO GITHUB" -ForegroundColor Yellow
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

Set-Location $PSScriptRoot

Write-Host "[1/3] Adding files..." -ForegroundColor Gray
git add main_v2.lua main.lua loader.lua tracker.lua .gitignore README.md push_update.bat push_update.ps1

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[2/3] Commit: $timestamp" -ForegroundColor Gray
git commit -m "Auto Update: $timestamp"

Write-Host "[3/3] Pushing to GitHub (origin main)..." -ForegroundColor Cyan
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "[4/4] Purging jsDelivr CDN Cache..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "https://purge.jsdelivr.net/gh/PeeKillxa/AA_Macro@main/tracker.lua" -Method Get | Out-Null
        Invoke-RestMethod -Uri "https://purge.jsdelivr.net/gh/PeeKillxa/AA_Macro@main/main_v2.lua" -Method Get | Out-Null
        Invoke-RestMethod -Uri "https://purge.jsdelivr.net/gh/PeeKillxa/AA_Macro@main/loader.lua" -Method Get | Out-Null
        Write-Host "[CDN] Purged jsDelivr cache successfully!" -ForegroundColor Green
    } catch {
        Write-Host "[CDN] Warning: Could not purge jsDelivr cache automatically." -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "[SUCCESS] Updated to GitHub successfully!" -ForegroundColor Green
    Write-Host "Other machines running loader.lua / tracker.lua will now receive the latest version." -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "[INFO] Failed to push to GitHub." -ForegroundColor Yellow
    Write-Host "1. Make sure you created a Public repository named 'AA_Macro' at https://github.com/new" -ForegroundColor White
    Write-Host "2. If a GitHub Login prompt appears, please sign in via browser to authorize git." -ForegroundColor White
}
Write-Host ""
