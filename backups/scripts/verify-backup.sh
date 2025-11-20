#!/bin/bash

# Health-InfraOps Backup Verification Script
# Comprehensive backup verification and integrity checking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$(dirname "$BACKUP_ROOT")")"

# Configuration
BACKUP_DIR="$BACKUP_ROOT/data"
LOG_DIR="$BACKUP_ROOT/logs"
VERIFICATION_DIR="$BACKUP_ROOT/verification"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VERIFICATION_ID="verify_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$VERIFICATION_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/${VERIFICATION_ID}.log"
REPORT_FILE="$VERIFICATION_DIR/${VERIFICATION_ID}_report.html"

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

show_help() {
    cat << EOF
Health-InfraOps Backup Verification Script

Usage: $0 [options]

Options:
  -h, --help           Show this help message
  -t, --type TYPE      Backup type to verify (all/full/incremental)
  -b, --backup ID      Verify specific backup ID
  --since DATE         Verify backups since date (YYYY-MM-DD)
  --check-encryption   Verify encryption of backup files
  --check-integrity    Verify file integrity and checksums
  --test-restore       Test restore capability (destructive)
  --html-report        Generate HTML verification report
  --email-report       Email verification report
  --quick              Quick verification only

Examples:
  $0 --type full --check-integrity
  $0 --backup full_20231201_120000 --test-restore
  $0 --since 2023-12-01 --html-report
  $0 --type all --quick
EOF
}

# Statistics
TOTAL_BACKUPS=0
VERIFIED_BACKUPS=0
FAILED_BACKUPS=0
WARNING_BACKUPS=0

# Find backup files
find_backup_files() {
    local backup_type=$1
    local since_date=$2
    
    local find_cmd="find \"$BACKUP_DIR\" -type f"
    
    case $backup_type in
        full)
            find_cmd="$find_cmd -name \"full_*\" -o -name \"*full*\""
            ;;
        incremental)
            find_cmd="$find_cmd -name \"incremental_*\" -o -name \"*inc*\""
            ;;
        all|*)
            find_cmd="$find_cmd -name \"*.gz\" -o -name \"*.enc\" -o -name \"*.sql\" -o -name \"*.tar\""
            ;;
    esac
    
    if [ -n "$since_date" ]; then
        find_cmd="$find_cmd -newermt \"$since_date\""
    fi
    
    eval "$find_cmd" | sort
}

# Verify file integrity
verify_file_integrity() {
    local file_path=$1
    
    log_info "Verifying file integrity: $(basename "$file_path")"
    
    if [[ "$file_path" == *.enc ]]; then
        verify_encrypted_file "$file_path"
    elif [[ "$file_path" == *.tar.gz ]] || [[ "$file_path" == *.gz ]]; then
        verify_compressed_file "$file_path"
    elif [[ "$file_path" == *.sql ]]; then
        verify_sql_file "$file_path"
    else
        verify_generic_file "$file_path"
    fi
}

# Verify encrypted files
verify_encrypted_file() {
    local file_path=$1
    
    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        log_warning "Skipping encrypted file (no key): $(basename "$file_path")"
        WARNING_BACKUPS=$((WARNING_BACKUPS + 1))
        return 2
    fi
    
    if openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "$file_path" \
        -out /dev/null \
        -pass pass:"$BACKUP_ENCRYPTION_KEY" 2>/dev/null; then
        log_success "Encrypted file verified: $(basename "$file_path")"
        VERIFIED_BACKUPS=$((VERIFIED_BACKUPS + 1))
        return 0
    else
        log_error "Encrypted file verification failed: $(basename "$file_path")"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        return 1
    fi
}

# Verify compressed files
verify_compressed_file() {
    local file_path=$1
    
    if tar -tzf "$file_path" > /dev/null 2>&1; then
        # Additional check: test extraction to temporary directory
        local temp_dir
        temp_dir=$(mktemp -d)
        
        if tar -xzf "$file_path" -C "$temp_dir" --strip-components=1 > /dev/null 2>&1; then
            rm -rf "$temp_dir"
            log_success "Compressed file verified: $(basename "$file_path")"
            VERIFIED_BACKUPS=$((VERIFIED_BACKUPS + 1))
            return 0
        else
            rm -rf "$temp_dir"
            log_error "Compressed file extraction failed: $(basename "$file_path")"
            FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
            return 1
        fi
    else
        log_error "Compressed file integrity check failed: $(basename "$file_path")"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        return 1
    fi
}

