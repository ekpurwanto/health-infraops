# Health-InfraOps VMware VM Deployment Script
# Requires VMware PowerCLI module

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
    
    [Parameter(Mandatory=$true)]
    [string]$Datastore,
    
    [int]$MemoryGB = 4,
    [int]$NumCpu = 2,
    [string]$Network = "VM Network",
    [string]$Folder = "Health-InfraOps",
    [string]$CustomizationSpec = "Linux-Server"
)

# Import VMware PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Host "✅ VMware PowerCLI module loaded" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to load VMware PowerCLI module"
    exit 1
}

# vCenter connection parameters
$vCenterServer = "vcenter.infokes.co.id"
$Username = "health-infraops-admin"
$Password = Read-Host -Prompt "Enter vCenter password" -AsSecureString

try {
    # Connect to vCenter
    Connect-VIServer -Server $vCenterServer -User $Username -Password ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)))
    Write-Host "✅ Connected to vCenter: $vCenterServer" -ForegroundColor Green
    
    # Check if template exists
    $Template = Get-Template -Name $TemplateName -ErrorAction SilentlyContinue
    if (-not $Template) {
        Write-Error "❌ Template '$TemplateName' not found"
        Disconnect-VIServer -Confirm:$false
        exit 1
    }
    
    # Check if folder exists, create if not
    $VMFolder = Get-Folder -Name $Folder -ErrorAction SilentlyContinue
    if (-not $VMFolder) {
        Write-Host "📁 Creating folder: $Folder" -ForegroundColor Yellow
        $VMFolder = New-Folder -Name $Folder -Location (Get-Folder -Name "vm")
    }
    
    # VM Deployment
    Write-Host "🚀 Deploying VM: $VMName" -ForegroundColor Green
    
    $VM = New-VM -Name $VMName `
        -Template $Template `
        -Datastore $Datastore `
        -VMHost (Get-VMHost | Get-Random) `
        -Location $VMFolder `
        -ErrorAction Stop
    
    # Configure VM settings
    Write-Host "⚙️ Configuring VM settings..." -ForegroundColor Yellow
    $VM | Set-VM -MemoryGB $MemoryGB -NumCpu $NumCpu -Confirm:$false
    
    # Configure network
    $VM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $Network -Confirm:$false
    
    # Apply customization spec
    if ($CustomizationSpec) {
        try {
            $VM | Set-VM -OSCustomizationSpec (Get-OSCustomizationSpec -Name $CustomizationSpec) -Confirm:$false
            Write-Host "✅ Applied customization spec: $CustomizationSpec" -ForegroundColor Green
        } catch {
            Write-Warning "⚠️ Could not apply customization spec: $CustomizationSpec"
        }
    }
    
    # Start VM
    Write-Host "🔌 Starting VM..." -ForegroundColor Yellow
    $VM | Start-VM -Confirm:$false
    
    # Wait for VM tools and get IP
    Write-Host "⏳ Waiting for VM Tools..." -ForegroundColor Yellow
    $IPAddress = $null
    $timeout = 300  # 5 minutes
    $timer = 0
    
    while ($timer -lt $timeout) {
        $VMView = $VM | Get-View
        if ($VMView.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
            $IPAddress = $VMView.Guest.IPAddress | Where-Object { $_ -like "10.0.*" }
            if ($IPAddress) {
                break
            }
        }
        Start-Sleep -Seconds 10
        $timer += 10
    }
    
    if ($IPAddress) {
        Write-Host "✅ VM deployed successfully!" -ForegroundColor Green
        Write-Host "📊 VM Details:" -ForegroundColor Cyan
        Write-Host "   Name: $VMName"
        Write-Host "   IP Address: $IPAddress"
        Write-Host "   Memory: $MemoryGB GB"
        Write-Host "   vCPU: $NumCpu"
        Write-Host "   Power State: $($VM.PowerState)"
    } else {
        Write-Warning "⚠️ VM deployed but could not retrieve IP address"
    }
    
    # Log deployment
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        VMName = $VMName
        IPAddress = $IPAddress
        MemoryGB = $MemoryGB
        NumCpu = $NumCpu
        Status = "Success"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\vm-deployments.csv" -Append -NoTypeInformation
    
} catch {
    Write-Error "❌ Deployment failed: $($_.Exception.Message)"
    
    # Log failure
    $LogEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        VMName = $VMName
        IPAddress = "N/A"
        MemoryGB = $MemoryGB
        NumCpu = $NumCpu
        Status = "Failed: $($_.Exception.Message)"
    }
    
    $LogEntry | Export-Csv -Path "C:\Health-InfraOps\vm-deployments.csv" -Append -NoTypeInformation
    
} finally {
    # Disconnect from vCenter
    if ($global:DefaultVIServers.Count -gt 0) {
        Disconnect-VIServer -Server * -Confirm:$false
        Write-Host "🔒 Disconnected from vCenter" -ForegroundColor Green
    }
}