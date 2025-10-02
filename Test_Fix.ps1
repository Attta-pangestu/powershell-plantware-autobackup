# Test script untuk memverifikasi perbaikan error readAllBytes

Write-Host "=== Test Perbaikan readAllBytes Error ===" -ForegroundColor Cyan
Write-Host "Testing file reading and backup functionality..." -ForegroundColor Yellow

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
    }
    catch {
        Write-Host "❌ Config file invalid: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Config file missing" -ForegroundColor Red
}

# Test 3: Check token file
if (Test-Path "config\token.json") {
    Write-Host "✅ Token file found" -ForegroundColor Green
}
else {
    Write-Host "❌ Token file missing" -ForegroundColor Red
}

# Test 4: Check directories
$directories = @("temp", "logs")
foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "✅ Directory '$dir' exists" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Directory '$dir' will be created" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Test 5: Test file reading with a sample file
Write-Host "`n--- Testing File Reading ---" -ForegroundColor Cyan
$testFile = "temp\test_read.txt"
try {
    # Create test file
    "Test content for file reading" | Out-File -FilePath $testFile -Force
    Write-Host "✅ Test file created: $testFile" -ForegroundColor Green

    # Test file reading
    $fileContent = [System.IO.File]::ReadAllBytes($testFile)
    Write-Host "✅ File reading successful ($($fileContent.Length) bytes)" -ForegroundColor Green

    # Clean up
    Remove-Item $testFile -Force
    Write-Host "✅ Test file cleaned up" -ForegroundColor Green
}
catch {
    Write-Host "❌ File reading test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "File reading functionality test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\Test_Configuration.ps1" -ForegroundColor White
Write-Host "2. Start GUI: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host "3. Test backup operation with selected items" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}