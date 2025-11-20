#!/bin/bash
# Health-InfraOps Local Development Setup Script

set -e

echo "🖥  Health-InfraOps System Administrator Setup"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please do not run this script as root"
    exit 1
fi

log_info "Starting Health-InfraOps setup..."

# Update system
log_info "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install essential packages
log_info "Installing essential packages..."
sudo apt install -y \
    git curl wget vim htop net-tools \
    python3 python3-pip python3-venv \
    ansible terraform docker.io docker-compose \
    jq tree unzip

# Add user to docker group
sudo usermod -aG docker $USER

# Setup GitHub (if not already configured)
if [ ! -f ~/.ssh/id_rsa ]; then
    log_info "Generating SSH key for GitHub..."
    ssh-keygen -t rsa -b 4096 -C "your-email@infokes.co.id" -f ~/.ssh/id_rsa -N ""
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa
    
    log_warning "Please add this SSH key to your GitHub account:"
    echo "=========================================="
    cat ~/.ssh/id_rsa.pub
    echo "=========================================="
    read -p "Press Enter after adding the key to GitHub..."
fi

# Clone or update repository
if [ -d "health-infraops" ]; then
    log_info "Updating existing repository..."
    cd health-infraops
    git pull origin main
else
    log_info "Cloning repository from GitHub..."
    git clone git@github.com:ekpurwanto/health-infraops.git
    cd health-infraops
fi

# Create Python virtual environment
log_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
log_info "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Make all scripts executable
log_info "Making scripts executable..."
find . -name "*.sh" -exec chmod +x {} \;

# Setup environment variables
log_info "Setting up environment variables..."
if [ ! -f .env ]; then
    cp .env.example .env
    log_warning "Please update .env file with your configuration"
fi

# Initialize Git hooks
log_info "Setting up Git hooks..."
cp scripts/git-hooks/* .git/hooks/
chmod +x .git/hooks/*

# Test installation
log_info "Testing installation..."
./scripts/health-check.sh --environment local --quick

log_success "✅ Setup completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Update .env file with your configuration"
echo "2. Run: source venv/bin/activate"
echo "3. Test deployment: ./scripts/deploy.sh local infrastructure"
echo "4. Explore documentation in documentation/"
echo ""
echo "🚀 Happy coding! Navigate to health-infraops directory"