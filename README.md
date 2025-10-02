# Simple Backup GUI - Google Drive

GUI sederhana untuk melakukan backup file dan folder ke Google Drive.

## Fitur

- ✅ **Manajemen Item Backup**: Tambah, hapus, dan kelola item backup
- ✅ **Pilihan Multiple**: Pilih beberapa item untuk backup sekaligus
- ✅ **Google Drive Integration**: Upload backup langsung ke Google Drive
- ✅ **Auto ZIP**: File/folder otomatis dikompres sebelum upload
- ✅ **Progress Tracking**: Real-time progress untuk backup process
- ✅ **Logging**: Semua aktivitas tersimpan di log file
- ✅ **Settings Management**: Konfigurasi Google Drive credentials

## Cara Menggunakan

### 1. Menjalankan Aplikasi

```powershell
cd "d:/Gawean Rebinmas/App_Auto_Backup/Plantware_Auto_Backup/PowerShell_Pure/refactor_powershell_backup"
.\SimpleBackupGUI.ps1
```

### 2. Setup Google Drive

1. Buka tab **Settings**
2. Masukkan **Client ID** dan **Client Secret** dari Google Cloud Console
3. Klik **Connect to Google Drive**
4. Klik **Save Settings**

### 3. Menambah Item Backup

1. Buka tab **Backup Items**
2. Klik **Tambah Item**
3. Isi form:
   - **Nama**: Nama untuk item backup
   - **Path**: Path file/folder yang akan dibackup (klik Browse untuk memilih folder)
   - **Deskripsi**: Deskripsi opsional
4. Klik **OK**

### 4. Melakukan Backup

1. Centang item-item yang ingin dibackup
2. Klik **Backup Selected**
3. Tunggu proses backup selesai
4. Cek status di bagian bawah form

## Struktur Folder

```
refactor_powershell_backup/
├── SimpleBackupGUI.ps1          # File utama aplikasi
├── config/                      # Folder konfigurasi
│   ├── auto_backup_config.json  # Konfigurasi backup items
│   └── token.json              # Google Drive token
├── logs/                        # Folder log files
├── temp/                        # Folder temporary files
└── README.md                    # Dokumentasi ini
```

## Konfigurasi Google Drive

### Membuat Google Cloud Project

1. Buka [Google Cloud Console](https://console.cloud.google.com/)
2. Create new project atau pilih existing project
3. Enable **Google Drive API**
4. Create OAuth2 Client ID:
   - Application type: **Desktop app**
   - Download JSON file

### Mengambil Credentials

Dari JSON file yang didownload, cari:
- **Client ID**: Bagian `"client_id"`
- **Client Secret**: Bagian `"client_secret"`

## Contoh Penggunaan

### Menambah Item Backup
1. Klik "Tambah Item"
2. Nama: "Documents"
3. Path: "C:\Users\Username\Documents" (atau klik Browse)
4. Deskripsi: "Backup dokumen penting"
5. Klik OK

### Backup Multiple Items
1. Centang beberapa item di list
2. Klik "Backup Selected"
3. Tunggu hingga proses selesai

## Fitur Tambahan

### Logging
- Semua aktivitas tersimpan di `logs/backup_YYYY-MM-DD.log`
- Support multiple log levels: INFO, WARNING, ERROR

### Auto ZIP
- File/folder otomatis dikompres ke format ZIP
- Nama file: `NamaItem_YYYYMMDD_HHMMSS.zip`

### Progress Tracking
- Real-time progress bar
- Status messages untuk setiap operasi

## Troubleshooting

### Common Issues

1. **File tidak ditemukan**: Pastikan path yang dimasukkan benar
2. **Google Drive connection failed**: Cek Client ID dan Client Secret
3. **Permission denied**: Pastikan punya akses ke path yang dipilih

### Debug Mode
Untuk melihat detail log, tambahkan di awal script:
```powershell
$script:DebugMode = $true
```

## Requirements

- Windows PowerShell 5.1+
- .NET Framework 4.5+
- Internet connection untuk Google Drive
- Google Cloud Project dengan Drive API enabled

## Catatan

- Aplikasi ini menggunakan mode demo untuk upload Google Drive
- Untuk implementasi nyata, perlu OAuth2 flow yang lengkap
- File temporary otomatis dihapus setelah upload
- Support file dan folder backup

---

**Created by Plantware Auto Backup Team**