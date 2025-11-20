#!/bin/bash
# Health-InfraOps Git Push Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << EOF
Health-InfraOps Git Push Script

Usage: $0 [options]

Options:
  -h, --help           Show this help message
  -m, --message MSG    Commit message
  -b, --branch BRANCH  Target branch (default: main)
  --no-verify         Skip pre-commit checks
  --force             Force push
  --setup-only        Only setup repository, don't push

Examples:
  $0 -m "Add new monitoring features"
  $0 -m "Fix backup script" -b develop
  $0 --setup-only
EOF
}

# Check if we're in a git repository
check_git_repo() {
    if [ ! -d ".git" ]; then
        log_error "Not a git repository. Please run from health-infraops root directory."
        exit 1
    fi
}

# Setup git configuration
setup_git_config() {
    log_info "Setting up git configuration..."
    
    # Set user info if not already set
    if [ -z "$(git config user.name)" ]; then
        git config user.name "Health InfraOps"
        log_info "Set git user.name to 'Health InfraOps'"
    fi
    
    if [ -z "$(git config user.email)" ]; then
        git config user.email "infraops@infokes.co.id"
        log_info "Set git user.email to 'infraops@infokes.co.id'"
    fi
    
    # Set push default
    git config push.default simple
    
    # Add remote if not exists
    if ! git remote get-url origin &> /dev/null; then
        git remote add origin git@github.com:ekpurwanto/health-infraops.git
        log_info "Added remote origin: git@github.com:ekpurwanto/health-infraops.git"
    fi
}

# Run pre-commit checks
run_pre_commit_checks() {
    if [ "$SKIP_VERIFY" = true ]; then
        log_warning "Skipping pre-commit checks"
        return 0
    fi
    
    log_info "Running pre-commit checks..."
    
    # Check for large files
    local large_files
    large_files=$(find . -type f -size +50M ! -path "./.git/*" ! -path "./backups/data/*")
    if [ -n "$large_files" ]; then
        log_error "Found large files (>50MB):"
        echo "$large_files"
        log_error "Please remove or add to .gitignore"
        exit 1
    fi
    
    # Check for sensitive data
    local sensitive_patterns=(
        "password.*="
        "secret.*="
        "api_key.*="
        "private_key.*="
        "BEGIN.*PRIVATE KEY"
        "AWS_ACCESS_KEY"
        "AWS_SECRET_KEY"
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        local matches
        matches=$(grep -r --include="*.yml" --include="*.yaml" --include="*.json" --include="*.conf" --include="*.sh" --include="*.py" -i "$pattern" . || true)
        if [ -n "$matches" ]; then
            log_warning "Potential sensitive data found with pattern: $pattern"
            echo "$matches"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            break
        fi
    done
    
    # Test scripts are executable
    log_info "Checking script permissions..."
    find . -name "*.sh" -exec test -x {} \; -o -name "*.sh" -exec ls -la {} \;
    
    log_success "Pre-commit checks passed"
}

# Commit changes
commit_changes() {
    local message=$1
    
    if [ -z "$message" ]; then
        log_error "Commit message is required"
        show_help
        exit 1
    fi
    
    log_info "Staging changes..."
    git add .
    
    log_info "Committing changes..."
    git commit -m "$message"
    
    log_success "Changes committed with message: $message"
}

# Push to remote
push_to_remote() {
    local branch=$1
    
    log_info "Pushing to remote repository..."
    
    if [ "$FORCE_PUSH" = true ]; then
        log_warning "Force pushing to $branch"
        git push -f origin "$branch"
    else
        git push origin "$branch"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Successfully pushed to $branch"
    else
        log_error "Failed to push to $branch"
        log_info "You may need to pull first: git pull origin $branch"
        exit 1
    fi
}

# Main function
main() {
    local commit_message=""
    local target_branch="main"
    local setup_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--message)
                commit_message="$2"
                shift 2
                ;;
            -b|--branch)
                target_branch="$2"
                shift 2
                ;;
            --no-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --force)
                FORCE_PUSH=true
                shift
                ;;
            --setup-only)
                setup_only=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Check git repository
    check_git_repo
    
    # Setup git config
    setup_git_config
    
    if [ "$setup_only" = true ]; then
        log_success "Git setup completed"
        exit 0
    fi
    
    # Show current status
    log_info "Current branch: $(git branch --show-current)"
    log_info "Changes to be committed:"
    git status --short
    
    # Run pre-commit checks
    run_pre_commit_checks
    
    # Commit changes
    commit_changes "$commit_message"
    
    # Push to remote
    push_to_remote "$target_branch"
    
    # Show final status
    log_info "Repository status:"
    git log --oneline -5
}

# Execute main function
main "$@"