# Verify SQL files
verify_sql_file() {
    local file_path=$1
    
    # Check if file is not empty and has valid SQL structure
    if [ -s "$file_path" ]; then
        if head -n 10 "$file_path" | grep -q -E "(CREATE|INSERT|UPDATE|DROP|ALTER)"; then
            log_success "SQL file verified: $(basename "$file_path")"
            VERIFIED_BACKUPS=$((VERIFIED_BACKUPS + 1))
            return 0
        else
            log_warning "SQL file structure questionable: $(basename "$file_path")"
            WARNING_BACKUPS=$((WARNING_BACKUPS + 1))
            return 2
        fi
    else
        log_error "SQL file is empty: $(basename "$file_path")"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        return 1
    fi
}

# Verify generic files
verify_generic_file() {
    local file_path=$1
    
    if [ -s "$file_path" ]; then
        # Calculate checksum for future comparison
        local checksum
        checksum=$(md5sum "$file_path" | cut -d' ' -f1)
        
        log_success "File verified: $(basename "$file_path") [MD5: ${checksum:0:8}]"
        VERIFIED_BACKUPS=$((VERIFIED_BACKUPS + 1))
        return 0
    else
        log_error "File is empty: $(basename "$file_path")"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        return 1
    fi
}

# Verify backup manifest
verify_backup_manifest() {
    local backup_file=$1
    
    local backup_dir
    backup_dir=$(dirname "$backup_file")
    local backup_name
    backup_name=$(basename "$backup_file" | cut -d'.' -f1)
    local manifest_file="$backup_dir/${backup_name}.manifest"
    
    if [ -f "$manifest_file" ]; then
        log_info "Found manifest file: $(basename "$manifest_file")"
        
        # Verify files listed in manifest exist
        local missing_files=0
        while IFS= read -r line; do
            if [[ "$line" == *"- "* ]]; then
                local listed_file
                listed_file=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]//')
                if [ ! -f "$backup_dir/$listed_file" ]; then
                    log_warning "File listed in manifest not found: $listed_file"
                    missing_files=$((missing_files + 1))
                fi
            fi
        done < "$manifest_file"
        
        if [ "$missing_files" -eq 0 ]; then
            log_success "Manifest verification passed: $(basename "$manifest_file")"
        else
            log_warning "Manifest has $missing_files missing files: $(basename "$manifest_file")"
        fi
    else
        log_warning "No manifest file found for: $(basename "$backup_file")"
    fi
}

# Test restore capability (non-destructive)
test_restore_capability() {
    local backup_file=$1
    
    log_info "Testing restore capability for: $(basename "$backup_file")"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    case $(basename "$backup_file") in
        *mysql*)
            test_mysql_restore "$backup_file" "$temp_dir"
            ;;
        *mongodb*)
            test_mongodb_restore "$backup_file" "$temp_dir"
            ;;
        *app*|*config*)
            test_filesystem_restore "$backup_file" "$temp_dir"
            ;;
        *)
            log_warning "Unknown backup type for restore test: $(basename "$backup_file")"
            ;;
    esac
    
    rm -rf "$temp_dir"
}

# Test MySQL restore
test_mysql_restore() {
    local backup_file=$1
    local temp_dir=$2
    
    local test_db="backup_verify_${TIMESTAMP}"
    
    # Create test database
    if mysql -e "CREATE DATABASE $test_db;" 2>/dev/null; then
        log_info "Created test database: $test_db"
        
        # Try to restore schema only
        if [[ "$backup_file" == *.gz ]]; then
            gunzip -c "$backup_file" | mysql "$test_db" 2>/dev/null || true
        else
            mysql "$test_db" < "$backup_file" 2>/dev/null || true
        fi
        
        # Check if any tables were created
        local table_count
        table_count=$(mysql -e "USE $test_db; SHOW TABLES;" 2>/dev/null | wc -l)
        
        # Cleanup
        mysql -e "DROP DATABASE $test_db;" 2>/dev/null
        
        if [ "$table_count" -gt 0 ]; then
            log_success "MySQL restore test passed: $(basename "$backup_file")"
            return 0
        else
            log_warning "MySQL restore test created no tables: $(basename "$backup_file")"
            return 2
        fi
    else
        log_warning "Could not create test database for MySQL restore test"
        return 2
    fi
}

