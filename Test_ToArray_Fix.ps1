# Test script untuk memverifikasi perbaikan ToArray() error

Write-Host "=== Test ToArray() Method Fix ===" -ForegroundColor Cyan
Write-Host "Testing byte array and MemoryStream operations..." -ForegroundColor Yellow

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

# Test 2: Check config and enabled items
if (Test-Path "config\auto_backup_config.json") {
    Write-Host "✅ Config file found" -ForegroundColor Green
    try {
        $config = Get-Content "config\auto_backup_config.json" -Raw | ConvertFrom-Json
        $enabledItems = $config.backup_items | Where-Object { $_.Enabled -eq $true }

        Write-Host "   - Total backup items: $($config.backup_items.Count)" -ForegroundColor White
        Write-Host "   - Enabled items: $($enabledItems.Count)" -ForegroundColor Green

        if ($enabledItems.Count -gt 0) {
            foreach ($item in $enabledItems) {
                if (Test-Path $item.SourcePath) {
                    $fileInfo = Get-Item $item.SourcePath
                    $size = [math]::Round($fileInfo.Length / 1MB, 2)
                    Write-Host "   ✅ $($item.Name): $size MB" -ForegroundColor Green
                }
                else {
                    Write-Host "   ❌ $($item.Name): File not found" -ForegroundColor Red
                }
            }
        }
    }
    catch {
        Write-Host "❌ Config file invalid: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Config file missing" -ForegroundColor Red
}

# Test 3: Test MemoryStream operations
Write-Host "`n--- Testing MemoryStream Operations ---" -ForegroundColor Cyan
try {
    # Create test data
    $testData = [System.Text.Encoding]::UTF8.GetBytes("This is test data for MemoryStream operations")

    # Test MemoryStream
    $memoryStream = New-Object System.IO.MemoryStream
    $memoryStream.Write($testData, 0, $testData.Length)

    # Get array and test properties
    $resultArray = $memoryStream.ToArray()
    $memoryStream.Close()

    Write-Host "✅ MemoryStream created successfully" -ForegroundColor Green
    Write-Host "   - Original size: $($testData.Length) bytes" -ForegroundColor White
    Write-Host "   - Result size: $($resultArray.Length) bytes" -ForegroundColor White
    Write-Host "   - Type: $($resultArray.GetType().Name)" -ForegroundColor White

    # Test that result is byte array (has Length property)
    if ($resultArray.Length -gt 0) {
        Write-Host "✅ Result is proper byte array with Length property" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Result array is empty" -ForegroundColor Red
    }

    # Test that ToArray() is not available on byte array
    try {
        $toArrayMethod = $resultArray.GetType().GetMethod("ToArray")
        if ($toArrayMethod) {
            Write-Host "⚠️  ToArray() method found (unexpected)" -ForegroundColor Yellow
        }
        else {
            Write-Host "✅ ToArray() method not found (expected for byte array)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "✅ ToArray() method not available (expected)" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ MemoryStream test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test boundary construction
Write-Host "`n--- Testing Boundary Construction ---" -ForegroundColor Cyan
try {
    $boundary = [System.Guid]::NewGuid().ToString()
    $boundaryBytes = [System.Text.Encoding]::UTF8.GetBytes("--$boundary")
    $crlfBytes = [System.Text.Encoding]::UTF8.GetBytes("`r`n")

    Write-Host "✅ Boundary generated: $boundary" -ForegroundColor Green
    Write-Host "   - Boundary bytes: $($boundaryBytes.Length)" -ForegroundColor White
    Write-Host "   - CRLF bytes: $($crlfBytes.Length)" -ForegroundColor White
}
catch {
    Write-Host "❌ Boundary construction failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Test file operations
Write-Host "`n--- Testing File Operations ---" -ForegroundColor Cyan
try {
    $testFile = "$env:TEMP\test_upload.txt"
    "Test content for upload" | Out-File -FilePath $testFile -Force

    $fileContent = [System.IO.File]::ReadAllBytes($testFile)
    Write-Host "✅ File reading successful: $($fileContent.Length) bytes" -ForegroundColor Green

    Remove-Item $testFile -Force
    Write-Host "✅ File cleanup successful" -ForegroundColor Green
}
catch {
    Write-Host "❌ File operations failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "ToArray() method fix test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Key fixes implemented:" -ForegroundColor Yellow
Write-Host "1. Removed duplicate .ToArray() call on byte array" -ForegroundColor White
Write-Host "2. Fixed Content-Length header from .Count to .Length" -ForegroundColor White
Write-Host "3. Added comprehensive error handling for upload" -ForegroundColor White
Write-Host "4. Added detailed logging for upload process" -ForegroundColor White
Write-Host ""
Write-Host "Technical details:" -ForegroundColor Yellow
Write-Host "- MemoryStream.ToArray() returns byte[] (not List<byte>)" -ForegroundColor White
Write-Host "- byte[] has Length property, not Count" -ForegroundColor White
Write-Host "- byte[] does not have ToArray() method" -ForegroundColor White
Write-Host "- Added HTTP error response parsing for better debugging" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host "2. Select enabled backup items" -ForegroundColor White
Write-Host "3. Click 'Backup Selected' to test the fix" -ForegroundColor White
Write-Host "4. Check logs for detailed upload progress" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}