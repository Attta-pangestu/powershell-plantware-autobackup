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

# Variabel global
$script:ConfigFile = "config\auto_backup_config.json"
$script:TokenFile = "config\token.json"
$script:LogFile = "logs\backup_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:BackupItems = @()
$script:SelectedItems = @()

# Fungsi untuk menulis log
function Write-Log {
    param([string]$message, [string]$level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$level] $message"

    # Tulis ke file
    $logMessage | Out-File -FilePath $script:LogFile -Append

    # Tulis ke console jika debug mode
    if ($script:DebugMode) {
        Write-Host $logMessage
    }
}

# Fungsi untuk membaca konfigurasi
function Get-BackupConfig {
    if (-not (Test-Path $script:ConfigFile)) {
        Write-Log "File config tidak ditemukan, membuat default..."
        $defaultConfig = @{
            google_drive = @{
                token_file = "token.json"
                scopes = @("https://www.googleapis.com/auth/drive.file")
                client_id = ""
                client_secret = ""
            }
            backup_items = @()
            scheduled_tasks = @()
            settings = @{
                auto_scan_enabled = $true
                scan_interval_minutes = 30
                max_backup_history = 100
                compression_level = 6
            }
        }
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:ConfigFile -Encoding UTF8
    }

    try {
        $config = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
        $script:BackupItems = $config.backup_items
        Write-Log "Config berhasil dimuat"
        return $config
    }
    catch {
        Write-Log "Gagal membaca config: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Fungsi untuk menyimpan konfigurasi
function Save-BackupConfig {
    param([object]$config)

    try {
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:ConfigFile -Encoding UTF8
        Write-Log "Config berhasil disimpan"
        return $true
    }
    catch {
        Write-Log "Gagal menyimpan config: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Fungsi untuk mengotentikasi Google Drive
function Connect-GoogleDrive {
    param([string]$clientId, [string]$clientSecret)

    # Simpan client credentials ke config
    $config = Get-BackupConfig
    $config.google_drive.client_id = $clientId
    $config.google_drive.client_secret = $clientSecret
    Save-BackupConfig $config

    # Cek token yang sudah ada
    if (Test-Path $script:TokenFile) {
        try {
            $tokenData = Get-Content $script:TokenFile -Raw | ConvertFrom-Json

            # Cek apakah token masih valid
            if ($tokenData.access_token -and $tokenData.expiry) {
                $expiryTime = [datetime]$tokenData.expiry
                if ($expiryTime -gt (Get-Date).AddMinutes(5)) {
                    Write-Log "Token masih valid, menggunakan token yang ada"
                    return $true
                }
            }

            # Coba refresh token jika ada refresh_token
            if ($tokenData.refresh_token) {
                Write-Log "Token expired, mencoba refresh token..."
                $refreshResult = Refresh-GoogleDriveToken -refreshToken $tokenData.refresh_token -clientId $clientId -clientSecret $clientSecret
                if ($refreshResult.Success) {
                    return $true
                }
            }
        }
        catch {
            Write-Log "Token tidak valid: $($_.Exception.Message)" "WARN"
        }
    }

    Write-Log "Token tidak ditemukan atau tidak valid. Silakan setup token terlebih dahulu." "ERROR"
    return $false
}

# Fungsi untuk refresh token
function Refresh-GoogleDriveToken {
    param([string]$refreshToken, [string]$clientId, [string]$clientSecret)

    try {
        $tokenEndpoint = "https://oauth2.googleapis.com/token"
        $body = @{
            client_id = $clientId
            client_secret = $clientSecret
            refresh_token = $refreshToken
            grant_type = "refresh_token"
        }

        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"

        # Update token file dengan token baru
        $currentToken = Get-Content $script:TokenFile -Raw | ConvertFrom-Json
        $currentToken.access_token = $response.access_token
        $currentToken.expires_in = $response.expires_in
        $currentToken.expiry = (Get-Date).AddSeconds($response.expires_in).ToString("o")

        $currentToken | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:TokenFile -Encoding UTF8

        Write-Log "Token berhasil di-refresh"
        return @{ Success = $true }
    }
    catch {
        Write-Log "Gagal refresh token: $($_.Exception.Message)" "ERROR"
        return @{ Success = $false; ErrorMessage = $_.Exception.Message }
    }
}

# Fungsi untuk upload file ke Google Drive
function Upload-ToGoogleDrive {
    param([string]$filePath, [string]$fileName)

    Write-Log "Upload $fileName ke Google Drive..." "INFO"

    try {
        # Baca token yang ada
        if (-not (Test-Path $script:TokenFile)) {
            Write-Log "Token file tidak ditemukan" "ERROR"
            return @{ Success = $false; ErrorMessage = "Token tidak ditemukan" }
        }

        $tokenData = Get-Content $script:TokenFile -Raw | ConvertFrom-Json

        # Cek token expiry
        if ($tokenData.expiry) {
            $expiryTime = [datetime]$tokenData.expiry
            if ($expiryTime -le (Get-Date).AddMinutes(5)) {
                Write-Log "Token expired, mencoba refresh..." "WARN"
                $config = Get-BackupConfig
                $refreshResult = Refresh-GoogleDriveToken -refreshToken $tokenData.refresh_token -clientId $config.google_drive.client_id -clientSecret $config.google_drive.client_secret

                if (-not $refreshResult.Success) {
                    return @{ Success = $false; ErrorMessage = "Gagal refresh token" }
                }

                # Baca token yang sudah di-refresh
                $tokenData = Get-Content $script:TokenFile -Raw | ConvertFrom-Json
            }
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
            "Authorization" = "Bearer $($tokenData.access_token)"
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
        # Cek apakah path ada
        if (-not (Test-Path $backupItem.SourcePath)) {
            Write-Log "Path tidak ditemukan: $($backupItem.SourcePath)" "ERROR"
            return @{
                Success = $false
                ErrorMessage = "Path tidak ditemukan"
            }
        }

        # Upload langsung tanpa melalui temp folder
        Write-Log "Memproses backup untuk: $($backupItem.Name)" "INFO"

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
            Write-Log "Gagal memproses backup: $($_.Exception.Message)" "ERROR"
            return @{
                Success = $false
                ErrorMessage = "Gagal memproses backup: $($_.Exception.Message)"
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
    catch {
        Write-Log "Backup $($backupItem.Name) gagal: $($_.Exception.Message)" "ERROR"
        return @{
            Success = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Fungsi untuk menambah item backup
function Add-BackupItem {
    param([string]$name, [string]$path, [string]$description = "")

    $newItem = @{
        Name = $name
        SourcePath = $path
        Description = $description
        IsFolder = Test-Path $path -PathType Container
        Enabled = $true
        LastBackup = ""
        CompressionLevel = 6
        GDriveSubfolder = ""
        CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    $config = Get-BackupConfig
    $config.backup_items += $newItem
    Save-BackupConfig $config

    Write-Log "Item backup '$name' berhasil ditambahkan" "INFO"
    return $newItem
}

# Fungsi untuk task scheduling
function New-ScheduledTask {
    param(
        [string]$name,
        [string]$backupItemName,
        [string]$scheduleType,  # "Daily", "Weekly", "Monthly"
        [hashtable]$scheduleSettings
    )

    $newTask = @{
        Name = $name
        BackupItemName = $backupItemName
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

            # Find backup item
            $backupItem = $config.backup_items | Where-Object { $_.Name -eq $task.BackupItemName }
            if (-not $backupItem) {
                Write-Log "Backup item '$($task.BackupItemName)' not found for task '$($task.Name)'" "WARNING"
                continue
            }

            # Perform backup
            $result = Backup-Item -backupItem $backupItem

            # Update task info
            $task.LastRun = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $task.NextRun = Get-NextRunTime -scheduleType $task.ScheduleType -settings $task.Settings

            if ($result.Success) {
                Write-Log "Scheduled backup '$($task.Name)' completed successfully" "INFO"

                # Update last backup time in backup item
                $itemInConfig = $config.backup_items | Where-Object { $_.Name -eq $backupItem.Name }
                if ($itemInConfig) {
                    $itemInConfig.LastBackup = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
            else {
                Write-Log "Scheduled backup '$($task.Name)' failed: $($result.ErrorMessage)" "ERROR"
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
    # Buat form utama
    $mainForm = New-Object System.Windows.Forms.Form
    $mainForm.Text = "Simple Backup GUI - Google Drive"
    $mainForm.Size = New-Object System.Drawing.Size(800, 600)
    $mainForm.StartPosition = "CenterScreen"
    $mainForm.FormBorderStyle = "FixedSingle"
    $mainForm.MaximizeBox = $false

    # Load config awal
    $config = Get-BackupConfig

    # Tab Control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(780, 520)
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)

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
    $listView.Columns.Add("Path", 300) | Out-Null
    $listView.Columns.Add("Tipe", 80) | Out-Null
    $listView.Columns.Add("Status", 100) | Out-Null
    $listView.Columns.Add("Terakhir Backup", 120) | Out-Null

    # Refresh list view
    function Refresh-ListView {
        $listView.Items.Clear()
        foreach ($item in $script:BackupItems) {
            $listItem = New-Object System.Windows.Forms.ListViewItem
            $listItem.Text = $item.Name
            $listItem.SubItems.Add($item.SourcePath) | Out-Null
            $listItem.SubItems.Add($(if ($item.IsFolder) { "Folder" } else { "File" })) | Out-Null
            $listItem.SubItems.Add($(if ($item.Enabled) { "Aktif" } else { "Non-aktif" })) | Out-Null
            $listItem.SubItems.Add($item.LastBackup) | Out-Null
            $listItem.Tag = $item
            $listView.Items.Add($listItem) | Out-Null
        }
    }

    # Tombol-tombol
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Tambah Item"
    $btnAdd.Size = New-Object System.Drawing.Size(100, 30)
    $btnAdd.Location = New-Object System.Drawing.Point(10, 370)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Hapus Item"
    $btnRemove.Size = New-Object System.Drawing.Size(100, 30)
    $btnRemove.Location = New-Object System.Drawing.Point(120, 370)

    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.Text = "Backup Selected"
    $btnBackup.Size = New-Object System.Drawing.Size(120, 30)
    $btnBackup.Location = New-Object System.Drawing.Point(230, 370)
    $btnBackup.BackColor = [System.Drawing.Color]::LightGreen

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
    $btnRefresh.Location = New-Object System.Drawing.Point(360, 370)

    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Ready"
    $statusLabel.Size = New-Object System.Drawing.Size(750, 20)
    $statusLabel.Location = New-Object System.Drawing.Point(10, 420)
    $statusLabel.ForeColor = [System.Drawing.Color]::Green

    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Size = New-Object System.Drawing.Size(750, 20)
    $progressBar.Location = New-Object System.Drawing.Point(10, 450)
    $progressBar.Visible = $false

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

    # Event handlers
    $btnAdd.Add_Click({
        # Form untuk menambah item baru
        $addForm = New-Object System.Windows.Forms.Form
        $addForm.Text = "Tambah Backup Item"
        $addForm.Size = New-Object System.Drawing.Size(400, 300)
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

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text = "OK"
        $btnOK.Size = New-Object System.Drawing.Size(75, 30)
        $btnOK.Location = New-Object System.Drawing.Point(220, 200)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
        $btnCancel.Location = New-Object System.Drawing.Point(305, 200)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $addForm.Controls.AddRange(@($lblName, $txtName, $lblPath, $txtPath, $btnBrowse, $lblDesc, $txtDesc, $btnOK, $btnCancel))

        $btnBrowse.Add_Click({
            $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
            if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtPath.Text = $folderBrowser.SelectedPath
            }
        })

        if ($addForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($txtName.Text -and $txtPath.Text) {
                Add-BackupItem -name $txtName.Text -path $txtPath.Text -description $txtDesc.Text
                Refresh-ListView
                $statusLabel.Text = "Item '$($txtName.Text)' berhasil ditambahkan"
            }
        }
    })

    $btnRemove.Add_Click({
        if ($listView.SelectedItems.Count -gt 0) {
            $selectedItem = $listView.SelectedItems[0]
            $itemToRemove = $selectedItem.Tag

            $result = [System.Windows.Forms.MessageBox]::Show(
                "Hapus item '$($itemToRemove.Name)'?",
                "Konfirmasi",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $config = Get-BackupConfig
                $config.backup_items = $config.backup_items | Where-Object { $_.Name -ne $itemToRemove.Name }
                Save-BackupConfig $config
                Refresh-ListView
                $statusLabel.Text = "Item '$($itemToRemove.Name)' berhasil dihapus"
            }
        }
    })

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
        $config = Get-BackupConfig
        Refresh-ListView
        $statusLabel.Text = "List refreshed"
    })

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

    # Schedule status label
    $scheduleStatusLabel = New-Object System.Windows.Forms.Label
    $scheduleStatusLabel.Text = "Schedule tasks will appear here"
    $scheduleStatusLabel.Size = New-Object System.Drawing.Size(750, 20)
    $scheduleStatusLabel.Location = New-Object System.Drawing.Point(10, 360)

    # Function to refresh schedule list
    function Refresh-ScheduleList {
        $scheduleListView.Items.Clear()
        $config = Get-BackupConfig

        foreach ($task in $config.scheduled_tasks) {
            $item = New-Object System.Windows.Forms.ListViewItem
            $item.Text = $task.Name
            $item.SubItems.Add($task.BackupItemName) | Out-Null

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

        $scheduleStatusLabel.Text = "Total scheduled tasks: $($config.scheduled_tasks.Count)"
    }

    # Add Schedule button click
    $btnAddSchedule.Add_Click({
        # Show add schedule dialog
        $scheduleForm = New-Object System.Windows.Forms.Form
        $scheduleForm.Text = "Add Scheduled Task"
        $scheduleForm.Size = New-Object System.Drawing.Size(500, 400)
        $scheduleForm.StartPosition = "CenterScreen"

        # Task Name
        $lblTaskName = New-Object System.Windows.Forms.Label
        $lblTaskName.Text = "Task Name:"
        $lblTaskName.Location = New-Object System.Drawing.Point(20, 20)
        $lblTaskName.Size = New-Object System.Drawing.Size(100, 20)

        $txtTaskName = New-Object System.Windows.Forms.TextBox
        $txtTaskName.Size = New-Object System.Drawing.Size(300, 20)
        $txtTaskName.Location = New-Object System.Drawing.Point(120, 20)

        # Backup Item Selection
        $lblBackupItem = New-Object System.Windows.Forms.Label
        $lblBackupItem.Text = "Backup Item:"
        $lblBackupItem.Location = New-Object System.Drawing.Point(20, 50)
        $lblBackupItem.Size = New-Object System.Drawing.Size(100, 20)

        $cboBackupItem = New-Object System.Windows.Forms.ComboBox
        $cboBackupItem.Size = New-Object System.Drawing.Size(300, 20)
        $cboBackupItem.Location = New-Object System.Drawing.Point(120, 50)
        $cboBackupItem.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

        # Populate backup items
        $config = Get-BackupConfig
        foreach ($item in $config.backup_items) {
            $cboBackupItem.Items.Add($item.Name) | Out-Null
        }

        # Schedule Type
        $lblScheduleType = New-Object System.Windows.Forms.Label
        $lblScheduleType.Text = "Schedule Type:"
        $lblScheduleType.Location = New-Object System.Drawing.Point(20, 80)
        $lblScheduleType.Size = New-Object System.Drawing.Size(100, 20)

        $cboScheduleType = New-Object System.Windows.Forms.ComboBox
        $cboScheduleType.Size = New-Object System.Drawing.Size(300, 20)
        $cboScheduleType.Location = New-Object System.Drawing.Point(120, 80)
        $cboScheduleType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cboScheduleType.Items.AddRange(@("Daily", "Weekly", "Monthly")) | Out-Null

        # Schedule Settings Panel
        $pnlScheduleSettings = New-Object System.Windows.Forms.Panel
        $pnlScheduleSettings.Size = New-Object System.Drawing.Size(400, 150)
        $pnlScheduleSettings.Location = New-Object System.Drawing.Point(20, 110)
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
        $btnOK.Location = New-Object System.Drawing.Point(200, 330)
        $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
        $btnCancel.Location = New-Object System.Drawing.Point(290, 330)
        $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        # Add controls to form
        $scheduleForm.Controls.AddRange(@($lblTaskName, $txtTaskName, $lblBackupItem, $cboBackupItem, $lblScheduleType, $cboScheduleType, $pnlScheduleSettings, $btnOK, $btnCancel))

        # Show form
        $result = $scheduleForm.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
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

            $newTask = New-ScheduledTask -name $txtTaskName.Text -backupItemName $cboBackupItem.SelectedItem.ToString() -scheduleType $cboScheduleType.SelectedItem.ToString() -scheduleSettings $scheduleSettings

            # Add to config
            $config.scheduled_tasks += $newTask
            Save-BackupConfig $config

            # Register Windows scheduled task
            $taskName = "Backup_$($newTask.Name)"
            $scriptPath = Join-Path $scriptPath "Run_Scheduled_Backup.ps1"
            Register-WindowsScheduledTask -taskName $taskName -scriptPath $scriptPath -scheduleType $newTask.ScheduleType -settings $newTask.Settings

            Refresh-ScheduleList
            $scheduleStatusLabel.Text = "Scheduled task '$($newTask.Name)' added successfully"
            $scheduleStatusLabel.ForeColor = [System.Drawing.Color]::Green
        }
    })

    # Add controls to schedule tab
    $scheduleTab.Controls.AddRange(@($scheduleListView, $btnAddSchedule, $btnEditSchedule, $btnRemoveSchedule, $btnEnableDisable, $btnRunNow, $scheduleStatusLabel))

    # Initial refresh of schedule list
    Refresh-ScheduleList

    # Add controls to tabs
    $backupTab.Controls.AddRange(@($listView, $btnAdd, $btnRemove, $btnBackup, $btnRefresh, $statusLabel, $progressBar))
    $settingsTab.Controls.AddRange(@($lblClientId, $txtClientId, $lblClientSecret, $txtClientSecret, $btnConnect, $btnSaveSettings))

    $tabControl.Controls.AddRange(@($backupTab, $settingsTab, $scheduleTab))

    # Add controls to main form
    $mainForm.Controls.Add($tabControl)

    # Initial load
    Refresh-ListView

    # Show form
    $mainForm.Add_Shown({ $mainForm.Activate() })
    [void]$mainForm.ShowDialog()
}

# Main execution
function main {
    # Buat direktori yang diperlukan
    $directories = @("config", "logs", "temp")
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Tampilkan GUI
    Show-MainForm
}

# Jalankan aplikasi
main