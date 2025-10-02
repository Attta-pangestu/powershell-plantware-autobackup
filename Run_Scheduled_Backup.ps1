# Script untuk menjalankan scheduled backup
# This script is called by Windows Task Scheduler

Write-Host "=== Running Scheduled Backup ===" -ForegroundColor Cyan
Write-Host "Starting scheduled backup process..." -ForegroundColor Yellow

# Set working directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

Write-Host "Working directory: $(Get-Location)" -ForegroundColor Green

# Import functions from main script
try {
    . .\SimpleBackupGUI.ps1

    # Run scheduled backup
    Run-ScheduledBackup

    Write-Host "=== Scheduled Backup Completed ===" -ForegroundColor Green
}
catch {
    Write-Host "Error running scheduled backup: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}