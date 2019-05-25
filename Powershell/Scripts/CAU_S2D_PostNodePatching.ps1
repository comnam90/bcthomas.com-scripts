
# Get required information and variables
$ComputerName = $env:COMPUTERNAME
$ScaleUnit = Get-StorageFaultDomain -Type StorageScaleUnit | Where-Object { $_.FriendlyName -eq $ComputerName }

# Exit Storage Maintenance Mode
try {
    $ScaleUnit | Disable-StorageMaintenanceMode -ErrorAction Stop
}
catch {
    throw "Failed to exit storage maintenance mode, try again"
}
