# Health-InfraOps Git Push Script for PowerShell

param(
    [string]$Message = "",
    [string]$Branch = "main",
    [switch]$NoVerify,
    [switch]$Force,
    [switch]$SetupOnly
)

# Colors
$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $($args[0])" -ForegroundColor Blue }
function Write-Success { Write-Host "[SUCCESS] $($args[0])" -ForegroundColor Green }
function Write-Warning { Write-Host "[WARNING] $($args[0])" -ForegroundColor Yellow }
function Write-Error { Write-Host "[ERROR] $($args[0])" -ForegroundColor Red }

function Show-Help {
    Write-Host "Health-InfraOps Git Push Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\git-push.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Message MSG       Commit message"
    Write-Host "  -Branch BRANCH     Target branch (default: main)"
    Write-Host "  -NoVerify         Skip pre-commit checks"
    Write-Host "  -Force            Force push"
    Write-Host "  -SetupOnly        Only setup repository, don't push"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\git-push.ps1 -Message 'Add new monitoring features'"
    Write-Host "  .\git-push.ps1 -Message 'Fix backup script' -Branch develop"
    Write-Host "  .\git-push.ps1 -SetupOnly"
}

# Check if we're in a git repository
function Test-GitRepository {
    if (-not (Test-Path ".git")) {
        Write-Error "Not a git repository. Please run from health-infraops root directory."
        exit 1
    }
}

# Setup git configuration
function Set-GitConfiguration {
    Write-Info "Setting up git configuration..."
    
    # Set user info if not already set
    if (-not (git config user.name)) {
        git config user.name "Health InfraOps"
        Write-Info "Set git user.name to 'Health InfraOps'"
    }
    
    if (-not (git config user.email)) {
        git config user.email "infraops@infokes.co.id"
        Write-Info "Set git user.email to 'infraops@infokes.co.id'"
    }
    
    # Set push default
    git config push.default simple
    
    # Add remote if not exists
    try {
        git remote get-url origin | Out-Null
    } catch {
        git remote add origin git@github.com:ekpurwanto/health-infraops.git
        Write-Info "Added remote origin: git@github.com:ekpurwanto/health-infraops.git"
    }
}

# Run pre-commit checks
function Test-PreCommit {
    if ($NoVerify) {
        Write-Warning "Skipping pre-commit checks"
        return
    }
    
    Write-Info "Running pre-commit checks..."
    
    # Check for large files
    $largeFiles = Get-ChildItem -Recurse -File | Where-Object { 
        $_.Length -gt 50MB -and 
        $_.FullName -notlike "*\.git\*" -and 
        $_.FullName -notlike "*\backups\data\*" 
    }
    
    if ($largeFiles) {
        Write-Error "Found large files (>50MB):"
        $largeFiles | ForEach-Object { Write-Host "  $($_.FullName)" }
        Write-Error "Please remove or add to .gitignore"
        exit 1
    }
    
    # Check for sensitive data
    $sensitivePatterns = @(
        "password.*=",
        "secret.*=",
        "api_key.*=",
        "private_key.*=",
        "BEGIN.*PRIVATE KEY",
        "AWS_ACCESS_KEY",
        "AWS_SECRET_KEY"
    )
    
    $filesToCheck = @("*.yml", "*.yaml", "*.json", "*.conf", "*.sh", "*.ps1", "*.py")
    
    foreach ($pattern in $sensitivePatterns) {
        $matches = Get-ChildItem -Recurse -Include $filesToCheck | 
                   Select-String -Pattern $pattern -CaseSensitive:$false
        if ($matches) {
            Write-Warning "Potential sensitive data found with pattern: $pattern"
            $matches | ForEach-Object { 
                Write-Host "  $($_.FileName):$($_.LineNumber): $($_.Line)" 
            }
            $response = Read-Host "Continue anyway? (y/N)"
            if ($response -notmatch '^[Yy]$') {
                exit 1
            }
            break
        }
    }
    
    # Test scripts are executable (for WSL)
    Write-Info "Checking script permissions..."
    Get-ChildItem -Recurse -Filter "*.sh" | ForEach-Object {
        $fullPath = $_.FullName
        wsl test -x "/mnt/$(($fullPath -replace '\\','/' -replace ':',''))"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Script not executable: $fullPath"
        }
    }
    
    Write-Success "Pre-commit checks passed"
}

# Commit changes
function New-GitCommit {
    param([string]$Message)
    
    if (-not $Message) {
        Write-Error "Commit message is required"
        Show-Help
        exit 1
    }
    
    Write-Info "Staging changes..."
    git add .
    
    Write-Info "Committing changes..."
    git commit -m $Message
    
    Write-Success "Changes committed with message: $Message"
}

# Push to remote
function Push-ToRemote {
    param([string]$Branch)
    
    Write-Info "Pushing to remote repository..."
    
    if ($Force) {
        Write-Warning "Force pushing to $Branch"
        git push -f origin $Branch
    } else {
        git push origin $Branch
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Successfully pushed to $Branch"
    } else {
        Write-Error "Failed to push to $Branch"
        Write-Info "You may need to pull first: git pull origin $Branch"
        exit 1
    }
}

# Main execution
try {
    # Change to script directory
    $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $ProjectRoot = Split-Path -Parent $ScriptPath
    Set-Location $ProjectRoot
    
    # Check git repository
    Test-GitRepository
    
    # Setup git config
    Set-GitConfiguration
    
    if ($SetupOnly) {
        Write-Success "Git setup completed"
        exit 0
    }
    
    # Show current status
    $currentBranch = git branch --show-current
    Write-Info "Current branch: $currentBranch"
    Write-Info "Changes to be committed:"
    git status --short
    
    # Run pre-commit checks
    Test-PreCommit
    
    # Commit changes
    New-GitCommit -Message $Message
    
    # Push to remote
    Push-ToRemote -Branch $Branch
    
    # Show final status
    Write-Info "Repository status:"
    git log --oneline -5
    
} catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}