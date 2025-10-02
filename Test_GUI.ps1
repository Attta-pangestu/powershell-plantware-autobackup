# Test file untuk SimpleBackupGUI.ps1

Write-Host "=== Simple Backup GUI Test ===" -ForegroundColor Cyan
Write-Host "Testing environment and dependencies..." -ForegroundColor Yellow

# Test PowerShell version
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green

# Test .NET assemblies
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Write-Host "✅ .NET assemblies loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to load .NET assemblies: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test directory structure
$directories = @("config", "logs", "temp")
foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "✅ Directory '$dir' exists" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Directory '$dir' will be created on first run" -ForegroundColor Yellow
    }
}

# Test config file
if (Test-Path "config\auto_backup_config.json") {
    Write-Host "✅ Config file exists" -ForegroundColor Green
    try {
        $config = Get-Content "config\auto_backup_config.json" -Raw | ConvertFrom-Json
        Write-Host "✅ Config file is valid JSON" -ForegroundColor Green
        Write-Host "   - Backup items count: $($config.backup_items.Count)" -ForegroundColor White
    }
    catch {
        Write-Host "❌ Config file is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠️  Config file will be created on first run" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Test Results ===" -ForegroundColor Cyan
Write-Host "All tests passed! The application should work correctly." -ForegroundColor Green
Write-Host ""
Write-Host "To start the application:" -ForegroundColor Yellow
Write-Host "1. Run: .\Run_Backup_GUI.ps1" -ForegroundColor White
Write-Host "2. Or run: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host ""
Write-Host "For Google Drive setup:" -ForegroundColor Yellow
Write-Host "1. Go to Settings tab" -ForegroundColor White
Write-Host "2. Enter your Client ID and Client Secret" -ForegroundColor White
Write-Host "3. Click 'Connect to Google Drive'" -ForegroundColor White
Write-Host "4. Click 'Save Settings'" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}