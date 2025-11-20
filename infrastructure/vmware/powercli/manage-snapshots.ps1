# Health-InfraOps VMware Snapshot Management

param(
    [Parameter(Mandatory=$true)]
    [string]$Action,  # create, list, remove, remove-all
    
    [string]$VMName,
    [string]$SnapshotName,
    [string]$Description = "Health-InfraOps Automated Snapshot",
    [switch]$Quiesce = $true,
    [switch]$Memory = $false
)

# vCenter connection
$vCenterServer = "vcenter.infokes.co.id"
$Username = "health-infraops-admin"

function Connect-vCenter {
    try {
        $Password = Read-Host -Prompt "Enter vCenter password" -AsSecureString
        Connect-VIServer -Server $vCenterServer -User $Username -Password ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) -ErrorAction Stop
        return $true
    } catch {
        Write-Error "❌ Failed to connect to vCenter: $($_.Exception.Message)"
        return $false
    }
}

function Create-Snapshot {
    param($VM, $Name, $Desc, $Quiesce, $Memory)
    
    try {
        $Snapshot = New-Snapshot -VM $VM -Name $Name -Description $Desc -Quiesce:$Quiesce -Memory:$Memory -Confirm:$false
        Write-Host "✅ Snapshot created: $Name" -ForegroundColor Green
        return $Snapshot
    } catch {
        Write-Error "❌ Failed to create snapshot: $($_.Exception.Message)"
        return $null
    }
}

function Get-Snapshots {
    param($VMName)
    
    if ($VMName) {
        $VMs = Get-VM -Name $VMName
    } else {
        $VMs = Get-VM -Location (Get-Folder -Name "Health-InfraOps" -ErrorAction SilentlyContinue)
    }
    
    foreach ($VM in $VMs) {
        Write-Host "📋 Snapshots for $($VM.Name):" -ForegroundColor Cyan
        $Snapshots = Get-Snapshot -VM $VM
        if ($Snapshots) {
            $Snapshots | Format-Table Name, Description, Created, SizeMB -AutoSize
        } else {
            Write-Host "   No snapshots found" -ForegroundColor Yellow
        }
    }
}

function Remove-Snapshot {
    param($VMName, $SnapshotName, [switch]$RemoveAll)
    
    $VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $VM) {
        Write-Error "❌ VM not found: $VMName"
        return
    }
    
    if ($RemoveAll) {
        Write-Host "🗑️ Removing all snapshots for $VMName..." -ForegroundColor Yellow
        Get-Snapshot -VM $VM | Remove-Snapshot -Confirm:$false
        Write-Host "✅ All snapshots removed" -ForegroundColor Green
    } else {
        $Snapshot = Get-Snapshot -VM $VM -Name $SnapshotName -ErrorAction SilentlyContinue
        if ($Snapshot) {
            Write-Host "🗑️ Removing snapshot: $SnapshotName" -ForegroundColor Yellow
            Remove-Snapshot -Snapshot $Snapshot -Confirm:$false
            Write-Host "✅ Snapshot removed" -ForegroundColor Green
        } else {
            Write-Error "❌ Snapshot not found: $SnapshotName"
        }
    }
}

# Main execution
if (-not (Connect-vCenter)) {
    exit 1
}

try {
    switch ($Action.ToLower()) {
        "create" {
            if (-not $VMName -or -not $SnapshotName) {
                Write-Error "❌ VMName and SnapshotName are required for create action"
                break
            }
            
            $VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if (-not $VM) {
                Write-Error "❌ VM not found: $VMName"
                break
            }
            
            $Snapshot = Create-Snapshot -VM $VM -Name $SnapshotName -Desc $Description -Quiesce $Quiesce -Memory $Memory
            
            # Log snapshot creation
            if ($Snapshot) {
                $LogEntry = @{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Action = "Create"
                    VM = $VMName
                    Snapshot = $SnapshotName
                    SizeMB = $Snapshot.SizeMB
                    Status = "Success"
                }
                $LogEntry | Export-Csv -Path "C:\Health-InfraOps\snapshot-management.csv" -Append -NoTypeInformation
            }
        }
        
        "list" {
            Get-Snapshots -VMName $VMName
        }
        
        "remove" {
            if (-not $VMName) {
                Write-Error "❌ VMName is required for remove action"
                break
            }
            Remove-Snapshot -VMName $VMName -SnapshotName $SnapshotName
        }
        
        "remove-all" {
            if (-not $VMName) {
                Write-Error "❌ VMName is required for remove-all action"
                break
            }
            Remove-Snapshot -VMName $VMName -RemoveAll
        }
        
        default {
            Write-Error "❌ Invalid action: $Action. Use create, list, remove, or remove-all"
        }
    }
} finally {
    Disconnect-VIServer -Server * -Confirm:$false
    Write-Host "🔒 Disconnected from vCenter" -ForegroundColor Green
}