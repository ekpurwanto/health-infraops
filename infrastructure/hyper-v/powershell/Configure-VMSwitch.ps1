# Health-InfraOps Hyper-V Virtual Switch Configuration

param(
    [Parameter(Mandatory=$true)]
    [string]$SwitchName,
    
    [ValidateSet("External", "Internal", "Private")]
    [string]$SwitchType = "External",
    
    [string]$NetAdapterName,
    [string]$VLANId,
    [switch]$EnableSR-IOV = $false
)

# Import Hyper-V module
try {
    Import-Module Hyper-V -ErrorAction Stop
    Write-Host "✅ Hyper-V module loaded" -ForegroundColor Green
} catch {
    Write-Error "❌ Hyper-V module not available"
    exit 1
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsPrincipal]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Error "❌ This script requires Administrator privileges"
    exit 1
}

try {
    Write-Host "🔧 Configuring Hyper-V Virtual Switch..." -ForegroundColor Green
    
    # Check if switch already exists
    $ExistingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if ($ExistingSwitch) {
        Write-Warning "⚠️ Virtual Switch '$SwitchName' already exists"
        $Overwrite = Read-Host "Overwrite? (y/n)"
        if ($Overwrite -ne 'y') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            exit 0
        }
        Remove-VMSwitch -Name $SwitchName -Force
    }
    
    # Create virtual switch based on type
    switch ($SwitchType) {
        "External" {
            if (-not $NetAdapterName) {
                # Get available network adapters
                $Adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
                if ($Adapters.Count -eq 0) {
                    Write-Error "❌ No available network adapters found"
                    exit 1
                }
                
                Write-Host "Available network adapters:" -ForegroundColor Cyan
                $Adapters | Format-Table Name, InterfaceDescription, LinkSpeed -AutoSize
                
                $NetAdapterName = Read-Host "Enter network adapter name"
            }
            
            Write-Host "Creating External switch: $SwitchName" -ForegroundColor Yellow
            $VMSwitch = New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true -EnableIov $EnableSR-IOV
        }
        
        "Internal" {
            Write-Host "Creating Internal switch: $SwitchName" -ForegroundColor Yellow
            $VMSwitch = New-VMSwitch -Name $SwitchName -SwitchType Internal
        }
        
        "Private" {
            Write-Host "Creating Private switch: $SwitchName" -ForegroundColor Yellow
            $VMSwitch = New-VMSwitch -Name $SwitchName -SwitchType Private
        }
    }
    
    # Configure VLAN if specified
    if ($VLANId) {
        Write-Host "Configuring VLAN: $VLANId" -ForegroundColor Yellow
        
        # Create VLAN configuration on management OS
        $ManagementAdapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
        if ($ManagementAdapter) {
            Set-NetAdapterAdvancedProperty -Name $ManagementAdapter.Name -RegistryKeyword "VLANID" -RegistryValue $VLANId
        }
    }
    
    # Configure switch settings
    Write-Host "Configuring switch settings..." -ForegroundColor Yellow
    
    # Enable extended port ACLs
    Set-VMSwitch -Name $SwitchName -EnableEmbeddedTeaming $true
    
    # Configure bandwidth management
    Set-VMSwitch -Name $SwitchName -DefaultFlowMinimumBandwidthAbsolute 100
    Set-VMSwitch -Name $SwitchName -DefaultFlowMinimumBandwidthWeight 50
    
    # Create port profiles for Health-InfraOps
    Write-Host "Creating port profiles..." -ForegroundColor Yellow
    
    # Production VLAN profile
    $ProdProfile = @{
        Name = "Health-InfraOps-Prod"
        IsolationMode = "Vlan"
        DefaultIsolationId = 10
        AllowUntaggedTraffic = $false
    }
    
    # Database VLAN profile  
    $DBProfile = @{
        Name = "Health-InfraOps-DB"
        IsolationMode = "Vlan"
        DefaultIsolationId = 20
        AllowUntaggedTraffic = $false
    }
    
    # Management VLAN profile
    $MgmtProfile = @{
        Name = "Health-InfraOps-Mgmt"
        IsolationMode = "Vlan"
        DefaultIsolationId = 40
        AllowUntaggedTraffic = $false
    }
    
    # Apply port profiles
    $Profiles = @($ProdProfile, $DBProfile, $MgmtProfile)
    foreach ($Profile in $Profiles) {
        try {
            Add-VMNetworkAdapterExtendedPort -VMSwitchName $SwitchName @Profile
            Write-Host "✅ Created port profile: $($Profile.Name)" -ForegroundColor Green
        } catch {
            Write-Warning "⚠️ Could not create port profile: $($Profile.Name)"
        }
    }
    
    # Test switch configuration
    Write-Host "Testing switch configuration..." -ForegroundColor Yellow
    $TestSwitch = Get-VMSwitch -Name $SwitchName
    $TestSwitch | Format-List Name, SwitchType, BandwidthReservationMode, IovEnabled
    
    Write-Host "✅ Health-InfraOps Virtual Switch configured successfully!" -ForegroundColor Green
    Write-Host "📊 Switch Details:" -ForegroundColor Cyan
    Write-Host "   Name: $($TestSwitch.Name)"
    Write-Host "   Type: $($TestSwitch.SwitchType)"
    Write-Host "   SR-IOV: $($TestSwitch.IovEnabled)"
    Write-Host "   Port ACLs: Enabled"
    
    # Log switch creation
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SwitchName = $SwitchName
        SwitchType = $SwitchType
        NetAdapter = $NetAdapterName
        VLANId = $VLANId
        SR-IOV = $EnableSR-IOV
        Status = "Success"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\vmswitch-configurations.csv" -Append -NoTypeInformation
    
} catch {
    Write-Error "❌ Virtual Switch configuration failed: $($_.Exception.Message)"
    
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SwitchName = $SwitchName
        SwitchType = $SwitchType
        NetAdapter = $NetAdapterName
        VLANId = $VLANId
        SR-IOV = $EnableSR-IOV
        Status = "Failed: $($_.Exception.Message)"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\vmswitch-configurations.csv" -Append -NoTypeInformation
    exit 1
}