# Test MongoDB restore
test_mongodb_restore() {
    local backup_file=$1
    local temp_dir=$2
    
    local test_db="backup_verify_${TIMESTAMP}"
    
    # Extract backup if compressed
    if [[ "$backup_file" == *.tar.gz ]]; then
        tar -xzf "$backup_file" -C "$temp_dir"
        local extracted_dir
        extracted_dir=$(find "$temp_dir" -type d -name "mongodump*" | head -1)
        
        if [ -n "$extracted_dir" ]; then
            if mongorestore --nsFrom ".*" --nsTo "${test_db}.*" "$extracted_dir" --quiet 2>/dev/null; then
                # Check if any collections were restored
                local collection_count
                collection_count=$(mongo "$test_db" --eval "db.getCollectionNames().length" --quiet)
                
                # Cleanup
                mongo "$test_db" --eval "db.dropDatabase()" --quiet
                
                if [ "$collection_count" -gt 0 ]; then
                    log_success "MongoDB restore test passed: $(basename "$backup_file")"
                    return 0
                else
                    log_warning "MongoDB restore test created no collections: $(basename "$backup_file")"
                    return 2
                fi
            else
                log_warning "MongoDB restore test failed: $(basename "$backup_file")"
                return 2
            fi
        fi
    else
        log_warning "Unsupported MongoDB backup format for restore test"
        return 2
    fi
}

# Test filesystem restore
test_filesystem_restore() {
    local backup_file=$1
    local temp_dir=$2
    
    if tar -tzf "$backup_file" > /dev/null 2>&1; then
        # Extract to temporary directory
        if tar -xzf "$backup_file" -C "$temp_dir" > /dev/null 2>&1; then
            # Check if files were extracted
            local file_count
            file_count=$(find "$temp_dir" -type f | wc -l)
            
            if [ "$file_count" -gt 0 ]; then
                log_success "Filesystem restore test passed: $(basename "$backup_file") - $file_count files"
                return 0
            else
                log_warning "Filesystem restore test extracted no files: $(basename "$backup_file")"
                return 2
            fi
        else
            log_warning "Filesystem restore test extraction failed: $(basename "$backup_file")"
            return 2
        fi
    else
        log_warning "Invalid tar archive for restore test: $(basename "$backup_file")"
        return 2
    fi
}

# Check backup age and retention
check_backup_age() {
    local backup_file=$1
    
    local backup_date
    backup_date=$(stat -c %Y "$backup_file")
    local current_date
    current_date=$(date +%s)
    local age_days
    age_days=$(( (current_date - backup_date) / 86400 ))
    
    local backup_name
    backup_name=$(basename "$backup_file")
    
    # Define retention policies
    local max_age=30
    if [[ "$backup_name" == *inc* ]]; then
        max_age=7
    elif [[ "$backup_name" == *full* ]]; then
        max_age=30
    fi
    
    if [ "$age_days" -gt "$max_age" ]; then
        log_warning "Backup is ${age_days} days old (exceeds ${max_age} day retention): $(basename "$backup_file")"
        return 2
    else
        log_info "Backup age: ${age_days} days - $(basename "$backup_file")"
        return 0
    fi
}

