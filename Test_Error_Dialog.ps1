# Test script untuk memverifikasi error dialog yang lebih besar

Write-Host "=== Test Error Dialog ===" -ForegroundColor Cyan
Write-Host "Testing improved error dialog with larger height..." -ForegroundColor Yellow

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

# Test 2: Load and test the Show-ErrorDialog function
Write-Host "`n--- Loading Show-ErrorDialog function ---" -ForegroundColor Cyan
try {
    # Load the script
    . .\SimpleBackupGUI.ps1

    # Test the error dialog function exists
    if (Get-Command Show-ErrorDialog -ErrorAction SilentlyContinue) {
        Write-Host "✅ Show-ErrorDialog function loaded successfully" -ForegroundColor Green

        # Test error dialog with sample error
        Write-Host "`n--- Testing Error Dialog ---" -ForegroundColor Cyan
        Write-Host "Displaying sample error dialog..." -ForegroundColor Yellow

        $sampleError = @"
Sample Error Details:
- Error Type: System.IO.IOException
- Message: File tidak ditemukan: C:\path\to\missing\file.pdf
- Stack Trace:
   at System.IO.File.ReadAllBytes(String path)
   at Upload-ToGoogleDrive(String filePath, String fileName)
   at Backup-Item(BackupItem backupItem)
   at <ScriptBlock>

Additional Information:
- File size: 0 bytes
- Last access: 2025-10-02 10:30:45
- User context: nbgmf
- Process ID: 12345

Troubleshooting Steps:
1. Check if the file exists at the specified path
2. Verify file permissions
3. Ensure file is not locked by another process
4. Check available disk space
5. Verify user has read access to the file

Timestamp: 2025-10-02 14:30:25.1234
Log File: logs\backup_2025-10-02.log
"@

        Show-ErrorDialog -title "Sample Backup Error" -message "Backup operation failed for DATA_KOPERASI_SIMPANG_TIGA" -details $sampleError

        Write-Host "✅ Error dialog test completed" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Show-ErrorDialog function not found" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Error loading script: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Error dialog functionality test completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Key improvements:" -ForegroundColor Yellow
Write-Host "1. Larger dialog window (700x500 pixels)" -ForegroundColor White
Write-Host "2. Scrollable error details textbox" -ForegroundColor White
Write-Host "3. Copy error button for easy debugging" -ForegroundColor White
Write-Host "4. Better formatting with monospace font" -ForegroundColor White
Write-Host "5. Professional color scheme and layout" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\SimpleBackupGUI.ps1" -ForegroundColor White
Write-Host "2. Try backup operation to see error dialog in action" -ForegroundColor White
Write-Host "3. Test copy error functionality" -ForegroundColor White

# Ask user if they want to start the GUI
$answer = Read-Host "`nDo you want to start the GUI now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Starting GUI..." -ForegroundColor Green
    .\SimpleBackupGUI.ps1
}
else {
    Write-Host "Test completed. You can start the GUI manually." -ForegroundColor Yellow
}