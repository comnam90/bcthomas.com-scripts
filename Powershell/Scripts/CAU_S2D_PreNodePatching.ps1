
# Get required information and variables
$ComputerName = $env:COMPUTERNAME
$ScaleUnit = Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object { $_.FriendlyName -eq $ComputerName }
$WitnessCheck = Get-ClusterResource -Name *Witness -ErrorAction SilentlyContinue
$ClusterPhysicalDisks = Get-StoragePool S2D* | Get-PhysicalDisk
$NodePhysicalDisks = $ScaleUnit | Get-PhysicalDisk

# Check cluster has a witness configured
if ($WitnessCheck.length -eq 0) {
    # Thow error as we don't have a witness configured.
    Write-Error -Message "No Witness Role configured for $( (Get-Cluster).Name )" `
        -RecommendedAction "Setup a File Share or Cloud Witness for Cluster Quorum." `
        -Exception
}

# Check all virtual disks are is healthy
do {
    $VirtualDisks = Get-VirtualDisk
    $UnhealthyDisks = $VirtualDisks | Where-Object { 
        $_.HealthStatus -ine "Healthy" -and $_.OperationalStatus -ine "OK" 
    }
}until(
    $UnhealthyDisks.length -eq 0
)

# Check there are no disks from other nodes already in maintenance mode
if ( $ClusterPhysicalDisks.where( 
        { $_.OperationalStatus -ilike "*Maintenance*" -and $_.SerialNumber -inotin $NodePhysicalDisks.SerialNumber } 
    ).Count -gt 0 ) {
    # Throw error as we don't want to continue if other nodes have disks still in maintenance mode
    Write-Error -Message "There are disks in the cluster already in maintenance mode" `
        -RecommendedAction "Make sure any existing nodes have been taken out of maintenance mode successfully before continuing." `
        -Exception
}

# Enter Storage Maintenance Mode
try {
    # Suspend cluster node first, otherwise CAU will fail to pause it after this script finishes
    Suspend-ClusterNode -Name $ComputerName -Drain:$true -RetryDrainOnFailure:$true -Wait:$true -Confirm:$false -ErrorAction Stop
    # Actually enable maintenance mode
    $ScaleUnit | Enable-StorageMaintenanceMode -ErrorAction Stop
}
catch {
    # Make sure node is brought back out of maintenance
    $ScaleUnit | Disable-StorageMaintenanceMode 
    Resume-ClusterNode -Name $ComputerName -Failback:$true -Confirm:$false
    throw "Failed to enter storage maintenance mode, try again"
}
