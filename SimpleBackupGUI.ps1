#Requires -Version 5.1

<#
.SYNOPSIS
    GUI Sederhana untuk Backup ke Google Drive
.DESCRIPTION
    Aplikasi GUI sederhana untuk mengelola dan melakukan backup file/folder ke Google Drive
.AUTHOR
    Plantware Auto Backup Team
.VERSION
    1.0.0
#>

# Tambahkan .NET assemblies yang diperlukan
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Import modules for program files integration
$modulesPath = Join-Path $PSScriptRoot "modules"
. "$modulesPath\ConfigManager.ps1"
. "$modulesPath\GoogleDriveAuthManager.ps1"

# Variabel global
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:ConfigManager = $null
$script:AuthManager = $null
$script:BackupItems = @()
$script:SelectedItems = @()
$script:DebugMode = $false

# Fungsi untuk menulis log
function Write-Log {
    param([string]$message, [string]$level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$level] $message"

    # Tulis ke console jika debug mode
    if ($script:DebugMode) {
        $color = switch($level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "INFO" { "Green" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }

    # Tulis ke file jika ConfigManager sudah diinisialisasi
    if ($script:ConfigManager) {
        try {
            $logFile = $script:ConfigManager.GetLogFilePath("backup_gui")
            $logMessage | Out-File -FilePath $logFile -Append -ErrorAction SilentlyContinue
        }
        catch {
            # Fallback ke console jika file logging gagal
            Write-Host "LOG ERROR: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host $logMessage -ForegroundColor White
        }
    }
    else {
        # Fallback ke console jika ConfigManager belum siap
        $color = switch($level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "INFO" { "Green" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}

# Fungsi untuk membaca konfigurasi
function Get-BackupConfig {
    if (-not $script:ConfigManager) {
        Write-Log "ConfigManager tidak diinisialisasi" "ERROR"
        return $null
    }

    try {
        $googleDriveConfig = $script:ConfigManager.GetGoogleDriveConfig()
        $backupItems = $script:ConfigManager.GetBackupItems()
        $scheduledTasks = $script:ConfigManager.GetScheduledTasks()
        $settings = $script:ConfigManager.GetSettings()

        Write-Host "DEBUG: Get-BackupConfig - backupItems from ConfigManager:" -ForegroundColor Magenta
        foreach ($item in $backupItems) {
            Write-Host "  Name: $($item.Name), SourcePath: '$($item.SourcePath)'" -ForegroundColor Magenta
        }

        $config = @{
            google_drive = $googleDriveConfig
            backup_items = $backupItems
            scheduled_tasks = $scheduledTasks
            settings = $settings
        }

        # Ensure all backup items have DestinationType property (migrate existing items)
        if ($config.backup_items) {
            foreach ($item in $config.backup_items) {
                if (-not $item.PSObject.Properties.Name -contains "DestinationType") {
                    $item | Add-Member -NotePropertyName "DestinationType" -NotePropertyValue "GoogleDrive" -Force
                }
            }
        }

        Write-Host "DEBUG: Get-BackupConfig - config.backup_items after processing:" -ForegroundColor Magenta
        foreach ($item in $config.backup_items) {
            Write-Host "  Name: $($item.Name), SourcePath: '$($item.SourcePath)'" -ForegroundColor Magenta
        }

        $script:BackupItems = $config.backup_items
        Write-Log "Config berhasil dimuat dari ConfigManager"
        return $config
    }
    catch {
        $errorMsg = "Gagal membaca config: " + $_.Exception.Message
        Write-Log $errorMsg "ERROR"
        return $null
    }
}

# Fungsi untuk menyimpan konfigurasi
function Save-BackupConfig {
    param([object]$config)

    if (-not $script:ConfigManager) {
        Write-Log "ConfigManager tidak diinisialisasi" "ERROR"
        return $false
    }

    try {
        # Update Google Drive configuration
        if ($config.google_drive) {
            $script:ConfigManager.UpdateGoogleDriveConfig($config.google_drive)
        }

        # Update settings
        if ($config.settings) {
            $script:ConfigManager.UpdateSettings($config.settings)
        }

        # Update backup items
        if ($config.backup_items) {
            $script:ConfigManager.UpdateBackupItems($config.backup_items)
        }

        # Update scheduled tasks
        if ($config.scheduled_tasks) {
            $script:ConfigManager.UpdateScheduledTasks($config.scheduled_tasks)
        }

        Write-Log "Config berhasil disimpan melalui ConfigManager"
        return $true
    }
    catch {
        $errorMsg = "Gagal menyimpan config: " + $_.Exception.Message
        Write-Log $errorMsg "ERROR"
        return $false
    }
}

# Fungsi untuk mengotentikasi Google Drive
function Connect-GoogleDrive {
    param([string]$clientId, [string]$clientSecret)

    if (-not $script:ConfigManager -or -not $script:AuthManager) {
        Write-Log "ConfigManager atau AuthManager tidak diinisialisasi" "ERROR"
        return $false
    }

    try {
        # Simpan client credentials ke config
        $config = Get-BackupConfig
        if ($config -and $config.google_drive) {
            $config.google_drive.client_id = $clientId
            $config.google_drive.client_secret = $clientSecret
            Save-BackupConfig $config
        }

        # Coba autentikasi menggunakan AuthManager
        $authResult = $script:AuthManager.Authenticate()

        if ($authResult.Success) {
            Write-Log "Berhasil terhubung ke Google Drive"
            return $true
        } else {
            $errorMsg = "Gagal terhubung ke Google Drive: " + $authResult.Message
            Write-Log $errorMsg "ERROR"

            # Jika manual authentication diperlukan, tampilkan URL
            if ($authResult.AuthUrl) {
                Write-Log "Manual authentication diperlukan. Buka URL berikut:" "INFO"
                Write-Log $authResult.AuthUrl "INFO"
                return $false
            }

            return $false
        }
    }
    catch {
        $errorMsg = "Error dalam Connect-GoogleDrive: " + $_.Exception.Message
        Write-Log $errorMsg "ERROR"
        return $false
    }
}

# Fungsi untuk refresh token
function Refresh-GoogleDriveToken {
    param([string]$refreshToken, [string]$clientId, [string]$clientSecret)

    if (-not $script:AuthManager) {
        Write-Log "AuthManager tidak diinisialisasi" "ERROR"
        return @{ Success = $false; ErrorMessage = "AuthManager tidak diinisialisasi" }
    }

    try {
        # Gunakan AuthManager untuk refresh token
        $refreshResult = $script:AuthManager.RefreshToken()

        if ($refreshResult.Success) {
            Write-Log "Token berhasil di-refresh"
            return @{ Success = $true }
        } else {
            $errorMsg = "Gagal refresh token: " + $refreshResult.Message
            Write-Log $errorMsg "ERROR"
            return @{ Success = $false; ErrorMessage = $refreshResult.Message }
        }
    }
    catch {
        $errorMsg = "Error dalam Refresh-GoogleDriveToken: " + $_.Exception.Message
        Write-Log $errorMsg "ERROR"
        return @{ Success = $false; ErrorMessage = $_.Exception.Message }
    }
}

# Fungsi untuk upload file ke Google Drive
function Upload-ToGoogleDrive {
    param([string]$filePath, [string]$fileName)

    Write-Log "Upload $fileName ke Google Drive..." "INFO"

    try {
        # Cek token menggunakan AuthManager
        if (-not $script:AuthManager -or -not $script:AuthManager.IsAuthenticated()) {
            Write-Log "Token tidak valid atau tidak ditemukan" "ERROR"
            return @{ Success = $false; ErrorMessage = "Token tidak ditemukan" }
        }

        # Coba refresh token jika expired
        if ($script:AuthManager.IsTokenValid()) {
            Write-Log "Token masih valid" "INFO"
        } else {
            Write-Log "Token expired, mencoba refresh..." "WARN"
            $refreshResult = $script:AuthManager.RefreshToken()

            if (-not $refreshResult.Success) {
                return @{ Success = $false; ErrorMessage = "Gagal refresh token" }
            }
        }

        # Get access token from AuthManager
        $accessToken = $script:AuthManager.GetAccessToken()
        if ([string]::IsNullOrEmpty($accessToken)) {
            Write-Log "Access token tidak tersedia" "ERROR"
            return @{ Success = $false; ErrorMessage = "Access token tidak tersedia" }
        }

        # Read file content dengan error handling yang lebih baik
        try {
            if (-not (Test-Path $filePath)) {
                Write-Log "File tidak ditemukan: $filePath" "ERROR"
                return @{ Success = $false; ErrorMessage = "File tidak ditemukan: $filePath" }
            }

            # Check jika file sedang digunakan dengan cara yang lebih aman
            $fileInfo = $null
            try {
                $fileInfo = Get-Item $filePath -ErrorAction Stop
            }
            catch {
                Write-Log "File sedang digunakan atau tidak dapat diakses: $filePath" "ERROR"
                return @{ Success = $false; ErrorMessage = "File sedang digunakan atau tidak dapat diakses: $filePath" }
            }

            if ($fileInfo.Length -eq 0) {
                Write-Log "File kosong: $filePath" "ERROR"
                return @{ Success = $false; ErrorMessage = "File kosong: $filePath" }
            }

            Write-Log "Membaca file: $($fileInfo.Name) ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)" "INFO"

            # Coba baca file dengan retry mechanism
            $maxRetries = 3
            $retryDelay = 1000 # milliseconds
            $fileContent = $null

            for ($i = 1; $i -le $maxRetries; $i++) {
                try {
                    $fileContent = [System.IO.File]::ReadAllBytes($filePath)
                    Write-Log "File berhasil dibaca (percobaan $i), ukuran: $($fileContent.Length) bytes" "INFO"
                    break
                }
                catch {
                    if ($i -eq $maxRetries) {
                        throw "Gagal membaca file setelah $maxRetries percobaan: $($_.Exception.Message)"
                    }
                    Write-Log "Percobaan $i gagal, mencoba lagi dalam $($retryDelay)ms..." "WARNING"
                    Start-Sleep -Milliseconds $retryDelay
                }
            }
        }
        catch {
            $errorMsg = "Gagal membaca file '$filePath': $($_.Exception.Message)"
            Write-Log $errorMsg "ERROR"
            return @{ Success = $false; ErrorMessage = $errorMsg }
        }

        # Prepare upload metadata
        $metadata = @{
            name = $fileName
            parents = @("root")  # Upload ke root folder
        } | ConvertTo-Json -Depth 10

        # Determine content type based on file extension
        $fileExtension = [System.IO.Path]::GetExtension($fileName).ToLower()
        $fileContentType = switch ($fileExtension) {
            ".pdf" { "application/pdf" }
            ".png" { "image/png" }
            ".jpg" { "image/jpeg" }
            ".jpeg" { "image/jpeg" }
            ".zip" { "application/zip" }
            default { "application/octet-stream" }
        }

        Write-Log "File content type: $fileContentType" "INFO"

        # Prepare multipart upload
        $boundary = [System.Guid]::NewGuid().ToString()
        $contentType = "multipart/related; boundary=$boundary"

        # Create multipart body dengan pendekatan yang lebih reliable
        $boundaryBytes = [System.Text.Encoding]::UTF8.GetBytes("--$boundary")
        $crlfBytes = [System.Text.Encoding]::UTF8.GetBytes("`r`n")
        $metadataHeaderBytes = [System.Text.Encoding]::UTF8.GetBytes("Content-Type: application/json; charset=UTF-8`r`n`r`n")
        $metadataBytes = [System.Text.Encoding]::UTF8.GetBytes($metadata)
        $fileHeaderBytes = [System.Text.Encoding]::UTF8.GetBytes("Content-Type: $fileContentType`r`n`r`n")
        $endBoundaryBytes = [System.Text.Encoding]::UTF8.GetBytes("--$boundary--")

        # Build multipart body using MemoryStream
        $memoryStream = New-Object System.IO.MemoryStream

        # Write first boundary
        $memoryStream.Write($boundaryBytes, 0, $boundaryBytes.Length)
        $memoryStream.Write($crlfBytes, 0, $crlfBytes.Length)

        # Write metadata part
        $memoryStream.Write($metadataHeaderBytes, 0, $metadataHeaderBytes.Length)
        $memoryStream.Write($metadataBytes, 0, $metadataBytes.Length)
        $memoryStream.Write($crlfBytes, 0, $crlfBytes.Length)

        # Write file boundary
        $memoryStream.Write($boundaryBytes, 0, $boundaryBytes.Length)
        $memoryStream.Write($crlfBytes, 0, $crlfBytes.Length)

        # Write file header
        $memoryStream.Write($fileHeaderBytes, 0, $fileHeaderBytes.Length)

        # Write file content
        $memoryStream.Write($fileContent, 0, $fileContent.Length)
        $memoryStream.Write($crlfBytes, 0, $crlfBytes.Length)

        # Write end boundary
        $memoryStream.Write($endBoundaryBytes, 0, $endBoundaryBytes.Length)

        # Get final body as byte array
        $finalBody = $memoryStream.ToArray()
        $memoryStream.Close()

        # Upload to Google Drive
        Write-Log "Uploading to Google Drive..." "INFO"
        Write-Log "File size: $([math]::Round($finalBody.Length / 1MB, 2)) MB" "INFO"
        Write-Log "Content type: $contentType" "INFO"

        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type" = $contentType
            "Content-Length" = $finalBody.Length
        }

        $uploadUrl = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

        try {
            $response = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $finalBody
            Write-Log "Upload response received successfully" "INFO"
        }
        catch {
            $errorMsg = "Upload failed: $($_.Exception.Message)"
            Write-Log $errorMsg "ERROR"

            # Add more detailed error information
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                Write-Log "HTTP Status: $statusCode - $statusDescription" "ERROR"

                try {
                    $responseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($responseStream)
                    $errorResponse = $reader.ReadToEnd()
                    Write-Log "Error response: $errorResponse" "ERROR"
                }
                catch {
                    Write-Log "Could not read error response" "WARNING"
                }
            }

            throw $errorMsg
        }

        Write-Log "Upload $fileName berhasil" "INFO"
        return @{
            Success = $true
            FileId = $response.id
            FileUrl = "https://drive.google.com/file/d/$($response.id)/view"
            FileName = $response.name
            SizeBytes = $response.size
        }
    }
    catch {
        Write-Log "Upload gagal: $($_.Exception.Message)" "ERROR"
        Write-Log "Detail error: $($_.Exception.InnerException)" "DEBUG"
        return @{
            Success = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Fungsi untuk backup item
function Backup-Item {
    param([object]$backupItem)

    Write-Log "Memulai backup $($backupItem.Name)" "INFO"

    try {
        # Validasi SourcePath tidak null atau kosong
        if ([string]::IsNullOrEmpty($backupItem.SourcePath)) {
            Write-Log "SourcePath tidak valid atau kosong untuk item: $($backupItem.Name)" "ERROR"
            return @{
                Success = $false
                ErrorMessage = "SourcePath tidak valid atau kosong"
            }
        }

        # Cek apakah path ada (for Google Drive backup)
        if ($backupItem.DestinationType -ne "Git" -and -not (Test-Path $backupItem.SourcePath)) {
            Write-Log "Path tidak ditemukan: $($backupItem.SourcePath)" "ERROR"
            return @{
                Success = $false
                ErrorMessage = "Path tidak ditemukan"
            }
        }

        # Determine backup type and process accordingly
        if ($backupItem.DestinationType -eq "Git") {
            # Git backup - push the current codebase
            Write-Log "Memproses Git backup untuk: $($backupItem.Name)" "INFO"
            
            try {
                # Change to the source path directory to perform git operations
                $originalPath = Get-Location
                Set-Location $backupItem.SourcePath
                
                # Function to check if git is available
                function Test-GitAvailable {
                    try {
                        $gitVersion = & git --version 2>$null
                        return ($LASTEXITCODE -eq 0)
                    }
                    catch {
                        return $false
                    }
                }

                # Function to check if current directory is a git repository
                function Test-IsGitRepository {
                    try {
                        $result = & git rev-parse --is-inside-work-tree 2>$null
                        return ($LASTEXITCODE -eq 0 -and $result -eq $true)
                    }
                    catch {
                        return $false
                    }
                }

                # Function to add, commit, and push changes
                function Push-GitChanges {
                    param(
                        [string]$CommitMessage = "Auto-commit from backup system $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    )
                    
                    try {
                        Write-Log "Adding all changes to git..." "INFO"
                        $result = & git add . 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Log "Error adding files: $result" "ERROR"
                            return $false
                        }
                        
                        Write-Log "Committing changes: $CommitMessage" "INFO"
                        $result = & git commit -m $CommitMessage 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Changes committed successfully" "INFO"
                        }
                        elseif ($result -like "*nothing to commit*") {
                            Write-Log "No changes to commit" "INFO"
                            # This is OK, continue to push
                        }
                        else {
                            Write-Log "Error committing: $result" "ERROR"
                            return $false
                        }
                        
                        Write-Log "Getting current branch..." "INFO"
                        $branch = & git branch --show-current 2>$null
                        if ($LASTEXITCODE -ne 0 -or -not $branch) {
                            $branch = "main"  # Default to main if we can't determine current branch
                            Write-Log "Using default branch: $branch" "INFO"
                        }
                        
                        Write-Log "Pushing changes to remote repository..." "INFO"
                        $result = & git push origin $branch 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Successfully pushed changes to $branch" "INFO"
                            return $true
                        }
                        else {
                            if ($result -like "*Authentication*" -or $result -like "*auth*" -or $result -like "*403*" -or $result -like "*401*") {
                                Write-Log "Authentication failed. Please check your git credentials." "ERROR"
                            }
                            elseif ($result -like "*Updates were rejected*") {
                                Write-Log "Updates were rejected. You may need to pull first." "ERROR"
                                Write-Log "Attempting pull before push..." "WARNING"
                                $pullResult = & git pull origin $branch --no-rebase 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Log "Pulled successfully, trying push again..." "INFO"
                                    $result = & git push origin $branch 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Log "Successfully pushed changes after pull" "INFO"
                                        return $true
                                    }
                                    else {
                                        Write-Log "Push failed after pull: $result" "ERROR"
                                        return $false
                                    }
                                }
                                else {
                                    Write-Log "Pull also failed: $pullResult" "ERROR"
                                    return $false
                                }
                            }
                            else {
                                Write-Log "Error pushing changes: $result" "ERROR"
                            }
                            return $false
                        }
                    }
                    catch {
                        Write-Log "Error in git operations: $($_.Exception.Message)" "ERROR"
                        return $false
                    }
                }
                
                # Perform git operations
                if (-not (Test-GitAvailable)) {
                    Write-Log "Git is not available. Please install Git and ensure it's in your PATH." "ERROR"
                    return @{
                        Success = $false
                        ErrorMessage = "Git is not available. Please install Git and ensure it's in your PATH."
                    }
                }
                
                if (-not (Test-IsGitRepository)) {
                    Write-Log "This directory is not a git repository: $($backupItem.SourcePath)" "ERROR"
                    return @{
                        Success = $false
                        ErrorMessage = "This directory is not a git repository: $($backupItem.SourcePath)"
                    }
                }
                
                $uploadResult = Push-GitChanges -CommitMessage "Backup commit: $($backupItem.Name) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                
                # Restore original path
                Set-Location $originalPath
                
                if ($uploadResult) {
                    Write-Log "Git backup $($backupItem.Name) berhasil" "INFO"
                    return @{
                        Success = $true
                        FileId = "git-push-success"
                        FileUrl = "N/A"
                    }
                }
                else {
                    Write-Log "Git backup $($backupItem.Name) gagal" "ERROR" 
                    return @{
                        Success = $false
                        ErrorMessage = "Git push failed"
                    }
                }
            }
            catch {
                $errorMsg = "Git backup $($backupItem.Name) gagal: " + $_.Exception.Message
                Write-Log $errorMsg "ERROR"
                return @{
                    Success = $false
                    ErrorMessage = $_.Exception.Message
                }
            }
        }
        else {
            # Google Drive backup (existing functionality)
            Write-Log "Memproses Google Drive backup untuk: $($backupItem.Name)" "INFO"

            try {
                if (Test-Path $backupItem.SourcePath -PathType Leaf) {
                    # Upload file tunggal langsung
                    $fileName = Split-Path $backupItem.SourcePath -Leaf
                    $uploadResult = Upload-ToGoogleDrive -filePath $backupItem.SourcePath -fileName $fileName
                    Write-Log "Upload file tunggal: $fileName" "INFO"
                }
                else {
                    # Buat file ZIP untuk folder (langsung di memory, tidak disimpan di temp)
                    $zipFileName = "$($backupItem.Name)_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
                    $zipFilePath = $backupItem.SourcePath

                    # Gunakan Compress-Archive dengan path yang benar
                    $tempZipPath = "$env:TEMP\$zipFileName"
                    Compress-Archive -Path $backupItem.SourcePath -DestinationPath $tempZipPath -CompressionLevel Optimal -ErrorAction Stop

                    Write-Log "File ZIP dibuat di temp: $tempZipPath" "INFO"

                    # Upload file ZIP
                    $uploadResult = Upload-ToGoogleDrive -filePath $tempZipPath -fileName $zipFileName

                    # Hapus file ZIP dari temp setelah upload
                    Remove-Item $tempZipPath -Force -ErrorAction SilentlyContinue
                    Write-Log "File ZIP dibersihkan dari temp" "INFO"
                }
            }
            catch {
                $errorMsg = "Gagal memproses backup: " + $_.Exception.Message
                Write-Log $errorMsg "ERROR"
                return @{
                    Success = $false
                    ErrorMessage = $errorMsg
                }
            }

            if ($uploadResult.Success) {
                Write-Log "Backup $($backupItem.Name) berhasil" "INFO"
                return @{
                    Success = $true
                    FileId = $uploadResult.FileId
                    FileUrl = $uploadResult.FileUrl
                }
            }
            else {
                Write-Log "Backup $($backupItem.Name) gagal: $($uploadResult.ErrorMessage)" "ERROR"
                return @{
                    Success = $false
                    ErrorMessage = $uploadResult.ErrorMessage
                }
            }
        }
    }
    catch {
        $errorMsg = "Backup $($backupItem.Name) gagal: " + $_.Exception.Message
        Write-Log $errorMsg "ERROR"
        return @{
            Success = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Fungsi untuk menambah item backup
function Add-BackupItem {
    param([string]$name, [string]$path, [string]$description = "", [string]$destinationType = "GoogleDrive")

    $newItem = @{
        Name = $name
        SourcePath = $path
        Description = $description
        DestinationType = $destinationType  # Added destination type (GoogleDrive or Git)
        IsFolder = if($destinationType -eq "Git") { $true } else { Test-Path $path -PathType Container }
        Enabled = $true
        LastBackup = ""
        CompressionLevel = 6
        GDriveSubfolder = ""
        CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    if (-not $script:ConfigManager) {
        Write-Log "ConfigManager tidak diinisialisasi" "ERROR"
        return $false
    }

    # Get current backup items and add new item
    $currentItems = $script:ConfigManager.GetBackupItems()
    $newItems = @()
    $newItems += $currentItems
    $newItems += $newItem

    # Save using ConfigManager
    $script:ConfigManager.Config.backup_items = $newItems
    $script:ConfigManager.SaveConfiguration()

    Write-Log "Item backup '$name' berhasil ditambahkan" "INFO"
    return $true
}

# Fungsi untuk task scheduling
function New-ScheduledTask {
    param(
        [string]$name,
        [string[]]$backupItemNames,  # Array of backup item names
        [string]$scheduleType,  # "Daily", "Weekly", "Monthly"
        [hashtable]$scheduleSettings
    )

    $newTask = @{
        Name = $name
        BackupItemNames = $backupItemNames  # Changed to array
        ScheduleType = $scheduleType
        Enabled = $true
        CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        LastRun = ""
        NextRun = ""
        Settings = $scheduleSettings
    }

    # Calculate next run time
    $newTask.NextRun = Get-NextRunTime -scheduleType $scheduleType -settings $scheduleSettings

    return $newTask
}

function Get-NextRunTime {
    param(
        [string]$scheduleType,
        [hashtable]$settings
    )

    $now = Get-Date

    switch ($scheduleType) {
        "Daily" {
            $time = [DateTime]::Parse($settings.Time)
            $nextRun = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $time.Hour -Minute $time.Minute -Second 0

            if ($nextRun -lt $now) {
                $nextRun = $nextRun.AddDays(1)
            }
        }
        "Weekly" {
            $time = [DateTime]::Parse($settings.Time)
            $dayOfWeek = [int]$settings.DayOfWeek
            $nextRun = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $time.Hour -Minute $time.Minute -Second 0

            # Adjust to next specified day
            while ($nextRun.DayOfWeek -ne $dayOfWeek) {
                $nextRun = $nextRun.AddDays(1)
            }

            if ($nextRun -lt $now) {
                $nextRun = $nextRun.AddDays(7)
            }
        }
        "Monthly" {
            $time = [DateTime]::Parse($settings.Time)
            $dayOfMonth = [int]$settings.DayOfMonth
            $nextRun = Get-Date -Year $now.Year -Month $now.Month -Day $dayOfMonth -Hour $time.Hour -Minute $time.Minute -Second 0

            if ($nextRun -lt $now) {
                $nextRun = $nextRun.AddMonths(1)
            }
        }
        default {
            $nextRun = $now.AddHours(1)
        }
    }

    return $nextRun.ToString("yyyy-MM-dd HH:mm:ss")
}

function Register-WindowsScheduledTask {
    param(
        [string]$taskName,
        [string]$scriptPath,
        [string]$scheduleType,
        [hashtable]$settings
    )

    try {
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Log "Existing task '$taskName' unregistered" "INFO"
        }

        # Create trigger based on schedule type
        $trigger = switch ($scheduleType) {
            "Daily" {
                $time = [DateTime]::Parse($settings.Time)
                New-ScheduledTaskTrigger -Daily -At $time
            }
            "Weekly" {
                $time = [DateTime]::Parse($settings.Time)
                $days = switch ([int]$settings.DayOfWeek) {
                    0 { "Sunday" }
                    1 { "Monday" }
                    2 { "Tuesday" }
                    3 { "Wednesday" }
                    4 { "Thursday" }
                    5 { "Friday" }
                    6 { "Saturday" }
                }
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $time
            }
            "Monthly" {
                $time = [DateTime]::Parse($settings.Time)
                New-ScheduledTaskTrigger -Monthly -DaysOfMonth ([int]$settings.DayOfMonth) -At $time
            }
            default {
                throw "Unsupported schedule type: $scheduleType"
            }
        }

        # Create action
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""

        # Create settings
        $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        # Register the task
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $taskSettings -Force | Out-Null

        Write-Log "Windows scheduled task '$taskName' registered successfully" "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to register Windows scheduled task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Unregister-WindowsScheduledTask {
    param([string]$taskName)

    try {
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Log "Windows scheduled task '$taskName' unregistered" "INFO"
            return $true
        }
        return $false
    }
    catch {
        Write-Log "Failed to unregister Windows scheduled task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Run-ScheduledBackup {
    Write-Log "Starting scheduled backup..." "INFO"

    try {
        $configPath = "config\auto_backup_config.json"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $enabledTasks = $config.scheduled_tasks | Where-Object { $_.Enabled -eq $true }

        if ($enabledTasks.Count -eq 0) {
            Write-Log "No enabled scheduled tasks found" "INFO"
            return
        }

        foreach ($task in $enabledTasks) {
            Write-Log "Processing scheduled task: $($task.Name)" "INFO"

            # Handle both old single-item and new multi-item format
            $backupItemNames = @()
            if ($task.PSObject.Properties.Name -contains "BackupItemNames") {
                $backupItemNames = $task.BackupItemNames
            }
            elseif ($task.PSObject.Properties.Name -contains "BackupItemName") {
                $backupItemNames = @($task.BackupItemName)  # Convert single item to array
            }

            if ($backupItemNames.Count -eq 0) {
                Write-Log "No backup items specified for task '$($task.Name)'" "WARNING"
                continue
            }

            $taskSuccess = $true
            $processedItems = @()

            foreach ($itemName in $backupItemNames) {
                # Find backup item
                $backupItem = $config.backup_items | Where-Object { $_.Name -eq $itemName }
                if (-not $backupItem) {
                    Write-Log "Backup item '$($itemName)' not found for task '$($task.Name)'" "WARNING"
                    $taskSuccess = $false
                    continue
                }

                # Check if backup item is enabled
                if ($backupItem.Enabled -ne $true) {
                    Write-Log "Backup item '$($itemName)' is disabled, skipping" "INFO"
                    continue
                }

                Write-Log "Backing up item: $($itemName)" "INFO"

                # Perform backup
                $result = Backup-Item -backupItem $backupItem

                if ($result.Success) {
                    Write-Log "Backup of '$($itemName)' completed successfully" "INFO"
                    $processedItems += $itemName

                    # Update last backup time in backup item
                    $itemInConfig = $config.backup_items | Where-Object { $_.Name -eq $backupItem.Name }
                    if ($itemInConfig) {
                        $itemInConfig.LastBackup = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    }
                }
                else {
                    Write-Log "Backup of '$($itemName)' failed: $($result.ErrorMessage)" "ERROR"
                    $taskSuccess = $false
                }
            }

            # Update task info
            $task.LastRun = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $task.NextRun = Get-NextRunTime -scheduleType $task.ScheduleType -settings $task.Settings

            if ($taskSuccess -and $processedItems.Count -gt 0) {
                Write-Log "Scheduled backup '$($task.Name)' completed successfully ($($processedItems.Count) items)" "INFO"
            }
            elseif ($processedItems.Count -gt 0) {
                Write-Log "Scheduled backup '$($task.Name)' completed with some failures ($($processedItems.Count)/$($backupItemNames.Count) items)" "WARNING"
            }
            else {
                Write-Log "Scheduled backup '$($task.Name)' failed - no items were successfully backed up" "ERROR"
            }
        }

        # Save updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        Write-Log "Scheduled backup process completed" "INFO"
    }
    catch {
        Write-Log "Scheduled backup process failed: $($_.Exception.Message)" "ERROR"
    }
}

# Fungsi untuk menampilkan error dialog dengan ukuran lebih besar
function Show-ErrorDialog {
    param(
        [string]$title,
        [string]$message,
        [string]$details
    )

    $errorForm = New-Object System.Windows.Forms.Form
    $errorForm.Text = $title
    $errorForm.Size = New-Object System.Drawing.Size(700, 500)
    $errorForm.StartPosition = "CenterScreen"
    $errorForm.FormBorderStyle = "FixedDialog"
    $errorForm.MaximizeBox = $false
    $errorForm.MinimizeBox = $false
    $errorForm.ControlBox = $true
    $errorForm.BackColor = [System.Drawing.Color]::White

    # Main message label
    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Location = New-Object System.Drawing.Point(20, 20)
    $lblMessage.Size = New-Object System.Drawing.Size(640, 30)
    $lblMessage.Text = $message
    $lblMessage.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $lblMessage.ForeColor = [System.Drawing.Color]::DarkRed

    # Details label
    $lblDetails = New-Object System.Windows.Forms.Label
    $lblDetails.Location = New-Object System.Drawing.Point(20, 60)
    $lblDetails.Size = New-Object System.Drawing.Size(640, 30)
    $lblDetails.Text = "Error Details:"
    $lblDetails.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)

    # Details textbox dengan scroll
    $txtDetails = New-Object System.Windows.Forms.TextBox
    $txtDetails.Location = New-Object System.Drawing.Point(20, 90)
    $txtDetails.Size = New-Object System.Drawing.Size(640, 300)
    $txtDetails.Multiline = $true
    $txtDetails.ScrollBars = "Vertical"
    $txtDetails.ReadOnly = $true
    $txtDetails.Text = $details
    $txtDetails.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtDetails.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $txtDetails.BorderStyle = "FixedSingle"

    # Copy button
    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Location = New-Object System.Drawing.Point(20, 400)
    $btnCopy.Size = New-Object System.Drawing.Size(100, 30)
    $btnCopy.Text = "Copy Error"
    $btnCopy.Font = New-Object System.Drawing.Font("Arial", 9)
    $btnCopy.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $btnCopy.ForeColor = [System.Drawing.Color]::White
    $btnCopy.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnCopy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($txtDetails.Text)
        [System.Windows.Forms.MessageBox]::Show("Error details copied to clipboard!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Location = New-Object System.Drawing.Point(560, 400)
    $btnClose.Size = New-Object System.Drawing.Size(100, 30)
    $btnClose.Text = "Close"
    $btnClose.Font = New-Object System.Drawing.Font("Arial", 9)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(220, 20, 60)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK

    # Add controls to form
    $errorForm.Controls.AddRange(@($lblMessage, $lblDetails, $txtDetails, $btnCopy, $btnClose))

    # Show the form
    $errorForm.Add_Shown({$errorForm.Activate()})
    [void]$errorForm.ShowDialog()
}

# Membuat form utama
function Show-MainForm {
    Write-Host "DEBUG: Show-MainForm function called" -ForegroundColor Cyan
    # Buat form utama
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = "Simple Backup GUI - Google Drive"
    $mainForm.Size = New-Object System.Drawing.Size(800, 600)
    $mainForm.StartPosition = "CenterScreen"
    $mainForm.FormBorderStyle = "FixedSingle"
    $mainForm.MaximizeBox = $false

    # Load config awal
    $config = Get-BackupConfig
    if (-not $config) {
        [System.Windows.Forms.MessageBox]::Show("Failed to load configuration", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Tab Control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(780, 520)
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)

    # Status Label (dideklarasikan di awal)
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 540)
    $statusLabel.Size = New-Object System.Drawing.Size(760, 20)
    $statusLabel.Text = "Ready"
    $statusLabel.ForeColor = [System.Drawing.Color]::Green

    # Progress Bar (dideklarasikan di awal)
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 565)
    $progressBar.Size = New-Object System.Drawing.Size(760, 20)
    $progressBar.Visible = $false

    # Tab Backup Items
    $backupTab = New-Object System.Windows.Forms.TabPage
    $backupTab.Text = "Backup Items"
    $backupTab.BackColor = [System.Drawing.Color]::White

    # ListView untuk backup items
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Size = New-Object System.Drawing.Size(750, 350)
    $listView.Location = New-Object System.Drawing.Point(10, 10)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.CheckBoxes = $true
    $listView.GridLines = $true

    # Tambahkan columns
    $listView.Columns.Add("Nama", 150) | Out-Null
    $listView.Columns.Add("Path", 250) | Out-Null
    $listView.Columns.Add("Tujuan", 80) | Out-Null
    $listView.Columns.Add("Tipe", 80) | Out-Null
    $listView.Columns.Add("Status", 100) | Out-Null
    $listView.Columns.Add("Terakhir Backup", 120) | Out-Null

    # Buttons untuk backup tab
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add Item"
    $btnAdd.Size = New-Object System.Drawing.Size(80, 30)
    $btnAdd.Location = New-Object System.Drawing.Point(10, 370)

    $btnEdit = New-Object System.Windows.Forms.Button
    $btnEdit.Text = "Edit"
    $btnEdit.Size = New-Object System.Drawing.Size(80, 30)
    $btnEdit.Location = New-Object System.Drawing.Point(100, 370)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove"
    $btnRemove.Size = New-Object System.Drawing.Size(80, 30)
    $btnRemove.Location = New-Object System.Drawing.Point(190, 370)

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = "Backup Selected"
    $btnBackup.Size = New-Object System.Drawing.Size(120, 30)
    $btnBackup.Location = New-Object System.Drawing.Point(280, 370)
    $btnBackup.BackColor = [System.Drawing.Color]::LightGreen

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
    $btnRefresh.Location = New-Object System.Drawing.Point(410, 370)

    # Event handlers for backup buttons
    $btnBackup.Add_Click({
        $selectedItems = $listView.CheckedItems
        if ($selectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Pilih minimal satu item untuk backup!", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $btnBackup.Enabled = $false
        $progressBar.Visible = $true
        $progressBar.Value = 0
        $progressBar.Maximum = $selectedItems.Count

        foreach ($listItem in $selectedItems) {
            $backupItem = $listItem.Tag
            Write-Host "DEBUG: Backup button clicked - Item: $($backupItem.Name)" -ForegroundColor Yellow
            Write-Host "DEBUG: Backup button clicked - SourcePath: '$($backupItem.SourcePath)'" -ForegroundColor Cyan
            Write-Host "DEBUG: Backup button clicked - SourcePath is null: $($backupItem.SourcePath -eq $null)" -ForegroundColor Cyan
            Write-Host "DEBUG: Backup button clicked - SourcePath is empty: $([string]::IsNullOrEmpty($backupItem.SourcePath))" -ForegroundColor Cyan

            $statusLabel.Text = "Membackup $($backupItem.Name)..."

            $result = Backup-Item -backupItem $backupItem

            if ($result.Success) {
                # Update last backup time
                $config = Get-BackupConfig
                $itemInConfig = $config.backup_items | Where-Object { $_.Name -eq $backupItem.Name }
                if ($itemInConfig) {
                    $itemInConfig.LastBackup = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Save-BackupConfig $config
                }

                $statusLabel.Text = "Backup $($backupItem.Name) berhasil"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
            }
            else {
                $statusLabel.Text = "Backup $($backupItem.Name) gagal: $($result.ErrorMessage)"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red

                # Tampilkan error dialog dengan ukuran lebih besar
                Show-ErrorDialog -title "Backup Gagal" -message "Backup $($backupItem.Name) gagal" -details $result.ErrorMessage
            }

            $progressBar.Value++
            Start-Sleep -Milliseconds 500
        }

        $progressBar.Visible = $false
        $btnBackup.Enabled = $true
        Refresh-ListView

        [System.Windows.Forms.MessageBox]::Show("Backup selesai!", "Selesai", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    $btnRefresh.Add_Click({
        Refresh-ListView
        $statusLabel.Text = "Daftar backup telah diperbarui"
    })

    $btnAdd.Add_Click({
        # Form untuk menambah item baru
        $addForm = New-Object System.Windows.Forms.Form
        $addForm.Text = "Tambah Backup Item"
        $addForm.Size = New-Object System.Drawing.Size(400, 350)
        $addForm.StartPosition = "CenterScreen"

        $lblName = New-Object System.Windows.Forms.Label
        $lblName.Text = "Nama:"
        $lblName.Location = New-Object System.Drawing.Point(20, 20)
        $lblName.Size = New-Object System.Drawing.Size(100, 20)

        $txtName = New-Object System.Windows.Forms.TextBox
        $txtName.Size = New-Object System.Drawing.Size(250, 20)
        $txtName.Location = New-Object System.Drawing.Point(120, 20)

        $lblPath = New-Object System.Windows.Forms.Label
        $lblPath.Text = "Path:"
        $lblPath.Location = New-Object System.Drawing.Point(20, 50)
        $lblPath.Size = New-Object System.Drawing.Size(100, 20)

        $txtPath = New-Object System.Windows.Forms.TextBox
        $txtPath.Size = New-Object System.Drawing.Size(250, 20)
        $txtPath.Location = New-Object System.Drawing.Point(120, 50)

        $btnBrowse = New-Object System.Windows.Forms.Button
        $btnBrowse.Text = "Browse..."
        $btnBrowse.Size = New-Object System.Drawing.Size(75, 20)
        $btnBrowse.Location = New-Object System.Drawing.Point(370, 50)

        $lblDesc = New-Object System.Windows.Forms.Label
        $lblDesc.Text = "Deskripsi:"
        $lblDesc.Location = New-Object System.Drawing.Point(20, 80)
        $lblDesc.Size = New-Object System.Drawing.Size(100, 20)

        $txtDesc = New-Object System.Windows.Forms.TextBox
        $txtDesc.Size = New-Object System.Drawing.Size(250, 60)
        $txtDesc.Location = New-Object System.Drawing.Point(120, 80)
        $txtDesc.Multiline = $true
        
        # Destination Type selection
        $lblDestType = New-Object System.Windows.Forms.Label
        $lblDestType.Text = "Tujuan:"
        $lblDestType.Location = New-Object System.Drawing.Point(20, 150)
        $lblDestType.Size = New-Object System.Drawing.Size(100, 20)

        $cboDestType = New-Object System.Windows.Forms.ComboBox
        $cboDestType.Size = New-Object System.Drawing.Size(250, 20)
        $cboDestType.Location = New-Object System.Drawing.Point(120, 150)
        $cboDestType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboDestType.Items.AddRange(@("GoogleDrive", "Git")) | Out-Null
        $cboDestType.SelectedIndex = 0  # Default to GoogleDrive

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Size = New-Object System.Drawing.Size(75, 30)
        $btnOK.Location = New-Object System.Drawing.Point(220, 240)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
        $btnCancel.Location = New-Object System.Drawing.Point(305, 240)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $addForm.Controls.AddRange(@($lblName, $txtName, $lblPath, $txtPath, $btnBrowse, $lblDesc, $txtDesc, $lblDestType, $cboDestType, $btnOK, $btnCancel))

        $btnBrowse.Add_Click({
            $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
            if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtPath.Text = $folderBrowser.SelectedPath
            }
        })

        if ($addForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($txtName.Text -and $txtPath.Text) {
                $destinationType = $cboDestType.SelectedItem
                Add-BackupItem -name $txtName.Text -path $txtPath.Text -description $txtDesc.Text -destinationType $destinationType
                Refresh-ListView
                $statusLabel.Text = "Item '$($txtName.Text)' berhasil ditambahkan (Tujuan: $destinationType)"
            }
        }
    })

    $btnEdit.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $selectedItem = $listView.SelectedItems[0]
            $itemToEdit = $selectedItem.Tag

            # Form untuk mengedit item
            $editForm = New-Object System.Windows.Forms.Form
            $editForm.Text = "Edit Backup Item"
            $editForm.Size = New-Object System.Drawing.Size(400, 350)
            $editForm.StartPosition = "CenterScreen"

            $lblName = New-Object System.Windows.Forms.Label
            $lblName.Text = "Nama:"
            $lblName.Location = New-Object System.Drawing.Point(20, 20)
            $lblName.Size = New-Object System.Drawing.Size(100, 20)

            $txtName = New-Object System.Windows.Forms.TextBox
            $txtName.Size = New-Object System.Drawing.Size(250, 20)
            $txtName.Location = New-Object System.Drawing.Point(120, 20)
            $txtName.Text = $itemToEdit.Name

            $lblPath = New-Object System.Windows.Forms.Label
            $lblPath.Text = "Path:"
            $lblPath.Location = New-Object System.Drawing.Point(20, 50)
            $lblPath.Size = New-Object System.Drawing.Size(100, 20)

            $txtPath = New-Object System.Windows.Forms.TextBox
            $txtPath.Size = New-Object System.Drawing.Size(250, 20)
            $txtPath.Location = New-Object System.Drawing.Point(120, 50)
            $txtPath.Text = $itemToEdit.SourcePath

            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "Browse..."
            $btnBrowse.Size = New-Object System.Drawing.Size(75, 20)
            $btnBrowse.Location = New-Object System.Drawing.Point(370, 50)

            $lblDesc = New-Object System.Windows.Forms.Label
            $lblDesc.Text = "Deskripsi:"
            $lblDesc.Location = New-Object System.Drawing.Point(20, 80)
            $lblDesc.Size = New-Object System.Drawing.Size(100, 20)

            $txtDesc = New-Object System.Windows.Forms.TextBox
            $txtDesc.Size = New-Object System.Drawing.Size(250, 60)
            $txtDesc.Location = New-Object System.Drawing.Point(120, 80)
            $txtDesc.Multiline = $true
            $txtDesc.Text = $itemToEdit.Description

            # Destination Type selection
            $lblDestType = New-Object System.Windows.Forms.Label
            $lblDestType.Text = "Tujuan:"
            $lblDestType.Location = New-Object System.Drawing.Point(20, 150)
            $lblDestType.Size = New-Object System.Drawing.Size(100, 20)

            $cboDestType = New-Object System.Windows.Forms.ComboBox
            $cboDestType.Size = New-Object System.Drawing.Size(250, 20)
            $cboDestType.Location = New-Object System.Drawing.Point(120, 150)
            $cboDestType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $cboDestType.Items.AddRange(@("GoogleDrive", "Git")) | Out-Null
            $cboDestType.SelectedItem = $itemToEdit.DestinationType

            # Enabled checkbox
            $chkEnabled = New-Object System.Windows.Forms.CheckBox
            $chkEnabled.Text = "Aktif"
            $chkEnabled.Location = New-Object System.Drawing.Point(120, 180)
            $chkEnabled.Size = New-Object System.Drawing.Size(100, 20)
            $chkEnabled.Checked = $itemToEdit.Enabled

            $btnOK = New-Object System.Windows.Forms.Button
            $btnOK.Text = "OK"
            $btnOK.Size = New-Object System.Drawing.Size(75, 30)
            $btnOK.Location = New-Object System.Drawing.Point(220, 240)
            $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = "Cancel"
            $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
            $btnCancel.Location = New-Object System.Drawing.Point(305, 240)
            $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

            $editForm.Controls.AddRange(@($lblName, $txtName, $lblPath, $txtPath, $btnBrowse, $lblDesc, $txtDesc, $lblDestType, $cboDestType, $chkEnabled, $btnOK, $btnCancel))

            $btnBrowse.Add_Click({
                $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $txtPath.Text = $folderBrowser.SelectedPath
                }
            })

            if ($editForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                if ($txtName.Text -and $txtPath.Text) {
                    if (-not $script:ConfigManager) {
                        [System.Windows.Forms.MessageBox]::Show("ConfigManager tidak diinisialisasi.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        return
                    }

                    # Get current backup items and find the item to edit
                    $currentItems = $script:ConfigManager.GetBackupItems()
                    $itemIndex = -1
                    for ($i = 0; $i -lt $currentItems.Count; $i++) {
                        if ($currentItems[$i].Name -eq $itemToEdit.Name) {
                            $itemIndex = $i
                            break
                        }
                    }

                    if ($itemIndex -ge 0) {
                        # Update the item
                        $currentItems[$itemIndex].Name = $txtName.Text
                        $currentItems[$itemIndex].SourcePath = $txtPath.Text
                        $currentItems[$itemIndex].Description = $txtDesc.Text
                        $currentItems[$itemIndex].DestinationType = $cboDestType.SelectedItem
                        $currentItems[$itemIndex].Enabled = $chkEnabled.Checked

                        # Save using ConfigManager
                        $script:ConfigManager.Config.backup_items = $currentItems
                        $script:ConfigManager.SaveConfiguration()

                        Refresh-ListView
                        $statusLabel.Text = "Item '$($txtName.Text)' berhasil diperbarui"
                    }
                }
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Pilih item yang akan diedit terlebih dahulu.", "Peringatan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })

    $btnRemove.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $selectedItems = @($listView.SelectedItems)
            $itemNames = $selectedItems | ForEach-Object { $_.Text }
            $itemNamesText = $itemNames -join ", "
            
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Apakah Anda yakin ingin menghapus item berikut?`n`n$itemNamesText", 
                "Konfirmasi Hapus", 
                [System.Windows.Forms.MessageBoxButtons]::YesNo, 
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                if (-not $script:ConfigManager) {
                    [System.Windows.Forms.MessageBox]::Show("ConfigManager tidak diinisialisasi.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }

                # Get current backup items
                $currentItems = $script:ConfigManager.GetBackupItems()

                foreach ($selectedItem in $selectedItems) {
                    $itemToRemove = $selectedItem.Tag
                    $currentItems = $currentItems | Where-Object { $_.Name -ne $itemToRemove.Name }
                }

                # Save using ConfigManager
                $script:ConfigManager.Config.backup_items = $currentItems
                $script:ConfigManager.SaveConfiguration()

                Refresh-ListView
                $statusLabel.Text = "Item berhasil dihapus: $itemNamesText"
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Pilih item yang akan dihapus terlebih dahulu.", "Peringatan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })

    $btnRefresh.Add_Click({
        Refresh-ListView
        $statusLabel.Text = "Daftar backup telah diperbarui"
    })

    # Refresh list view
    function Refresh-ListView {
        Write-Host "DEBUG: Refresh-ListView called" -ForegroundColor Yellow

        $listView.Items.Clear()

        # Get fresh config data instead of using script variable
        try {
            $config = Get-BackupConfig
            Write-Host "DEBUG: Config loaded with $($config.backup_items.Count) items" -ForegroundColor Yellow

            if ($config.backup_items -and $config.backup_items.Count -gt 0) {
                foreach ($item in $config.backup_items) {
                    Write-Host "DEBUG: Processing item: $($item.Name)" -ForegroundColor Yellow
                    Write-Host "DEBUG: Item SourcePath: '$($item.SourcePath)'" -ForegroundColor Cyan

                    # Check if item properties exist
                    if (-not $item.Name) {
                        Write-Host "DEBUG: Item.Name is null, skipping" -ForegroundColor Red
                        continue
                    }

                    $listItem = New-Object System.Windows.Forms.ListViewItem
                    $listItem.Text = $item.Name
                    $listItem.Tag = $item  # Store the item for later use

                    # Safely add subitems with null checks
                    $sourcePath = if ($item.SourcePath) { $item.SourcePath } else { "" }
                    $listItem.SubItems.Add($sourcePath) | Out-Null

                    $destType = if ($item.DestinationType) { $item.DestinationType } else { "GoogleDrive" }
                    $listItem.SubItems.Add($destType) | Out-Null

                    $itemType = if ($item.IsFolder) { "Folder" } else { "File" }
                    $listItem.SubItems.Add($itemType) | Out-Null

                    $status = if ($item.Enabled) { "Aktif" } else { "Non-aktif" }
                    $listItem.SubItems.Add($status) | Out-Null

                    $lastBackup = if ($item.LastBackup) { $item.LastBackup } else { "" }
                    $listItem.SubItems.Add($lastBackup) | Out-Null

                    $listView.Items.Add($listItem) | Out-Null
                }
            } else {
                Write-Host "DEBUG: No backup items to display" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "DEBUG: Error in Refresh-ListView: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host "DEBUG: Refresh-ListView completed" -ForegroundColor Yellow
    }

    # Status label dan progress bar sudah dideklarasikan di awal fungsi

    # Tab Settings
    $settingsTab = New-Object System.Windows.Forms.TabPage
    $settingsTab.Text = "Settings"
    $settingsTab.BackColor = [System.Drawing.Color]::White

    # Google Drive settings
    $lblClientId = New-Object System.Windows.Forms.Label
    $lblClientId.Text = "Client ID:"
    $lblClientId.Location = New-Object System.Drawing.Point(20, 20)
    $lblClientId.Size = New-Object System.Drawing.Size(100, 20)

    $txtClientId = New-Object System.Windows.Forms.TextBox
    $txtClientId.Size = New-Object System.Drawing.Size(500, 20)
    $txtClientId.Location = New-Object System.Drawing.Point(120, 20)
    $txtClientId.Text = $config.google_drive.client_id

    $lblClientSecret = New-Object System.Windows.Forms.Label
    $lblClientSecret.Text = "Client Secret:"
    $lblClientSecret.Location = New-Object System.Drawing.Point(20, 50)
    $lblClientSecret.Size = New-Object System.Drawing.Size(100, 20)

    $txtClientSecret = New-Object System.Windows.Forms.TextBox
    $txtClientSecret.Size = New-Object System.Drawing.Size(500, 20)
    $txtClientSecret.Location = New-Object System.Drawing.Point(120, 50)
    $txtClientSecret.Text = $config.google_drive.client_secret
    $txtClientSecret.PasswordChar = "*"

    $btnConnect = New-Object System.Windows.Forms.Button
    $btnConnect.Text = "Connect to Google Drive"
    $btnConnect.Size = New-Object System.Drawing.Size(150, 30)
    $btnConnect.Location = New-Object System.Drawing.Point(120, 80)
    $btnConnect.BackColor = [System.Drawing.Color]::LightBlue

    $btnSaveSettings = New-Object System.Windows.Forms.Button
    $btnSaveSettings.Text = "Save Settings"
    $btnSaveSettings.Size = New-Object System.Drawing.Size(100, 30)
    $btnSaveSettings.Location = New-Object System.Drawing.Point(280, 80)

    $btnConnect.Add_Click({
        if ($txtClientId.Text -and $txtClientSecret.Text) {
            $statusLabel.Text = "Menghubungkan ke Google Drive..."
            $btnConnect.Enabled = $false

            if (Connect-GoogleDrive -clientId $txtClientId.Text -clientSecret $txtClientSecret.Text) {
                $statusLabel.Text = "Berhasil terhubung ke Google Drive"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                [System.Windows.Forms.MessageBox]::Show("Berhasil terhubung ke Google Drive!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            else {
                $statusLabel.Text = "Gagal terhubung ke Google Drive"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red

                # Tampilkan error dialog dengan detail
                $errorDetails = "Gagal terhubung ke Google Drive. Periksa:`n- Client ID dan Client Secret sudah benar`n- Koneksi internet stabil`n- Token sudah valid`n`nCoba lagi atau periksa log file di folder 'logs' untuk detail lebih lanjut."
                Show-ErrorDialog -title "Koneksi Gagal" -message "Gagal terhubung ke Google Drive" -details $errorDetails
            }

            $btnConnect.Enabled = $true
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Masukkan Client ID dan Client Secret!", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })

    $btnSaveSettings.Add_Click({
        $config = Get-BackupConfig
        $config.google_drive.client_id = $txtClientId.Text
        $config.google_drive.client_secret = $txtClientSecret.Text
        Save-BackupConfig $config
        $statusLabel.Text = "Settings berhasil disimpan"
        [System.Windows.Forms.MessageBox]::Show("Settings berhasil disimpan!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    # Tab Schedule Management
    $scheduleTab = New-Object System.Windows.Forms.TabPage
    $scheduleTab.Text = "Schedule"
    $scheduleTab.BackColor = [System.Drawing.Color]::White

    # ListView for scheduled tasks
    $scheduleListView = New-Object System.Windows.Forms.ListView
    $scheduleListView.Size = New-Object System.Drawing.Size(750, 300)
    $scheduleListView.Location = New-Object System.Drawing.Point(10, 10)
    $scheduleListView.View = [System.Windows.Forms.View]::Details
    $scheduleListView.FullRowSelect = $true
    $scheduleListView.GridLines = $true
    $scheduleListView.CheckBoxes = $true
    $scheduleListView.MultiSelect = $true

    # Add columns for schedule list
    $scheduleListView.Columns.Add("Task Name", 150) | Out-Null
    $scheduleListView.Columns.Add("Backup Item", 150) | Out-Null
    $scheduleListView.Columns.Add("Schedule Type", 100) | Out-Null
    $scheduleListView.Columns.Add("Schedule Details", 200) | Out-Null
    $scheduleListView.Columns.Add("Next Run", 120) | Out-Null
    $scheduleListView.Columns.Add("Status", 80) | Out-Null

    # Buttons for schedule management
    $btnAddSchedule = New-Object System.Windows.Forms.Button
    $btnAddSchedule.Text = "Add Schedule"
    $btnAddSchedule.Size = New-Object System.Drawing.Size(100, 30)
    $btnAddSchedule.Location = New-Object System.Drawing.Point(10, 320)

    $btnEditSchedule = New-Object System.Windows.Forms.Button
    $btnEditSchedule.Text = "Edit"
    $btnEditSchedule.Size = New-Object System.Drawing.Size(80, 30)
    $btnEditSchedule.Location = New-Object System.Drawing.Point(120, 320)

    $btnRemoveSchedule = New-Object System.Windows.Forms.Button
    $btnRemoveSchedule.Text = "Remove"
    $btnRemoveSchedule.Size = New-Object System.Drawing.Size(80, 30)
    $btnRemoveSchedule.Location = New-Object System.Drawing.Point(210, 320)

    $btnEnableDisable = New-Object System.Windows.Forms.Button
    $btnEnableDisable.Text = "Enable/Disable"
    $btnEnableDisable.Size = New-Object System.Drawing.Size(120, 30)
    $btnEnableDisable.Location = New-Object System.Drawing.Point(300, 320)

    $btnRunNow = New-Object System.Windows.Forms.Button
    $btnRunNow.Text = "Run Now"
    $btnRunNow.Size = New-Object System.Drawing.Size(80, 30)
    $btnRunNow.Location = New-Object System.Drawing.Point(430, 320)

    # Selection status label
    $selectionStatusLabel = New-Object System.Windows.Forms.Label
    $selectionStatusLabel.Text = "No tasks selected"
    $selectionStatusLabel.Size = New-Object System.Drawing.Size(200, 20)
    $selectionStatusLabel.Location = New-Object System.Drawing.Point(520, 325)
    $selectionStatusLabel.ForeColor = [System.Drawing.Color]::Blue

    # Schedule status label
    $scheduleStatusLabel = New-Object System.Windows.Forms.Label
    $scheduleStatusLabel.Text = "Schedule tasks will appear here"
    $scheduleStatusLabel.Size = New-Object System.Drawing.Size(750, 20)
    $scheduleStatusLabel.Location = New-Object System.Drawing.Point(10, 360)

    # Function to refresh schedule list
    function Refresh-ScheduleList {
        $scheduleListView.Items.Clear()

        if (-not $script:ConfigManager) {
            $scheduleStatusLabel.Text = "ConfigManager not initialized"
            return
        }

        try {
            $config = Get-BackupConfig

        foreach ($task in $config.scheduled_tasks) {
            # Skip tasks with empty names
            if ([string]::IsNullOrWhiteSpace($task.Name)) {
                continue
            }

            # Handle both old format (BackupItemName) and new format (BackupItemNames)
            $backupItemsText = ""
            $hasBackupItems = $false

            if ($task.BackupItemNames -and $task.BackupItemNames.Count -gt 0) {
                # New format - array
                $backupItemsText = $task.BackupItemNames -join ", "
                $hasBackupItems = $true
            } elseif ($task.BackupItemName) {
                # Old format - single string
                $backupItemsText = $task.BackupItemName
                $hasBackupItems = $true
            }

            if (-not $hasBackupItems) {
                # No backup items configured
                continue
            }
            
            $item = New-Object System.Windows.Forms.ListViewItem
            $item.Text = $task.Name
            $item.SubItems.Add($backupItemsText) | Out-Null

            $scheduleTypeText = switch ($task.ScheduleType) {
                "Daily" { "Daily" }
                "Weekly" { "Weekly" }
                "Monthly" { "Monthly" }
                default { $task.ScheduleType }
            }
            $item.SubItems.Add($scheduleTypeText) | Out-Null

            $detailsText = switch ($task.ScheduleType) {
                "Daily" { "At $($task.Settings.Time)" }
                "Weekly" { "$([System.DayOfWeek]($task.Settings.DayOfWeek)) at $($task.Settings.Time)" }
                "Monthly" { "Day $($task.Settings.DayOfMonth) at $($task.Settings.Time)" }
                default { "N/A" }
            }
            $item.SubItems.Add($detailsText) | Out-Null

            $item.SubItems.Add($task.NextRun) | Out-Null
            $item.SubItems.Add($(if ($task.Enabled) { "Enabled" } else { "Disabled" })) | Out-Null

            $item.Tag = $task
            $scheduleListView.Items.Add($item) | Out-Null
        }

        $validTaskCount = ($config.scheduled_tasks | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Name) -and
            (($_.BackupItemNames -and $_.BackupItemNames.Count -gt 0) -or $_.BackupItemName)
        }).Count

        $scheduleStatusLabel.Text = "Total scheduled tasks: $validTaskCount"
        }
        catch {
            $scheduleStatusLabel.Text = "Error loading scheduled tasks: $($_.Exception.Message)"
        }
    }

    # Add Schedule button click
    $btnAddSchedule.Add_Click({
        # Show add schedule dialog
        $scheduleForm = New-Object System.Windows.Forms.Form
        $scheduleForm.Text = "Add Scheduled Task"
        $scheduleForm.Size = New-Object System.Drawing.Size(500, 450)
        $scheduleForm.StartPosition = "CenterScreen"

        # Task Name
        $lblTaskName = New-Object System.Windows.Forms.Label
        $lblTaskName.Text = "Task Name:"
        $lblTaskName.Location = New-Object System.Drawing.Point(20, 20)
        $lblTaskName.Size = New-Object System.Drawing.Size(100, 20)

        $txtTaskName = New-Object System.Windows.Forms.TextBox
        $txtTaskName.Size = New-Object System.Drawing.Size(300, 20)
        $txtTaskName.Location = New-Object System.Drawing.Point(120, 20)

        # Backup Item Selection (Multi-select)
        $lblBackupItem = New-Object System.Windows.Forms.Label
        $lblBackupItem.Text = "Backup Items:"
        $lblBackupItem.Location = New-Object System.Drawing.Point(20, 50)
        $lblBackupItem.Size = New-Object System.Drawing.Size(100, 20)

        $clbBackupItems = New-Object System.Windows.Forms.CheckedListBox
        $clbBackupItems.Size = New-Object System.Drawing.Size(300, 80)
        $clbBackupItems.Location = New-Object System.Drawing.Point(120, 50)
        $clbBackupItems.CheckOnClick = $true

        # Populate backup items with only enabled items
        $config = Get-BackupConfig
        if ($config -and $config.backup_items) {
            foreach ($item in $config.backup_items) {
                if ($item -and $item.Name -and $item.Enabled -eq $true) {
                    $clbBackupItems.Items.Add($item.Name) | Out-Null
                }
            }
        }

        # Schedule Type
        $lblScheduleType = New-Object System.Windows.Forms.Label
        $lblScheduleType.Text = "Schedule Type:"
        $lblScheduleType.Location = New-Object System.Drawing.Point(20, 140)
        $lblScheduleType.Size = New-Object System.Drawing.Size(100, 20)

        $cboScheduleType = New-Object System.Windows.Forms.ComboBox
        $cboScheduleType.Size = New-Object System.Drawing.Size(300, 20)
        $cboScheduleType.Location = New-Object System.Drawing.Point(120, 140)
        $cboScheduleType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboScheduleType.Items.AddRange(@("Daily", "Weekly", "Monthly")) | Out-Null

        # Schedule Settings Panel
        $pnlScheduleSettings = New-Object System.Windows.Forms.Panel
        $pnlScheduleSettings.Size = New-Object System.Drawing.Size(400, 150)
        $pnlScheduleSettings.Location = New-Object System.Drawing.Point(20, 170)
        $pnlScheduleSettings.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

        # Time picker
        $lblTime = New-Object System.Windows.Forms.Label
        $lblTime.Text = "Time:"
        $lblTime.Location = New-Object System.Drawing.Point(10, 20)
        $lblTime.Size = New-Object System.Drawing.Size(50, 20)

        $dtpTime = New-Object System.Windows.Forms.DateTimePicker
        $dtpTime.Size = New-Object System.Drawing.Size(100, 20)
        $dtpTime.Location = New-Object System.Drawing.Point(70, 20)
        $dtpTime.Format = [System.Windows.Forms.DateTimePickerFormat]::Time
        $dtpTime.Value = Get-Date -Hour 9 -Minute 0 -Second 0

        # Day of Week (for Weekly)
        $lblDayOfWeek = New-Object System.Windows.Forms.Label
        $lblDayOfWeek.Text = "Day of Week:"
        $lblDayOfWeek.Location = New-Object System.Drawing.Point(10, 50)
        $lblDayOfWeek.Size = New-Object System.Drawing.Size(100, 20)

        $cboDayOfWeek = New-Object System.Windows.Forms.ComboBox
        $cboDayOfWeek.Size = New-Object System.Drawing.Size(150, 20)
        $cboDayOfWeek.Location = New-Object System.Drawing.Point(120, 50)
        $cboDayOfWeek.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboDayOfWeek.Items.AddRange(@([System.DayOfWeek]::Monday, [System.DayOfWeek]::Tuesday, [System.DayOfWeek]::Wednesday, [System.DayOfWeek]::Thursday, [System.DayOfWeek]::Friday, [System.DayOfWeek]::Saturday, [System.DayOfWeek]::Sunday)) | Out-Null
        $cboDayOfWeek.SelectedIndex = 0

        # Day of Month (for Monthly)
        $lblDayOfMonth = New-Object System.Windows.Forms.Label
        $lblDayOfMonth.Text = "Day of Month:"
        $lblDayOfMonth.Location = New-Object System.Drawing.Point(10, 80)
        $lblDayOfMonth.Size = New-Object System.Drawing.Size(100, 20)

        $numDayOfMonth = New-Object System.Windows.Forms.NumericUpDown
        $numDayOfMonth.Size = New-Object System.Drawing.Size(60, 20)
        $numDayOfMonth.Location = New-Object System.Drawing.Point(120, 80)
        $numDayOfMonth.Minimum = 1
        $numDayOfMonth.Maximum = 31
        $numDayOfMonth.Value = 1

        # Add controls to settings panel
        $pnlScheduleSettings.Controls.AddRange(@($lblTime, $dtpTime, $lblDayOfWeek, $cboDayOfWeek, $lblDayOfMonth, $numDayOfMonth))

        # Initially hide day controls
        $lblDayOfWeek.Visible = $false
        $cboDayOfWeek.Visible = $false
        $lblDayOfMonth.Visible = $false
        $numDayOfMonth.Visible = $false

        # Schedule type change handler
        $cboScheduleType.Add_SelectedIndexChanged({
            switch ($cboScheduleType.SelectedItem.ToString()) {
                "Daily" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $false
                    $cboDayOfWeek.Visible = $false
                    $lblDayOfMonth.Visible = $false
                    $numDayOfMonth.Visible = $false
                }
                "Weekly" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $true
                    $cboDayOfWeek.Visible = $true
                    $lblDayOfMonth.Visible = $false
                    $numDayOfMonth.Visible = $false
                }
                "Monthly" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $false
                    $cboDayOfWeek.Visible = $false
                    $lblDayOfMonth.Visible = $true
                    $numDayOfMonth.Visible = $true
                }
            }
        })

        # Buttons
        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Size = New-Object System.Drawing.Size(75, 30)
        $btnOK.Location = New-Object System.Drawing.Point(200, 380)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
        $btnCancel.Location = New-Object System.Drawing.Point(290, 380)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        # Add controls to form
        $scheduleForm.Controls.AddRange(@($lblTaskName, $txtTaskName, $lblBackupItem, $clbBackupItems, $lblScheduleType, $cboScheduleType, $pnlScheduleSettings, $btnOK, $btnCancel))

        # Show form
        $result = $scheduleForm.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            # Get selected backup items
            $selectedBackupItems = @()
            for ($i = 0; $i -lt $clbBackupItems.Items.Count; $i++) {
                if ($clbBackupItems.GetItemChecked($i)) {
                    $selectedBackupItems += $clbBackupItems.Items[$i]
                }
            }

            # Validate input
            if (-not $txtTaskName.Text) {
                [System.Windows.Forms.MessageBox]::Show("Silakan masukkan nama task.", "Validasi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }

            if ($selectedBackupItems.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Silakan pilih minimal satu item backup.", "Validasi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }

            # Create new scheduled task
            $scheduleSettings = @{
                Time = $dtpTime.Value.ToString("HH:mm")
            }

            switch ($cboScheduleType.SelectedItem.ToString()) {
                "Weekly" {
                    $scheduleSettings.DayOfWeek = [int]$cboDayOfWeek.SelectedItem
                }
                "Monthly" {
                    $scheduleSettings.DayOfMonth = [int]$numDayOfMonth.Value
                }
            }

            $newTask = New-ScheduledTask -name $txtTaskName.Text -backupItemNames $selectedBackupItems -scheduleType $cboScheduleType.SelectedItem.ToString() -scheduleSettings $scheduleSettings

            # Add to config using ConfigManager
            if (-not $script:ConfigManager) {
                [System.Windows.Forms.MessageBox]::Show("ConfigManager tidak diinisialisasi.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            $currentConfig = Get-BackupConfig
            $newTasks = @()
            $newTasks += $currentConfig.scheduled_tasks
            $newTasks += $newTask

            $script:ConfigManager.Config.scheduled_tasks = $newTasks
            $script:ConfigManager.SaveConfiguration()

            # Register Windows scheduled task
            $taskName = "Backup_$($newTask.Name)"
            $scriptPath = Join-Path $PSScriptRoot "Run_Scheduled_Backup.ps1"
            Register-WindowsScheduledTask -taskName $taskName -scriptPath $scriptPath -scheduleType $newTask.ScheduleType -settings $newTask.Settings

            Refresh-ScheduleList
            $scheduleStatusLabel.Text = "Scheduled task '$($newTask.Name)' added successfully"
            $scheduleStatusLabel.ForeColor = [System.Drawing.Color]::Green
        }
    })

    # Script-level timer variable to prevent multiple instances
    $script:selectionUpdateTimer = $null

    # Event handler for checkbox changes to update selection status
    $scheduleListView.Add_ItemCheck({
        param($sender, $e)
        
        # Stop and dispose existing timer if it exists
        if ($script:selectionUpdateTimer -ne $null) {
            try {
                $script:selectionUpdateTimer.Stop()
                $script:selectionUpdateTimer.Dispose()
            } catch {
                # Ignore disposal errors
            }
            $script:selectionUpdateTimer = $null
        }
        
        # Use a timer to delay the update since ItemCheck fires before the check state changes
        $script:selectionUpdateTimer = New-Object System.Windows.Forms.Timer
        $script:selectionUpdateTimer.Interval = 10
        $script:selectionUpdateTimer.Add_Tick({
            $checkedCount = 0
            foreach ($item in $scheduleListView.Items) {
                if ($item.Checked) {
                    $checkedCount++
                }
            }
            
            if ($checkedCount -eq 0) {
                $selectionStatusLabel.Text = "No tasks selected"
                $selectionStatusLabel.ForeColor = [System.Drawing.Color]::Gray
            } elseif ($checkedCount -eq 1) {
                $selectionStatusLabel.Text = "1 task selected"
                $selectionStatusLabel.ForeColor = [System.Drawing.Color]::Blue
            } else {
                $selectionStatusLabel.Text = "$checkedCount tasks selected"
                $selectionStatusLabel.ForeColor = [System.Drawing.Color]::Blue
            }
            
            # Safely stop and dispose timer
            if ($script:selectionUpdateTimer -ne $null) {
                try {
                    $script:selectionUpdateTimer.Stop()
                    $script:selectionUpdateTimer.Dispose()
                } catch {
                    # Ignore disposal errors
                }
                $script:selectionUpdateTimer = $null
            }
        })
        $script:selectionUpdateTimer.Start()
    })

    # Event handler for Run Now button
    $btnRunNow.Add_Click({
        # Get checked items first, then fall back to selected items
        $selectedItems = @()
        
        # First, try to get checked items
        foreach ($item in $scheduleListView.Items) {
            if ($item.Checked) {
                $selectedItems += $item
            }
        }
        
        # If no checked items, try selected items
        if ($selectedItems.Count -eq 0) {
            foreach ($item in $scheduleListView.SelectedItems) {
                $selectedItems += $item
            }
        }
        
        if ($selectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih atau centang tugas yang ingin dijalankan sekarang.", "Tidak Ada Tugas Dipilih", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Confirm before running
        $taskNames = ($selectedItems | ForEach-Object { $_.Text }) -join ", "
        $confirmMessage = if ($selectedItems.Count -eq 1) {
            "Apakah Anda yakin ingin menjalankan tugas '$taskNames' sekarang?"
        } else {
            "Apakah Anda yakin ingin menjalankan $($selectedItems.Count) tugas sekarang?`n`nTugas: $taskNames"
        }
        
        $result = [System.Windows.Forms.MessageBox]::Show($confirmMessage, "Konfirmasi Run Now", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $config = Get-BackupConfig
            $successCount = 0
            $failCount = 0
            $errorMessages = @()
            
            foreach ($selectedItem in $selectedItems) {
                $taskName = $selectedItem.Text
                
                try {
                    $scheduleStatusLabel.Text = "Menjalankan tugas '$taskName'..."
                    $scheduleStatusLabel.Refresh()
                    
                    # Find the task
                    $task = $config.scheduled_tasks | Where-Object { $_.Name -eq $taskName }
                    
                    if (-not $task) {
                        $errorMessages += "Tugas '$taskName' tidak ditemukan dalam konfigurasi"
                        $failCount++
                        continue
                    }

                    # Get backup items for this task (handle both old and new format)
                    $backupItemNames = @()
                    if ($task.BackupItemNames -and $task.BackupItemNames.Count -gt 0) {
                        # New format - array
                        $backupItemNames = $task.BackupItemNames
                    } elseif ($task.BackupItemName) {
                        # Old format - single string
                        $backupItemNames = @($task.BackupItemName)
                    }

                    if ($backupItemNames.Count -eq 0) {
                        $errorMessages += "Tugas '$taskName' tidak memiliki item backup yang dikonfigurasi"
                        $failCount++
                        continue
                    }

                    # Process each backup item in the task
                    $taskSuccess = $true
                    $taskErrors = @()

                    foreach ($backupItemName in $backupItemNames) {
                        # Find the backup item
                        $backupItem = $config.backup_items | Where-Object { $_.Name -eq $backupItemName }
                        
                        if (-not $backupItem) {
                            $taskErrors += "Item backup '$backupItemName' tidak ditemukan"
                            $taskSuccess = $false
                            continue
                        }
                        
                        # Run the backup for this item
                        try {
                            $backupResult = Backup-Item -backupItem $backupItem

                            if (-not $backupResult.Success) {
                                $taskErrors += "Backup '$backupItemName': $($backupResult.ErrorMessage)"
                                $taskSuccess = $false
                            }
                        } catch {
                            $errorMsg = "Backup '$backupItemName': " + $_.Exception.Message
                            $taskErrors += $errorMsg
                            $taskSuccess = $false
                        }
                    }
                    
                    if ($taskSuccess) {
                        $successCount++
                    } else {
                        $failCount++
                        $errorMessages += "Tugas '$taskName': " + ($taskErrors -join "; ")
                    }
                } catch {
                    $failCount++
                    $errorMsg = "Tugas '$taskName': " + $_.Exception.Message
                    $errorMessages += $errorMsg
                }
            }
            
            # Show summary
            $summaryMessage = "Hasil eksekusi:`n"
            $summaryMessage += "Berhasil: $successCount tugas`n"
            $summaryMessage += "Gagal: $failCount tugas"
            
            if ($errorMessages.Count -gt 0) {
                $summaryMessage += "`n`nDetail error:`n" + ($errorMessages -join "`n")
            }
            
            $scheduleStatusLabel.Text = "Selesai: $successCount berhasil, $failCount gagal"
            
            $messageType = if ($failCount -eq 0) { 
                [System.Windows.Forms.MessageBoxIcon]::Information 
            } elseif ($successCount -eq 0) { 
                [System.Windows.Forms.MessageBoxIcon]::Error 
            } else { 
                [System.Windows.Forms.MessageBoxIcon]::Warning 
            }
            
            [System.Windows.Forms.MessageBox]::Show($summaryMessage, "Hasil Run Now", [System.Windows.Forms.MessageBoxButtons]::OK, $messageType)
        }
    })

    # Event handler for Edit Schedule button
    $btnEditSchedule.Add_Click({
        $selectedItems = $scheduleListView.SelectedItems
        if ($selectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih jadwal yang ingin diedit.", "Tidak Ada Jadwal Dipilih", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if ($selectedItems.Count -gt 1) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih hanya satu jadwal untuk diedit.", "Terlalu Banyak Jadwal Dipilih", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $selectedItem = $selectedItems[0]
        $taskName = $selectedItem.Text
        
        # Find the task in configuration
        $config = Get-BackupConfig
        $task = $config.scheduled_tasks | Where-Object { $_.Name -eq $taskName }
        
        if (-not $task) {
            [System.Windows.Forms.MessageBox]::Show("Jadwal '$taskName' tidak ditemukan dalam konfigurasi.", "Jadwal Tidak Ditemukan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        # Show edit form with existing values
        $editForm = New-Object System.Windows.Forms.Form
        $editForm.Text = "Edit Scheduled Task"
        $editForm.Size = New-Object System.Drawing.Size(500, 450)
        $editForm.StartPosition = "CenterScreen"

        # Task Name
        $lblTaskName = New-Object System.Windows.Forms.Label
        $lblTaskName.Text = "Task Name:"
        $lblTaskName.Location = New-Object System.Drawing.Point(20, 20)
        $lblTaskName.Size = New-Object System.Drawing.Size(100, 20)

        $txtTaskName = New-Object System.Windows.Forms.TextBox
        $txtTaskName.Size = New-Object System.Drawing.Size(300, 20)
        $txtTaskName.Location = New-Object System.Drawing.Point(120, 20)
        $txtTaskName.Text = $task.Name

        # Backup Item Selection (Multi-select)
        $lblBackupItem = New-Object System.Windows.Forms.Label
        $lblBackupItem.Text = "Backup Items:"
        $lblBackupItem.Location = New-Object System.Drawing.Point(20, 50)
        $lblBackupItem.Size = New-Object System.Drawing.Size(100, 20)

        $clbBackupItems = New-Object System.Windows.Forms.CheckedListBox
        $clbBackupItems.Size = New-Object System.Drawing.Size(300, 80)
        $clbBackupItems.Location = New-Object System.Drawing.Point(120, 50)
        $clbBackupItems.CheckOnClick = $true

        # Populate backup items with only enabled items
        $config = Get-BackupConfig
        if ($config -and $config.backup_items) {
            foreach ($item in $config.backup_items) {
                if ($item -and $item.Name -and $item.Enabled -eq $true) {
                    $index = $clbBackupItems.Items.Add($item.Name)
                    # Check if this item is in the task
                    if ($task.BackupItemNames -contains $item.Name) {
                        $clbBackupItems.SetItemChecked($index, $true)
                    }
                }
            }
        }

        # Schedule Type
        $lblScheduleType = New-Object System.Windows.Forms.Label
        $lblScheduleType.Text = "Schedule Type:"
        $lblScheduleType.Location = New-Object System.Drawing.Point(20, 140)
        $lblScheduleType.Size = New-Object System.Drawing.Size(100, 20)

        $cboScheduleType = New-Object System.Windows.Forms.ComboBox
        $cboScheduleType.Size = New-Object System.Drawing.Size(300, 20)
        $cboScheduleType.Location = New-Object System.Drawing.Point(120, 140)
        $cboScheduleType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboScheduleType.Items.AddRange(@("Daily", "Weekly", "Monthly")) | Out-Null
        $cboScheduleType.SelectedItem = $task.ScheduleType

        # Schedule Settings Panel
        $pnlScheduleSettings = New-Object System.Windows.Forms.Panel
        $pnlScheduleSettings.Size = New-Object System.Drawing.Size(400, 150)
        $pnlScheduleSettings.Location = New-Object System.Drawing.Point(20, 170)
        $pnlScheduleSettings.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

        # Time picker
        $lblTime = New-Object System.Windows.Forms.Label
        $lblTime.Text = "Time:"
        $lblTime.Location = New-Object System.Drawing.Point(10, 20)
        $lblTime.Size = New-Object System.Drawing.Size(50, 20)

        $dtpTime = New-Object System.Windows.Forms.DateTimePicker
        $dtpTime.Size = New-Object System.Drawing.Size(100, 20)
        $dtpTime.Location = New-Object System.Drawing.Point(70, 20)
        $dtpTime.Format = [System.Windows.Forms.DateTimePickerFormat]::Time
        if ($task.Settings.Time) {
            $dtpTime.Value = [DateTime]::Parse($task.Settings.Time)
        } else {
            $dtpTime.Value = Get-Date -Hour 9 -Minute 0 -Second 0
        }

        # Day of Week (for Weekly)
        $lblDayOfWeek = New-Object System.Windows.Forms.Label
        $lblDayOfWeek.Text = "Day of Week:"
        $lblDayOfWeek.Location = New-Object System.Drawing.Point(10, 50)
        $lblDayOfWeek.Size = New-Object System.Drawing.Size(100, 20)

        $cboDayOfWeek = New-Object System.Windows.Forms.ComboBox
        $cboDayOfWeek.Size = New-Object System.Drawing.Size(150, 20)
        $cboDayOfWeek.Location = New-Object System.Drawing.Point(120, 50)
        $cboDayOfWeek.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboDayOfWeek.Items.AddRange(@([System.DayOfWeek]::Monday, [System.DayOfWeek]::Tuesday, [System.DayOfWeek]::Wednesday, [System.DayOfWeek]::Thursday, [System.DayOfWeek]::Friday, [System.DayOfWeek]::Saturday, [System.DayOfWeek]::Sunday)) | Out-Null
        if ($task.Settings.DayOfWeek) {
            $cboDayOfWeek.SelectedIndex = $task.Settings.DayOfWeek
        } else {
            $cboDayOfWeek.SelectedIndex = 0
        }

        # Day of Month (for Monthly)
        $lblDayOfMonth = New-Object System.Windows.Forms.Label
        $lblDayOfMonth.Text = "Day of Month:"
        $lblDayOfMonth.Location = New-Object System.Drawing.Point(10, 80)
        $lblDayOfMonth.Size = New-Object System.Drawing.Size(100, 20)

        $numDayOfMonth = New-Object System.Windows.Forms.NumericUpDown
        $numDayOfMonth.Size = New-Object System.Drawing.Size(60, 20)
        $numDayOfMonth.Location = New-Object System.Drawing.Point(120, 80)
        $numDayOfMonth.Minimum = 1
        $numDayOfMonth.Maximum = 31
        if ($task.Settings.DayOfMonth) {
            $numDayOfMonth.Value = $task.Settings.DayOfMonth
        } else {
            $numDayOfMonth.Value = 1
        }

        # Enabled checkbox
        $chkEnabled = New-Object System.Windows.Forms.CheckBox
        $chkEnabled.Text = "Enabled"
        $chkEnabled.Location = New-Object System.Drawing.Point(120, 330)
        $chkEnabled.Size = New-Object System.Drawing.Size(100, 20)
        $chkEnabled.Checked = $task.Enabled

        # Add controls to settings panel
        $pnlScheduleSettings.Controls.AddRange(@($lblTime, $dtpTime, $lblDayOfWeek, $cboDayOfWeek, $lblDayOfMonth, $numDayOfMonth))

        # Initially hide day controls
        $lblDayOfWeek.Visible = $false
        $cboDayOfWeek.Visible = $false
        $lblDayOfMonth.Visible = $false
        $numDayOfMonth.Visible = $false

        # Schedule type change handler
        $cboScheduleType.Add_SelectedIndexChanged({
            switch ($cboScheduleType.SelectedItem.ToString()) {
                "Daily" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $false
                    $cboDayOfWeek.Visible = $false
                    $lblDayOfMonth.Visible = $false
                    $numDayOfMonth.Visible = $false
                }
                "Weekly" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $true
                    $cboDayOfWeek.Visible = $true
                    $lblDayOfMonth.Visible = $false
                    $numDayOfMonth.Visible = $false
                }
                "Monthly" {
                    $lblTime.Visible = $true
                    $dtpTime.Visible = $true
                    $lblDayOfWeek.Visible = $false
                    $cboDayOfWeek.Visible = $false
                    $lblDayOfMonth.Visible = $true
                    $numDayOfMonth.Visible = $true
                }
            }
        })

        # Set initial visibility based on current schedule type
        switch ($task.ScheduleType) {
            "Weekly" {
                $lblDayOfWeek.Visible = $true
                $cboDayOfWeek.Visible = $true
            }
            "Monthly" {
                $lblDayOfMonth.Visible = $true
                $numDayOfMonth.Visible = $true
            }
        }

        # Buttons
        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Size = New-Object System.Drawing.Size(75, 30)
        $btnOK.Location = New-Object System.Drawing.Point(200, 380)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
        $btnCancel.Location = New-Object System.Drawing.Point(290, 380)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        # Add controls to form
        $editForm.Controls.AddRange(@($lblTaskName, $txtTaskName, $lblBackupItem, $clbBackupItems, $lblScheduleType, $cboScheduleType, $pnlScheduleSettings, $chkEnabled, $btnOK, $btnCancel))

        # Show form
        $result = $editForm.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            # Get selected backup items
            $selectedBackupItems = @()
            for ($i = 0; $i -lt $clbBackupItems.Items.Count; $i++) {
                if ($clbBackupItems.GetItemChecked($i)) {
                    $selectedBackupItems += $clbBackupItems.Items[$i]
                }
            }

            if ($selectedBackupItems.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Silakan pilih minimal satu item backup untuk dijadwalkan.", "Tidak Ada Item Backup Dipilih", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }

            try {
                # Update the existing task
                $task.Name = $txtTaskName.Text
                $task.BackupItemNames = $selectedBackupItems
                $task.ScheduleType = $cboScheduleType.SelectedItem.ToString()
                $task.Enabled = $chkEnabled.Checked

                # Create schedule settings
                $scheduleSettings = @{
                    Time = $dtpTime.Value.ToString("HH:mm")
                }

                switch ($cboScheduleType.SelectedItem.ToString()) {
                    "Weekly" {
                        $scheduleSettings.DayOfWeek = [int]$cboDayOfWeek.SelectedItem
                    }
                    "Monthly" {
                        $scheduleSettings.DayOfMonth = [int]$numDayOfMonth.Value
                    }
                }

                $task.Settings = $scheduleSettings
                $task.NextRun = Get-NextRunTime -scheduleType $task.ScheduleType -settings $task.Settings

                # Save configuration using ConfigManager
                if (-not $script:ConfigManager) {
                    [System.Windows.Forms.MessageBox]::Show("ConfigManager tidak diinisialisasi.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }

                # Update the task in the configuration using ConfigManager
                $currentTasks = $script:ConfigManager.GetScheduledTasks()
                $updatedTasks = @()

                # Find and update the task
                foreach ($currentTask in $currentTasks) {
                    if ($currentTask.Name -eq $task.Name) {
                        # Update with new values
                        $currentTask.Name = $txtTaskName.Text
                        $currentTask.BackupItemNames = $selectedBackupItems
                        $currentTask.ScheduleType = $cboScheduleType.SelectedItem.ToString()
                        $currentTask.Enabled = $chkEnabled.Checked
                        $currentTask.Settings = $scheduleSettings
                        $currentTask.NextRun = Get-NextRunTime -scheduleType $currentTask.ScheduleType -settings $currentTask.Settings
                    }
                    $updatedTasks += $currentTask
                }

                $script:ConfigManager.Config.scheduled_tasks = $updatedTasks
                $script:ConfigManager.SaveConfiguration()

                # Re-register the Windows scheduled task
                $windowsTaskName = "Backup_$($task.Name)"
                $scriptPath = Join-Path $PSScriptRoot "Run_Scheduled_Backup.ps1"
                Unregister-WindowsScheduledTask -taskName $windowsTaskName
                Register-WindowsScheduledTask -taskName $windowsTaskName -scriptPath $scriptPath -scheduleType $task.ScheduleType -settings $task.Settings

                # Refresh the schedule list
                Refresh-ScheduleList
                
                # Update status
                $scheduleStatusLabel.Text = "Jadwal '$($result.TaskName)' berhasil diperbarui"
                
                [System.Windows.Forms.MessageBox]::Show("Jadwal '$($result.TaskName)' berhasil diperbarui.", "Jadwal Diperbarui", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } catch {
                $errorMsg = "Gagal memperbarui jadwal: " + $_.Exception.Message
                Write-Log $errorMsg "ERROR"
                $scheduleStatusLabel.Text = "Gagal memperbarui jadwal"
                [System.Windows.Forms.MessageBox]::Show($errorMsg, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    })

    # Event handler for Delete Schedule button
    $btnRemoveSchedule.Add_Click({
        $selectedItems = $scheduleListView.SelectedItems
        if ($selectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Silakan pilih jadwal yang ingin dihapus.", "Tidak Ada Jadwal Dipilih", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Confirm deletion
        $taskNames = ($selectedItems | ForEach-Object { $_.Text }) -join ", "
        $confirmMessage = if ($selectedItems.Count -eq 1) {
            "Apakah Anda yakin ingin menghapus jadwal '$taskNames'?"
        } else {
            "Apakah Anda yakin ingin menghapus $($selectedItems.Count) jadwal?`n`nJadwal: $taskNames"
        }
        
        $result = [System.Windows.Forms.MessageBox]::Show($confirmMessage, "Konfirmasi Hapus Jadwal", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $config = Get-BackupConfig
            $deletedCount = 0
            $errorMessages = @()
            
            foreach ($selectedItem in $selectedItems) {
                $taskName = $selectedItem.Text
                
                try {
                    # Find and remove from configuration
                    $taskIndex = -1
                    for ($i = 0; $i -lt $config.scheduled_tasks.Count; $i++) {
                        if ($config.scheduled_tasks[$i].Name -eq $taskName) {
                            $taskIndex = $i
                            break
                        }
                    }
                    
                    if ($taskIndex -ge 0) {
                        # Remove from configuration
                        $config.scheduled_tasks = $config.scheduled_tasks | Where-Object { $_.Name -ne $taskName }
                        
                        # Remove Windows scheduled task
                        try {
                            Unregister-ScheduledTask -TaskName "AutoBackup_$taskName" -Confirm:$false -ErrorAction SilentlyContinue
                        } catch {
                            # Log but don't fail if Windows task doesn't exist
                            Write-Log "Warning: Could not remove Windows scheduled task for '$taskName': $($_.Exception.Message)" "WARNING"
                        }
                        
                        $deletedCount++
                    } else {
                        $errorMessages += "Jadwal '$taskName' tidak ditemukan dalam konfigurasi"
                    }
                } catch {
                    $errorMessages += "Gagal menghapus jadwal '$taskName': $($_.Exception.Message)"
                }
            }
            
            if ($deletedCount -gt 0) {
                # Save configuration using ConfigManager
                if (-not $script:ConfigManager) {
                    [System.Windows.Forms.MessageBox]::Show("ConfigManager tidak diinisialisasi.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }

                # Update tasks using ConfigManager
                $script:ConfigManager.Config.scheduled_tasks = $config.scheduled_tasks
                $script:ConfigManager.SaveConfiguration()
                
                # Refresh the schedule list
                Refresh-ScheduleList
            }
            
            # Show result
            if ($errorMessages.Count -eq 0) {
                $scheduleStatusLabel.Text = "$deletedCount jadwal berhasil dihapus"
                [System.Windows.Forms.MessageBox]::Show("$deletedCount jadwal berhasil dihapus.", "Jadwal Dihapus", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                $scheduleStatusLabel.Text = "Beberapa jadwal gagal dihapus"
                $errorMsg = "Berhasil menghapus: $deletedCount jadwal`n`nError:`n" + ($errorMessages -join "`n")
                [System.Windows.Forms.MessageBox]::Show($errorMsg, "Hasil Hapus Jadwal", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
    })

    # Add controls to schedule tab (with null checks)
    $scheduleControls = @($scheduleListView, $btnAddSchedule, $btnEditSchedule, $btnRemoveSchedule, $btnEnableDisable, $btnRunNow, $selectionStatusLabel, $scheduleStatusLabel)
    $scheduleControls = $scheduleControls | Where-Object { $_ -ne $null }
    if ($scheduleControls.Count -gt 0) {
        $scheduleTab.Controls.AddRange($scheduleControls)
    }

    # Initial refresh of schedule list
    Refresh-ScheduleList

    # Add controls to tabs (with null checks)
    $backupControls = @($listView, $btnAdd, $btnEdit, $btnRemove, $btnBackup, $btnRefresh)
    $backupControls = $backupControls | Where-Object { $_ -ne $null }
    if ($backupControls.Count -gt 0) {
        $backupTab.Controls.AddRange($backupControls)
    }

    $settingsControls = @($lblClientId, $txtClientId, $lblClientSecret, $txtClientSecret, $btnConnect, $btnSaveSettings)
    $settingsControls = $settingsControls | Where-Object { $_ -ne $null }
    if ($settingsControls.Count -gt 0) {
        $settingsTab.Controls.AddRange($settingsControls)
    }

    $tabControls = @($backupTab, $settingsTab, $scheduleTab)
    $tabControls = $tabControls | Where-Object { $_ -ne $null }
    if ($tabControls.Count -gt 0) {
        $tabControl.Controls.AddRange($tabControls)
    }

    # Add controls to main form (with null check)
    if ($tabControl -ne $null) {
        $mainForm.Controls.Add($tabControl)
    }

    # Add status label and progress bar to main form
    if ($statusLabel -ne $null) {
        $mainForm.Controls.Add($statusLabel)
    }
    if ($progressBar -ne $null) {
        $mainForm.Controls.Add($progressBar)
    }

    # Initial load
    Refresh-ListView

    # Show form
    Write-Host "DEBUG: About to show form with ShowDialog()" -ForegroundColor Yellow
    $mainForm.Add_Shown({ $mainForm.Activate() })
    Write-Host "DEBUG: Calling ShowDialog()..." -ForegroundColor Yellow
    [void]$mainForm.ShowDialog()
    Write-Host "DEBUG: ShowDialog() returned" -ForegroundColor Yellow
}

# Main execution
function main {
    Write-Host "DEBUG: Main function started" -ForegroundColor Green
    try {
        Write-Host "DEBUG: Initializing ConfigManager..." -ForegroundColor Green
        # Initialize ConfigManager with correct base path
        $script:ConfigManager = [ConfigManager]::new($PSScriptRoot)
        Write-Log "ConfigManager initialized successfully" "INFO"

        Write-Host "DEBUG: Initializing AuthManager..." -ForegroundColor Green
        # Initialize AuthManager
        $script:AuthManager = New-GoogleDriveAuthManager -ConfigManager $script:ConfigManager
        Write-Log "AuthManager initialized successfully" "INFO"

        # Setup logging system for AuthManager
        $script:AuthManager.SetLoggingSystem($script:ConfigManager)

        Write-Host "DEBUG: Loading configuration..." -ForegroundColor Green
        # Load initial configuration
        $config = Get-BackupConfig
        if (-not $config) {
            Write-Log "Failed to load initial configuration" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("Failed to load configuration. Check logs for details.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        Write-Log "Application initialized successfully" "INFO"
        Write-Log "Backup items loaded: $($config.backup_items.Count)" "INFO"
        Write-Log "Scheduled tasks loaded: $($config.scheduled_tasks.Count)" "INFO"
        Write-Log "Config file: $($script:ConfigManager.GetConfigFilePath())" "INFO"

        Write-Host "DEBUG: About to call Show-MainForm..." -ForegroundColor Green
        # Tampilkan GUI
        Show-MainForm
        Write-Host "DEBUG: Show-MainForm returned" -ForegroundColor Green
    }
    catch {
        $errorMsg = "Failed to initialize application: " + $_.Exception.Message
        Write-Host "DEBUG: Exception caught in main: $errorMsg" -ForegroundColor Red
        Write-Host "DEBUG: Exception details: $($_.Exception)" -ForegroundColor Red
        Write-Log $errorMsg "ERROR"
        [System.Windows.Forms.MessageBox]::Show($errorMsg, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Jalankan aplikasi
main