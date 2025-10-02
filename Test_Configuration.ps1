# Test script untuk memverifikasi konfigurasi GUI Backup

Write-Host "=== Test Konfigurasi GUI Backup ===" -ForegroundColor Cyan
Write-Host "Memeriksa konfigurasi dan token..." -ForegroundColor Yellow

# Test path configuration
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

Write-Host "Current directory: $(Get-Location)" -ForegroundColor Green

# Test config file
$configFile = "config\auto_backup_config.json"
if (Test-Path $configFile) {
    Write-Host "✅ Config file found: $configFile" -ForegroundColor Green

    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        Write-Host "✅ Config file is valid JSON" -ForegroundColor Green

        # Display Google Drive configuration
        Write-Host "`n--- Google Drive Configuration ---" -ForegroundColor Cyan
        Write-Host "Client ID: $($config.google_drive.client_id)" -ForegroundColor White
        Write-Host "Client Secret: $($config.google_drive.client_secret.Substring(0, 10))..." -ForegroundColor White
        Write-Host "Token File: $($config.google_drive.token_file)" -ForegroundColor White

        # Display backup items
        Write-Host "`n--- Backup Items ($($config.backup_items.Count) items) ---" -ForegroundColor Cyan
        foreach ($item in $config.backup_items) {
            Write-Host "  - $($item.Name): $($item.SourcePath)" -ForegroundColor White
            Write-Host "    Type: $(if ($item.IsFolder) { 'Folder' } else { 'File' })" -ForegroundColor Gray
            Write-Host "    Status: $(if ($item.Enabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor Gray
            Write-Host "    Last Backup: $($item.LastBackup)" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Host "❌ Config file is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Config file not found: $configFile" -ForegroundColor Red
}

# Test token file
$tokenFile = "config\token.json"
if (Test-Path $tokenFile) {
    Write-Host "✅ Token file found: $tokenFile" -ForegroundColor Green

    try {
        $tokenData = Get-Content $tokenFile -Raw | ConvertFrom-Json
        Write-Host "✅ Token file is valid JSON" -ForegroundColor Green

        # Check token expiry
        if ($tokenData.expiry) {
            $expiryTime = [datetime]$tokenData.expiry
            $currentTime = Get-Date
            $timeUntilExpiry = $expiryTime - $currentTime

            Write-Host "Token expiry: $expiryTime" -ForegroundColor White
            Write-Host "Time until expiry: $($timeUntilExpiry.TotalMinutes.ToString('0.0')) minutes" -ForegroundColor White

            if ($timeUntilExpiry.TotalMinutes -gt 5) {
                Write-Host "✅ Token is still valid" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️  Token will expire soon, refresh needed" -ForegroundColor Yellow
            }
        }

        if ($tokenData.refresh_token) {
            Write-Host "✅ Refresh token available" -ForegroundColor Green
        }
        else {
            Write-Host "❌ No refresh token available" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Token file is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Token file not found: $tokenFile" -ForegroundColor Red
}

# Test directory structure
Write-Host "`n--- Directory Structure ---" -ForegroundColor Cyan
$directories = @("config", "logs", "temp")
foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "✅ Directory '$dir' exists" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Directory '$dir' missing" -ForegroundColor Red
    }
}

# Test script availability
Write-Host "`n--- Script Files ---" -ForegroundColor Cyan
$scripts = @("SimpleBackupGUI.ps1", "Run_Backup_GUI.ps1", "Test_GUI.ps1")
foreach ($script in $scripts) {
    if (Test-Path $script) {
        Write-Host "✅ Script '$script' exists" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Script '$script' missing" -ForegroundColor Red
    }
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Configuration test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\Test_GUI.ps1" -ForegroundColor White
Write-Host "2. Run: .\Run_Backup_GUI.ps1" -ForegroundColor White
Write-Host "3. Or run: .\SimpleBackupGUI.ps1" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}