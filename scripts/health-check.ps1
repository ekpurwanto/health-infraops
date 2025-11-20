# Health-InfraOps Health Check Script for PowerShell

param(
    [string]$Environment = "local",
    [switch]$Quick,
    [switch]$Full,
    [string]$Component = "all"
)

# Colors
function Write-Info { Write-Host "[INFO] $($args[0])" -ForegroundColor Blue }
function Write-Success { Write-Host "[SUCCESS] $($args[0])" -ForegroundColor Green }
function Write-Warning { Write-Host "[WARNING] $($args[0])" -ForegroundColor Yellow }
function Write-Error { Write-Host "[ERROR] $($args[0])" -ForegroundColor Red }

# Health status counters
$Healthy = 0
$Unhealthy = 0
$Warning = 0

function Test-ServiceHealth {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Write-Success "Service $ServiceName is running"
            $script:Healthy++
        } else {
            Write-Error "Service $ServiceName is not running (Status: $($service.Status))"
            $script:Unhealthy++
        }
    } catch {
        Write-Warning "Service $ServiceName not found"
        $script:Warning++
    }
}

function Test-PortListening {
    param([int]$Port, [string]$ServiceName = "Unknown")
    
    try {
        $connection = Test-NetConnection -ComputerName localhost -Port $Port -InformationLevel Quiet
        if ($connection) {
            Write-Success "Port $Port ($ServiceName) is listening"
            $script:Healthy++
        } else {
            Write-Error "Port $Port ($ServiceName) is not listening"
            $script:Unhealthy++
        }
    } catch {
        Write-Error "Failed to test port $Port ($ServiceName)"
        $script:Unhealthy++
    }
}

function Test-DiskSpace {
    param([string]$Drive = "C", [int]$ThresholdPercent = 80)
    
    try {
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$Drive`:'"
        if ($disk) {
            $freeSpacePercent = ($disk.FreeSpace / $disk.Size) * 100
            if ($freeSpacePercent -gt (100 - $ThresholdPercent)) {
                Write-Success "Drive $Drive has $([math]::Round($freeSpacePercent, 1))% free space"
                $script:Healthy++
            } else {
                Write-Warning "Drive $Drive has only $([math]::Round($freeSpacePercent, 1))% free space"
                $script:Warning++
            }
        }
    } catch {
        Write-Error "Failed to check disk space for drive $Drive"
        $script:Unhealthy++
    }
}

function Test-ProcessRunning {
    param([string]$ProcessName)
    
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Success "Process $ProcessName is running"
        $script:Healthy++
    } else {
        Write-Error "Process $ProcessName is not running"
        $script:Unhealthy++
    }
}

function Test-InfrastructureHealth {
    Write-Info "Checking infrastructure health..."
    
    # Test essential services
    Test-ServiceHealth "Docker Desktop Service"
    Test-ServiceHealth "SSH Agent"
    
    # Test ports
    Test-PortListening -Port 80 -ServiceName "HTTP"
    Test-PortListening -Port 443 -ServiceName "HTTPS"
    Test-PortListening -Port 22 -ServiceName "SSH"
    
    # Test disk space
    Test-DiskSpace -Drive "C" -ThresholdPercent 80
    
    # Test processes
    Test-ProcessRunning "docker"
    Test-ProcessRunning "python"
}

function Test-ApplicationHealth {
    Write-Info "Checking application health..."
    
    # Test if Python virtual environment exists
    if (Test-Path "venv") {
        Write-Success "Python virtual environment exists"
        $script:Healthy++
    } else {
        Write-Error "Python virtual environment not found"
        $script:Unhealthy++
    }
    
    # Test if requirements are installed
    try {
        python -c "import ansible, boto3, requests" 2>$null
        Write-Success "Python dependencies are installed"
        $script:Healthy++
    } catch {
        Write-Error "Python dependencies are missing"
        $script:Unhealthy++
    }
    
    # Test if scripts are accessible
    $scripts = @("deploy.ps1", "backup-all.ps1", "health-check.ps1")
    foreach ($script in $scripts) {
        if (Test-Path "scripts\$script") {
            Write-Success "Script $script is accessible"
            $script:Healthy++
        } else {
            Write-Warning "Script $script not found"
            $script:Warning++
        }
    }
}

function Test-DatabaseHealth {
    Write-Info "Checking database connectivity..."
    
    # This would test database connections
    # For now, just check if Docker is running databases
    try {
        $dockerPs = docker ps --format "table {{.Names}}\t{{.Status}}" 2>$null
        if ($dockerPs -like "*mysql*" -or $dockerPs -like "*mongo*" -or $dockerPs -like "*postgres*") {
            Write-Success "Database containers are running"
            $script:Healthy++
        } else {
            Write-Warning "No database containers found (this may be normal for local development)"
            $script:Warning++
        }
    } catch {
        Write-Warning "Docker not available or no databases running"
        $script:Warning++
    }
}

# Main execution
try {
    Write-Host "🩺 Health-InfraOps Health Check" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    
    switch ($Component) {
        "infrastructure" { Test-InfrastructureHealth }
        "application" { Test-ApplicationHealth }
        "database" { Test-DatabaseHealth }
        "all" { 
            Test-InfrastructureHealth
            Test-ApplicationHealth 
            Test-DatabaseHealth
        }
    }
    
    # Generate summary
    $totalChecks = $Healthy + $Unhealthy + $Warning
    Write-Host ""
    Write-Host "📊 Health Check Summary:" -ForegroundColor Cyan
    Write-Host "  Total checks: $totalChecks"
    Write-Host "  Healthy: $Healthy" -ForegroundColor Green
    Write-Host "  Warnings: $Warning" -ForegroundColor Yellow
    Write-Host "  Unhealthy: $Unhealthy" -ForegroundColor Red
    
    if ($Unhealthy -gt 0) {
        Write-Error "Health check completed with $Unhealthy failures"
        exit 1
    } elseif ($Warning -gt 0) {
        Write-Warning "Health check completed with $Warning warnings"
        exit 0
    } else {
        Write-Success "All health checks passed!"
        exit 0
    }
    
} catch {
    Write-Error "Health check failed: $($_.Exception.Message)"
    exit 1
}