# Program Files Structure

This directory contains all static configuration files, logs, and application data.

## Folder Structure

### `auth/`
- Authentication and credential files
- `client_secret.json` - Google OAuth client secrets
- `client_secrets.json` - Alternative Google OAuth credentials
- `ptrj-backup-services-account.json` - Google Service Account credentials
- `token.json` - OAuth2 access tokens
- `token.json.backup` - Backup of OAuth2 tokens

### `config/`
- Application configuration files
- `auto_backup_config.json` - Main backup configuration with schedules and settings

### `history/`
- Backup history and tracking files
- `backup_history_*.json` - Individual backup history files for each database
- `changes.log` - Application change history and development notes

### `logs/`
- Application log files
- `auto_backup.log` - Main application log
- `auto_backup_gui.log` - GUI-specific logs
- `direct_gdrive_uploader.log` - Google Drive upload logs
- `ftp_uploader.log` - FTP upload logs
- `token_manager.log` - Token management logs
- `ftp_health.log` - FTP health monitoring logs
- `token_auto_update.log` - Token auto-update service logs
- `application_service_manager.log` - Application service manager logs

### `temp/`
- Temporary files (cleaned up automatically)
- This directory is periodically cleaned to prevent storage bloat

## File Organization

- **Configuration**: Centralized in `config/` for easy backup and restore
- **Authentication**: Securely stored in `auth/` with restricted access
- **History**: Individual backup history files organized by database name
- **Logs**: All application logs in one location for debugging and monitoring
- **Temporary**: Short-lived files that are automatically cleaned up

## Security Notes

- Files in `auth/` contain sensitive credentials and should be backed up securely
- Token files are automatically rotated and backed up
- Temporary files are regularly cleaned to prevent storage issues