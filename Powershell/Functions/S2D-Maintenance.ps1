# dot source to import a number of helper functions for performing maintenance
# on S2D Clusters

# Functions
## Enable-S2DNodeMaintenance
## Disable-S2DNodeMaintenance
## Get-S2DNodeMaintenanceState

Function Enable-S2DNodeMaintenance { }

Function Disable-S2DNodeMaintenance {
    [cmdletbinding()]
    Param(
        [alias('ComputerName', 'StorageNodeFriendlyName')]
        [string]$Name = $Env:ComputerName,
        [switch]$OnlyCluster,
        [switch]$OnlyStorage
    )
    begin {
        $AvailableModules = Get-Module -ListAvailable
        if( $AvailableModules.Name -inotcontains "FailoverClusters" -or $AvailableModules.Name -inotcontains "Storage" ){
            throw "Required modules FailoverClusters and Storage are not available"
        }
    }
    process {
        if ( -not $OnlyCluster ) {
            $ScaleUnit = Get-StorageFaultDomain -Type StorageScaleUnit -CimSession $Name | Where-Object { $_.FriendlyName -eq $Name }
            $ScaleUnit | Disable-StorageMaintenanceMode -CimSession $Name | Out-Null
            Start-Sleep -Seconds 5
        }
        if ( -not $OnlyStorage ) {
            $ClusterName = Get-Cluster -Name $Name | Select-Object -ExpandProperty Name
            if ( (Get-ClusterNode -Name $Name -Cluster $ClusterName).State -ieq 'Paused' ) {
                Resume-ClusterNode -Name $Name -Failback Immediate -Cluster $ClusterName | Out-Null
            }
        }
    }
    end {
        Get-S2DNodeMaintenanceState -Name $Name
    }
}

Function Get-S2DNodeMaintenanceState {
    [cmdletbinding(DefaultParameterSetName = "Node")]
    Param(
        [parameter(ParameterSetName = "Node")]
        [alias('ComputerName')]
        [string[]]$Name = $Env:ComputerName,
        [parameter(ParameterSetName = "Cluster")]
        [string[]]$Cluster
    )
    begin {
        $AvailableModules = Get-Module -ListAvailable
        if( $AvailableModules.Name -inotcontains "FailoverClusters" -or $AvailableModules.Name -inotcontains "Storage" ){
            throw "Required modules FailoverClusters and Storage are not available"
        }
        if ($PSCmdlet.ParameterSetName -ieq 'Cluster') {
            $NodeMappings = @{ }
            $Name = foreach ($S2DCluster in $Cluster) {
                $Nodes = Get-ClusterNode -Cluster $S2DCluster | Select-Object -ExpandProperty Name
                Foreach ($Node in $Nodes) {
                    $NodeMappings[$Node] = $S2DCluster
                }
                $Nodes
            }
        }
        $results = @()
    }
    process {
        Foreach ($ClusterNode in $Name) {
            $NodeDisks = Get-StorageSubSystem clu* -CimSession $ClusterNode | 
            Get-StorageNode | Where-Object { $_.Name -ilike "*$ClusterNode*" } | 
            Get-PhysicalDisk -PhysicallyConnected -CimSession $ClusterNode

            if ($PSCmdlet.ParameterSetName -ieq 'Node') {
                $ClusterName = Get-Cluster -Name $ClusterNode | Select-Object -ExpandProperty Name
            }
            else {
                $ClusterName = $NodeMappings[$ClusterNode]
            }
            $ClusterNodeState = Get-ClusterNode -Name $ClusterNode -Cluster $ClusterName | Select-Object -ExpandProperty State 
            $StorageNodeState = switch ($NodeDisks.Where( { $_.OperationalStatus -icontains "In Maintenance Mode" } ).Count) {
                0 { "Up"; Break }
                { $_ -lt $NodeDisks.Count } { "PartialMaintenance"; Break }
                { $_ -eq $NodeDisks.Count } { "InMaintenance"; Break }
                default { "UNKNOWN" }
            }
            $Results += [pscustomobject][ordered]@{
                Cluster      = $ClusterName
                Name         = $ClusterNode
                ClusterState = $ClusterNodeState
                StorageState = $StorageNodeState
            }
        }
    }
    end {
        $results
    }
}
