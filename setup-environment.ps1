# Health-InfraOps PowerShell Setup Script

Write-Host "🖥  Health-InfraOps System Administrator Setup" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green

# Colors for output
$ErrorActionPreference = "Stop"

# Logging functions
function Write-Info { Write-Host "[INFO] $($args[0])" -ForegroundColor Blue }
function Write-Success { Write-Host "[SUCCESS] $($args[0])" -ForegroundColor Green }
function Write-Warning { Write-Host "[WARNING] $($args[0])" -ForegroundColor Yellow }
function Write-Error { Write-Host "[ERROR] $($args[0])" -ForegroundColor Red }

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (Test-Administrator) {
    Write-Error "Please do not run this script as Administrator"
    exit 1
}

Write-Info "Starting Health-InfraOps setup..."

# Check and install Chocolatey (Windows package manager)
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Info "Installing Chocolatey package manager..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    RefreshEnv.cmd
}

# Install essential packages
Write-Info "Installing essential packages..."
choco install -y git vscode python3 nodejs docker-desktop postman
choco install -y curl wget 7zip sysinternals

# Install Windows Subsystem for Linux (WSL) if not present
if (-not (wsl --list --quiet)) {
    Write-Info "Installing Windows Subsystem for Linux..."
    wsl --install -d Ubuntu
    Write-Warning "WSL installation requires restart. Please restart and run this script again."
    exit 0
}

# Install Python packages
Write-Info "Installing Python packages..."
pip install --upgrade pip
pip install ansible terraform-commander boto3 azure-identity google-cloud-storage
pip install prometheus-client grafana-api elasticsearch python-dotenv

# Setup SSH key for GitHub
Write-Info "Setting up SSH key for GitHub..."
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path "$sshDir\id_rsa")) {
    ssh-keygen -t rsa -b 4096 -C "your-email@infokes.co.id" -f "$sshDir\id_rsa" -N ""
    Start-Service ssh-agent
    ssh-add "$sshDir\id_rsa"
    
    Write-Warning "Please add this SSH key to your GitHub account:"
    Write-Host "==========================================" -ForegroundColor Cyan
    Get-Content "$sshDir\id_rsa.pub"
    Write-Host "==========================================" -ForegroundColor Cyan
    Read-Host "Press Enter after adding the key to GitHub"
}

# Clone or update repository
$repoPath = "health-infraops"
if (Test-Path $repoPath) {
    Write-Info "Updating existing repository..."
    Set-Location $repoPath
    git pull origin main
} else {
    Write-Info "Cloning repository from GitHub..."
    git clone git@github.com:ekpurwanto/health-infraops.git
    Set-Location $repoPath
}

# Create Python virtual environment
Write-Info "Setting up Python virtual environment..."
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install Python dependencies
Write-Info "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Make scripts executable (for WSL compatibility)
Write-Info "Setting up script permissions..."
Get-ChildItem -Recurse -Filter "*.sh" | ForEach-Object {
    $fullPath = $_.FullName
    wsl chmod +x "/mnt/$(($fullPath -replace '\\','/' -replace ':',''))"
}

# Setup environment variables
Write-Info "Setting up environment variables..."
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Warning "Please update .env file with your configuration"
}

# Initialize Git hooks
Write-Info "Setting up Git hooks..."
if (Test-Path "scripts\git-hooks") {
    Copy-Item "scripts\git-hooks\*" ".git\hooks\" -Force
    Get-ChildItem ".git\hooks\*" | ForEach-Object { 
        $fullPath = $_.FullName
        wsl chmod +x "/mnt/$(($fullPath -replace '\\','/' -replace ':',''))"
    }
}

# Test installation
Write-Info "Testing installation..."
.\scripts\health-check.ps1 -Environment "local" -Quick

Write-Success "✅ Setup completed successfully!"
Write-Host ""
Write-Host "📋 Next steps:" -ForegroundColor Cyan
Write-Host "1. Update .env file with your configuration"
Write-Host "2. Run: .\venv\Scripts\Activate.ps1"
Write-Host "3. Test deployment: .\scripts\deploy.ps1 local infrastructure"
Write-Host "4. Explore documentation in documentation\"
Write-Host ""
Write-Host "🚀 Happy coding! Navigate to health-infraops directory" -ForegroundColor Green