# Generate HTML report
generate_html_report() {
    log_info "Generating HTML verification report..."
    
    cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Backup Verification Report - $VERIFICATION_ID</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; padding: 15px; border-radius: 5px; }
        .healthy { background: #d4edda; border: 1px solid #c3e6cb; }
        .warning { background: #fff3cd; border: 1px solid #ffeaa7; }
        .unhealthy { background: #f8d7da; border: 1px solid #f5c6cb; }
        .backup-list { margin: 10px 0; }
        .backup-item { padding: 8px; margin: 2px 0; border-left: 4px solid #007bff; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        .stats { display: flex; justify-content: space-between; margin: 20px 0; }
        .stat-box { flex: 1; padding: 15px; text-align: center; border-radius: 5px; margin: 0 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Backup Verification Report</h1>
        <p><strong>Verification ID:</strong> $VERIFICATION_ID</p>
        <p><strong>Timestamp:</strong> $(date)</p>
        <p><strong>Backup Directory:</strong> $BACKUP_DIR</p>
    </div>
    
    <div class="stats">
        <div class="stat-box" style="background: #d4edda;">
            <h3>Verified</h3>
            <p style="font-size: 24px; font-weight: bold;">$VERIFIED_BACKUPS</p>
        </div>
        <div class="stat-box" style="background: #fff3cd;">
            <h3>Warnings</h3>
            <p style="font-size: 24px; font-weight: bold;">$WARNING_BACKUPS</p>
        </div>
        <div class="stat-box" style="background: #f8d7da;">
            <h3>Failed</h3>
            <p style="font-size: 24px; font-weight: bold;">$FAILED_BACKUPS</p>
        </div>
        <div class="stat-box" style="background: #d1ecf1;">
            <h3>Total</h3>
            <p style="font-size: 24px; font-weight: bold;">$TOTAL_BACKUPS</p>
        </div>
    </div>
    
    <div class="summary">
        <h2>Verification Summary</h2>
        <p><strong>Overall Status:</strong> 
EOF

    if [ "$FAILED_BACKUPS" -eq 0 ]; then
        if [ "$WARNING_BACKUPS" -eq 0 ]; then
            echo "<span style='color: green; font-weight: bold;'>HEALTHY</span>" >> "$REPORT_FILE"
        else
            echo "<span style='color: orange; font-weight: bold;'>DEGRADED</span>" >> "$REPORT_FILE"
        fi
    else
        echo "<span style='color: red; font-weight: bold;'>UNHEALTHY</span>" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF
        </p>
        <p><strong>Success Rate:</strong> $((TOTAL_BACKUPS > 0 ? (VERIFIED_BACKUPS * 100 / TOTAL_BACKUPS) : 0))%</p>
    </div>
    
    <div class="backup-list">
        <h2>Detailed Results</h2>
EOF

    # Add log entries to HTML
    while IFS= read -r line; do
        local class=""
        if [[ $line == *"SUCCESS"* ]]; then
            class="success"
        elif [[ $line == *"WARNING"* ]]; then
            class="warning"
        elif [[ $line == *"ERROR"* ]]; then
            class="error"
        fi
        echo "<div class='backup-item $class'>$line</div>" >> "$REPORT_FILE"
    done < "$LOG_FILE"

    cat >> "$REPORT_FILE" << EOF
    </div>
    
    <div style="margin-top: 30px; padding: 15px; background: #f8f9fa; border-radius: 5px;">
        <h3>Recommendations</h3>
        <ul>
EOF

    if [ "$FAILED_BACKUPS" -gt 0 ]; then
        echo "<li>Immediate action required for $FAILED_BACKUPS failed backups</li>" >> "$REPORT_FILE"
    fi
    if [ "$WARNING_BACKUPS" -gt 0 ]; then
        echo "<li>Review $WARNING_BACKUPS backups with warnings</li>" >> "$REPORT_FILE"
    fi
    if [ "$TOTAL_BACKUPS" -eq 0 ]; then
        echo "<li>No backups found for verification</li>" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF
            <li>Run full backup verification weekly</li>
            <li>Test restore capability monthly</li>
            <li>Monitor backup storage capacity</li>
        </ul>
    </div>
</body>
</html>
EOF

    log_success "HTML report generated: $REPORT_FILE"
}

# Email report
email_report() {
    local recipient=${EMAIL_RECIPIENT:-"admin@infokes.co.id"}
    
    if command -v mail &> /dev/null; then
        cat "$REPORT_FILE" | mail -s "Backup Verification Report - $VERIFICATION_ID" "$recipient"
        log_success "Verification report emailed to: $recipient"
    else
        log_warning "mail command not available, cannot send email report"
    fi
}

# Quick verification
quick_verification() {
    log_info "Running quick verification..."
    
    # Check latest backups only
    local latest_backups
    latest_backups=$(find "$BACKUP_DIR" -type f -name "*.gz" -o -name "*.enc" | sort -r | head -10)
    
    for backup in $latest_backups; do
        TOTAL_BACKUPS=$((TOTAL_BACKUPS + 1))
        verify_file_integrity "$backup"
    done
}

# Main verification function
main_verification() {
    log_info "Starting backup verification - ID: $VERIFICATION_ID"
    
    if [ "$QUICK_VERIFY" = true ]; then
        quick_verification
    else
        # Find all backup files based on criteria
        local backup_files
        backup_files=$(find_backup_files "$BACKUP_TYPE" "$SINCE_DATE")
        
        for backup_file in $backup_files; do
            TOTAL_BACKUPS=$((TOTAL_BACKUPS + 1))
            
            # Verify file integrity
            verify_file_integrity "$backup_file"
            
            # Verify manifest if exists
            verify_backup_manifest "$backup_file"
            
            # Check backup age
            check_backup_age "$backup_file"
            
            # Test restore capability if requested
            if [ "$TEST_RESTORE" = true ]; then
                test_restore_capability "$backup_file"
            fi
        done
    fi
    
    # Generate report
    if [ "$GENERATE_HTML" = true ]; then
        generate_html_report
    fi
    
    # Email report if requested
    if [ "$EMAIL_REPORT" = true ]; then
        email_report
    fi
    
    # Final summary
    log_info "Verification completed:"
    log_info "  Total backups checked: $TOTAL_BACKUPS"
    log_info "  Verified: $VERIFIED_BACKUPS"
    log_info "  Warnings: $WARNING_BACKUPS"
    log_info "  Failed: $FAILED_BACKUPS"
    
    if [ "$FAILED_BACKUPS" -gt 0 ]; then
        log_error "Backup verification completed with $FAILED_BACKUPS failures"
        exit 1
    elif [ "$WARNING_BACKUPS" -gt 0 ]; then
        log_warning "Backup verification completed with $WARNING_BACKUPS warnings"
        exit 0
    else
        log_success "All backups verified successfully"
        exit 0
    fi
}

# Parse arguments
BACKUP_TYPE="all"
SINCE_DATE=""
CHECK_ENCRYPTION=false
CHECK_INTEGRITY=true
TEST_RESTORE=false
GENERATE_HTML=false
EMAIL_REPORT=false
QUICK_VERIFY=false
SPECIFIC_BACKUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--type)
            BACKUP_TYPE=$2
            shift 2
            ;;
        -b|--backup)
            SPECIFIC_BACKUP=$2
            shift 2
            ;;
        --since)
            SINCE_DATE=$2
            shift 2
            ;;
        --check-encryption)
            CHECK_ENCRYPTION=true
            shift
            ;;
        --check-integrity)
            CHECK_INTEGRITY=true
            shift
            ;;
        --test-restore)
            TEST_RESTORE=true
            shift
            ;;
        --html-report)
            GENERATE_HTML=true
            shift
            ;;
        --email-report)
            EMAIL_REPORT=true
            shift
            ;;
        --quick)
            QUICK_VERIFY=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Export encryption key if needed
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}

# If specific backup provided, verify only that one
if [ -n "$SPECIFIC_BACKUP" ]; then
    local backup_file
    backup_file=$(find "$BACKUP_DIR" -name "*$SPECIFIC_BACKUP*" -type f | head -1)
    if [ -n "$backup_file" ]; then
        TOTAL_BACKUPS=1
        verify_file_integrity "$backup_file"
        if [ "$TEST_RESTORE" = true ]; then
            test_restore_capability "$backup_file"
        fi
    else
        log_error "Backup not found: $SPECIFIC_BACKUP"
        exit 1
    fi
else
    main_verification
fi