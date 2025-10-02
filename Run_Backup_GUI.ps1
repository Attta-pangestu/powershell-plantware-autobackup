# Simple launcher untuk SimpleBackupGUI.ps1

# Set execution policy untuk session ini
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Navigasi ke script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

# Jalankan GUI
try {
    Write-Host "Starting Simple Backup GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
catch {
    Write-Host "Error starting application: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}