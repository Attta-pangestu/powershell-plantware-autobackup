# Script untuk melakukan git push dari sistem backup
# This script pushes the current codebase to git

Write-Host "=== Running Git Push ===" -ForegroundColor Cyan
Write-Host "Pushing current codebase to git repository..." -ForegroundColor Yellow

# Set working directory to the script's directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptPath

Write-Host "Working directory: $(Get-Location)" -ForegroundColor Green

# Function to check if git is available
function Test-GitAvailable {
    try {
        $gitVersion = & git --version 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        Write-Host "Git is not installed or not in PATH" -ForegroundColor Red
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
        Write-Host "Not a git repository or git error" -ForegroundColor Yellow
        return $false
    }
}

# Function to get current git branch
function Get-GitBranch {
    try {
        $branch = & git branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $branch
        }
        return $null
    }
    catch {
        return $null
    }
}

# Function to add, commit, and push changes
function Push-GitChanges {
    param(
        [string]$CommitMessage = "Auto-commit from backup system $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )
    
    try {
        Write-Host "Adding all changes to git..." -ForegroundColor Cyan
        $result = & git add . 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error adding files: $result" -ForegroundColor Red
            return $false
        }
        
        Write-Host "Committing changes: $CommitMessage" -ForegroundColor Cyan
        $result = & git commit -m $CommitMessage 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Changes committed successfully" -ForegroundColor Green
        }
        elseif ($result -like "*nothing to commit*") {
            Write-Host "No changes to commit" -ForegroundColor Yellow
            # This is OK, continue to push
        }
        else {
            Write-Host "Error committing: $result" -ForegroundColor Red
            return $false
        }
        
        Write-Host "Pushing changes to remote repository..." -ForegroundColor Cyan
        $branch = Get-GitBranch
        if (-not $branch) {
            $branch = "main"  # Default to main if we can't determine current branch
        }
        
        $result = & git push origin $branch 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully pushed changes to $branch" -ForegroundColor Green
            return $true
        }
        else {
            if ($result -like "*Authentication*" -or $result -like "*auth*" -or $result -like "*403*" -or $result -like "*401*") {
                Write-Host "Authentication failed. Please check your git credentials." -ForegroundColor Red
            }
            elseif ($result -like "*Updates were rejected*") {
                Write-Host "Updates were rejected. You may need to pull first." -ForegroundColor Red
                Write-Host "Attempting pull before push..." -ForegroundColor Yellow
                $pullResult = & git pull origin $branch --no-rebase 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Pulled successfully, trying push again..." -ForegroundColor Cyan
                    $result = & git push origin $branch 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Successfully pushed changes after pull" -ForegroundColor Green
                        return $true
                    }
                    else {
                        Write-Host "Push failed after pull: $result" -ForegroundColor Red
                        return $false
                    }
                }
                else {
                    Write-Host "Pull also failed: $pullResult" -ForegroundColor Red
                    return $false
                }
            }
            else {
                Write-Host "Error pushing changes: $result" -ForegroundColor Red
            }
            return $false
        }
    }
    catch {
        Write-Host "Error in git operations: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
try {
    # Check if git is available
    if (-not (Test-GitAvailable)) {
        Write-Host "Git is not available. Please install Git and ensure it's in your PATH." -ForegroundColor Red
        exit 1
    }
    
    # Check if this is a git repository
    if (-not (Test-IsGitRepository)) {
        Write-Host "This directory is not a git repository." -ForegroundColor Red
        exit 1
    }
    
    # Perform git operations
    $result = Push-GitChanges -CommitMessage "Scheduled code sync $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    if ($result) {
        Write-Host "=== Git Push Completed Successfully ===" -ForegroundColor Green
    }
    else {
        Write-Host "=== Git Push Failed ===" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Error running git push: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}