# Simple script to check enabled backup items

$config = Get-Content "config\auto_backup_config.json" -Raw | ConvertFrom-Json
$enabled = $config.backup_items | Where-Object { $_.Enabled -eq $true }

Write-Host "Enabled items: $($enabled.Count)"
foreach ($item in $enabled) {
    Write-Host "- $($item.Name): $($item.Enabled)"
}