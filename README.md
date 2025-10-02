# PowerShell Plantware Auto Backup

This application provides automated backup functionality for files and folders to Google Drive, with the option to also push code changes to Git repositories.

## Features

- GUI for managing backup items
- Scheduled backups
- Google Drive integration
- Git repository push functionality
- Support for both Google Drive and Git backup destinations

## Setup

1. Install the required modules and dependencies
2. Configure Google Drive API credentials (for Google Drive backups)
3. Set up Git repository with proper authentication (for Git backups)

## Usage

### Adding a Google Drive Backup Item
- Name: Choose a name for your backup item
- Path: Select the file or folder to backup
- Destination: Select "GoogleDrive"
- The item will be backed up to Google Drive

### Adding a Git Backup Item
- Name: Choose a name for your backup item
- Path: Select the directory containing the Git repository
- Destination: Select "Git"
- The directory will be committed and pushed to its remote repository

### Scheduling Backups
- Use the Schedule tab to create scheduled tasks
- Tasks can run either Google Drive backups or Git pushes on a schedule
- Supports Daily, Weekly, and Monthly schedules

## Git Backup Functionality

Git backup items will:
1. Add all changes in the specified directory
2. Commit with an auto-generated message
3. Pull latest changes (if needed)
4. Push to the remote repository

## Contributing

Please feel free to contribute to this project by submitting issues or pull requests.

## License

[Add your license information here]