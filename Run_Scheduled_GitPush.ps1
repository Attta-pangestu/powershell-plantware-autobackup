# Script untuk menjalankan scheduled git push
# This script is called by Windows Task Scheduler

Write-Host "=== Running Scheduled Git Push ===" -ForegroundColor Cyan
Write-Host "Starting scheduled git push process..." -ForegroundColor Yellow

# Set working directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

Write-Host "Working directory: $(Get-Location)" -ForegroundColor Green

# Import functions from main git script
try {
    . .\Push-ToGit.ps1

    Write-Host "=== Scheduled Git Push Completed ===" -ForegroundColor Green
}
catch {
    Write-Host "Error running scheduled git push: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}