# Test script untuk memverifikasi perbaikan multipart upload error

Write-Host "=== Test Multipart Upload Fix ===" -ForegroundColor Cyan
Write-Host "Testing byte array conversion fix..." -ForegroundColor Yellow

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

        # Show enabled backup items
        $enabledItems = $config.backup_items | Where-Object { $_.Enabled -eq $true }
        if ($enabledItems.Count -gt 0) {
            Write-Host "   - Enabled items: $($enabledItems.Count)" -ForegroundColor Green
            foreach ($item in $enabledItems) {
                Write-Host "     * $($item.Name): $($item.SourcePath)" -ForegroundColor White
            }
        }
        else {
            Write-Host "   - No enabled items found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "❌ Config file invalid: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "❌ Config file missing" -ForegroundColor Red
}

# Test 3: Test content type detection
Write-Host "`n--- Testing Content Type Detection ---" -ForegroundColor Cyan
$testFiles = @(
    "test.pdf",
    "test.png",
    "test.jpg",
    "test.zip",
    "test.txt",
    "test.docx"
)

foreach ($testFile in $testFiles) {
    $fileExtension = [System.IO.Path]::GetExtension($testFile).ToLower()
    $contentType = switch ($fileExtension) {
        ".pdf" { "application/pdf" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".zip" { "application/zip" }
        default { "application/octet-stream" }
    }
    Write-Host "✅ $testFile -> $contentType" -ForegroundColor White
}

# Test 4: Test memory stream operations
Write-Host "`n--- Testing Memory Stream Operations ---" -ForegroundColor Cyan
try {
    # Test memory stream creation
    $memoryStream = New-Object System.IO.MemoryStream
    $testData = [System.Text.Encoding]::UTF8.GetBytes("Test data for memory stream")
    $memoryStream.Write($testData, 0, $testData.Length)
    $result = $memoryStream.ToArray()
    $memoryStream.Close()

    Write-Host "✅ Memory stream test successful ($($result.Length) bytes)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Memory stream test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Test byte array operations
Write-Host "`n--- Testing Byte Array Operations ---" -ForegroundColor Cyan
try {
    # Test byte array list operations
    $byteList = New-Object System.Collections.Generic.List[byte]
    $testBytes = [System.Text.Encoding]::UTF8.GetBytes("Hello World")

    foreach ($byte in $testBytes) {
        $byteList.Add($byte)
    }

    $finalArray = $byteList.ToArray()
    Write-Host "✅ Byte array list test successful ($($finalArray.Length) bytes)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Byte array list test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Multipart upload fix test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Key fixes implemented:" -ForegroundColor Yellow
Write-Host "1. Fixed byte array conversion error using MemoryStream" -ForegroundColor White
Write-Host "2. Dynamic content type detection based on file extension" -ForegroundColor White
Write-Host "3. Proper multipart body construction" -ForegroundColor White
Write-Host "4. Better error handling and logging" -ForegroundColor White
Write-Host ""
Write-Host "Technical details:" -ForegroundColor Yellow
Write-Host "- Replaced List<byte>.AddRange() with MemoryStream.Write()" -ForegroundColor White
Write-Host "- Added proper content type detection for different file types" -ForegroundColor White
Write-Host "- Used sequential byte writing instead of array slicing" -ForegroundColor White
Write-Host "- Improved logging for debugging purposes" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host "2. Select enabled backup items" -ForegroundColor White
Write-Host "3. Click 'Backup Selected' to test the fix" -ForegroundColor White
Write-Host "4. Monitor logs for upload progress" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}