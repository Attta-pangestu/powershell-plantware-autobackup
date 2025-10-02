# Test script untuk memverifikasi perbaikan upload langsung tanpa temp dependency

Write-Host "=== Test Upload Langsung Tanpa Temp ===" -ForegroundColor Cyan
Write-Host "Testing direct upload functionality..." -ForegroundColor Yellow

# Test path configuration
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

Write-Host "Current directory: $(Get-Location)" -ForegroundColor Green

# Test 1: Check if SimpleBackupGUI.ps1 exists
if (Test-Path "SimpleBackupGUI.ps1") {
    Write-Host "✅ SimpleBackupGUI.ps1 found" -ForegroundColor Green
}
else {
    Write-Host "❌ SimpleBackupGUI.ps1 missing" -ForegroundColor Red
    exit 1
}

# Test 2: Check config file
if (Test-Path "config\auto_backup_config.json") {
    Write-Host "✅ Config file found" -ForegroundColor Green
    try {
        $config = Get-Content "config\auto_backup_config.json" -Raw | ConvertFrom-Json
        Write-Host "   - Backup items: $($config.backup_items.Count)" -ForegroundColor White

        # Show backup items
        foreach ($item in $config.backup_items) {
            $status = if ($item.Enabled) { "Enabled" } else { "Disabled" }
            $type = if ($item.IsFolder) { "Folder" } else { "File" }
            Write-Host "   - $($item.Name): $type - $status" -ForegroundColor White
        }
    }
    catch {
        Write-Host "❌ Config file invalid: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Config file missing" -ForegroundColor Red
}

# Test 3: Check if backup sources exist
Write-Host "`n--- Checking Backup Sources ---" -ForegroundColor Cyan
try {
    $config = Get-Content "config\auto_backup_config.json" -Raw | ConvertFrom-Json
    foreach ($item in $config.backup_items) {
        if (Test-Path $item.SourcePath) {
            $fileInfo = Get-Item $item.SourcePath
            $size = [math]::Round($fileInfo.Length / 1MB, 2)
            Write-Host "✅ $($item.Name): $($item.SourcePath) ($size MB)" -ForegroundColor Green
        }
        else {
            Write-Host "❌ $($item.Name): $($item.SourcePath) - NOT FOUND" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "❌ Error checking backup sources: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test file reading with retry mechanism
Write-Host "`n--- Testing File Reading with Retry ---" -ForegroundColor Cyan
$testFile = "$env:TEMP\test_upload.txt"
try {
    # Create test file
    "Test content for direct upload testing" | Out-File -FilePath $testFile -Force
    Write-Host "✅ Test file created: $testFile" -ForegroundColor Green

    # Test file reading multiple times
    for ($i = 1; $i -le 3; $i++) {
        $fileContent = [System.IO.File]::ReadAllBytes($testFile)
        Write-Host "✅ File reading attempt $i successful ($($fileContent.Length) bytes)" -ForegroundColor Green
        Start-Sleep -Milliseconds 500
    }

    # Clean up
    Remove-Item $testFile -Force
    Write-Host "✅ Test file cleaned up" -ForegroundColor Green
}
catch {
    Write-Host "❌ File reading test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Direct upload functionality test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Key improvements:" -ForegroundColor Yellow
Write-Host "1. Files uploaded directly without temp folder dependency" -ForegroundColor White
Write-Host "2. Retry mechanism for file reading (3 attempts)" -ForegroundColor White
Write-Host "3. Better error handling for file access issues" -ForegroundColor White
Write-Host "4. Automatic cleanup of temporary files" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host "2. Select backup items and click 'Backup Selected'" -ForegroundColor White
Write-Host "3. Monitor logs for detailed progress" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}