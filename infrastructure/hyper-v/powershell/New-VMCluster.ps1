# Health-InfraOps Hyper-V VM Cluster Creation

param(
    [Parameter(Mandatory=$true)]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$true)]
    [string[]]$NodeNames,
    
    [string]$StoragePath = "C:\ClusterStorage",
    [string]$NetworkName = "Health-InfraOps-Network",
    [string]$IPAddress = "10.0.100.0/24"
)

# Import required modules
try {
    Import-Module Hyper-V -ErrorAction Stop
    Import-Module FailoverClusters -ErrorAction Stop
    Write-Host "✅ Hyper-V and FailoverClusters modules loaded" -ForegroundColor Green
} catch {
    Write-Error "❌ Required modules not available"
    exit 1
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Error "❌ This script requires Administrator privileges"
    exit 1
}

# Validate nodes
foreach ($Node in $NodeNames) {
    if (-not (Test-Connection -ComputerName $Node -Count 1 -Quiet)) {
        Write-Error "❌ Node unreachable: $Node"
        exit 1
    }
}

try {
    Write-Host "🚀 Creating Health-InfraOps Hyper-V Cluster..." -ForegroundColor Green
    
    # Create cluster
    Write-Host "Creating cluster: $ClusterName" -ForegroundColor Yellow
    New-Cluster -Name $ClusterName -Node $NodeNames -StaticAddress $IPAddress -NoStorage
    
    # Configure cluster quorum
    Write-Host "Configuring cluster quorum..." -ForegroundColor Yellow
    Set-ClusterQuorum -NodeAndFileShareMajority
    
    # Enable cluster features
    Write-Host "Enabling cluster features..." -ForegroundColor Yellow
    Enable-ClusterStorageSpacesDirect -CimSession $NodeNames[0] -PoolFriendlyName "Health-InfraOps-Pool"
    
    # Create virtual disks
    Write-Host "Creating virtual disks..." -ForegroundColor Yellow
    New-Volume -StoragePoolFriendlyName "Health-InfraOps-Pool" -FriendlyName "CSV-Volume" -FileSystem CSVFS_ReFS -Size 500GB
    
    # Configure cluster networks
    Write-Host "Configuring cluster networks..." -ForegroundColor Yellow
    Get-ClusterNetwork | ForEach-Object {
        $Network = $_
        switch ($Network.Name) {
            "Management" {
                $Network.Role = 3  # Cluster and Client
            }
            "Live Migration" {
                $Network.Role = 1  # Cluster only
            }
            default {
                $Network.Role = 0  # None
            }
        }
    }
    
    # Set cluster properties
    Write-Host "Setting cluster properties..." -ForegroundColor Yellow
    (Get-Cluster -Name $ClusterName).SameSubnetThreshold = 20
    (Get-Cluster -Name $ClusterName).CrossSubnetThreshold = 10
    
    # Create VM folders
    Write-Host "Creating VM storage structure..." -ForegroundColor Yellow
    $VMPaths = @("$StoragePath\VMs", "$StoragePath\Templates", "$StoragePath\ISOs")
    foreach ($Path in $VMPaths) {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force
        }
    }
    
    # Test cluster
    Write-Host "Testing cluster configuration..." -ForegroundColor Yellow
    Test-Cluster -Node $NodeNames -Include "Inventory", "Network", "Storage", "System Configuration"
    
    # Create cluster report
    $ReportPath = "C:\Health-InfraOps\Cluster-Reports"
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force
    }
    
    Get-Cluster -Name $ClusterName | Export-Clixml -Path "$ReportPath\$ClusterName-ClusterInfo.xml"
    Get-ClusterNode -Cluster $ClusterName | Export-Clixml -Path "$ReportPath\$ClusterName-Nodes.xml"
    
    Write-Host "✅ Health-InfraOps Hyper-V Cluster created successfully!" -ForegroundColor Green
    Write-Host "📊 Cluster Details:" -ForegroundColor Cyan
    Write-Host "   Name: $ClusterName"
    Write-Host "   Nodes: $($NodeNames -join ', ')"
    Write-Host "   Storage: $StoragePath"
    Write-Host "   Network: $NetworkName"
    
    # Log cluster creation
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ClusterName = $ClusterName
        Nodes = ($NodeNames -join ';')
        Status = "Success"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\cluster-creations.csv" -Append -NoTypeInformation
    
} catch {
    Write-Error "❌ Cluster creation failed: $($_.Exception.Message)"
    
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ClusterName = $ClusterName
        Nodes = ($NodeNames -join ';')
        Status = "Failed: $($_.Exception.Message)"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\cluster-creations.csv" -Append -NoTypeInformation
    exit 1
}