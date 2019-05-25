<#
This file contains powershell functions, designed to make it easier
to perform maintenance on S2D Clusters and nodes.

Dot source the file to import the functions
eg. PS> . C:\Scripts\S2D-Maintenance.ps1

Functions:
- Enable-S2DNodeMaintenance
- Disable-S2DNodeMaintenance
- Get-S2DNodeMaintenanceState

Maintained by: Ben Thomas (@NZ_BenThomas)
Version: 1.0.1
Last Updated: 2019-05-25
Website: https://bcthomas.com

Changelog:
 - 1.0.0
  - Initial Commit
 - 1.0.1
  - Added verbose output
#>

Function Enable-S2DNodeMaintenance { 
    [cmdletbinding()]
    Param(
        [alias('ComputerName', 'StorageNodeFriendlyName')]
        [string]$Name = $Env:ComputerName,
        [switch]$OnlyCluster,
        [switch]$OnlyStorage
    )
    begin {
        Write-Verbose "Checking that the required powershell modules are available"
        $AvailableModules = Get-Module -ListAvailable
        if ( $AvailableModules.Name -inotcontains "FailoverClusters" -or $AvailableModules.Name -inotcontains "Storage" ) {
            throw "Required modules FailoverClusters and Storage are not available"
        }
    }
    process {
        Write-Verbose "Checking that all volumes are currently healthy before enabling maintenance"
        $UnhealthyDisks = Get-VirtualDisk -CimSession $Name | Where-Object { 
            $_.HealthStatus -ine "Healthy" -and $_.OperationalStatus -ine "OK" 
        }
        if ($UnhealthyDisks.Count -gt 0) {
            throw "Cannot enter maintenance mode as the follow volumes are unhealthy`n$($UnhealthyDisks.FriendlyName -join ", ")"
        }
        if ( -not $OnlyStorage ) {
            Write-Verbose "Pausing and draining $Name"
            $ClusterName = Get-Cluster -Name $Name | Select-Object -ExpandProperty Name
            $NodeState = (Get-ClusterNode -Name $Name -Cluster $ClusterName).State
            if ( $NodeState -ieq 'Up' ) {
                Suspend-ClusterNode -Name $Name -Drain -Cluster $ClusterName -Wait | Out-Null
            }
            elseif ($NodeState -ieq 'Paused') {
                Write-Verbose "Skipping $Name as it is already paused"
            }
            else {
                Write-Warning "$Name is currently $NodeState"
            }
        }
        if ( -not $OnlyCluster ) {
            Write-Verbose "Enabling Storage Maintenance Mode on disks in $Name"
            $ScaleUnit = Get-StorageFaultDomain -Type StorageScaleUnit -CimSession $Name | Where-Object { $_.FriendlyName -eq $Name }
            $ScaleUnit | Enable-StorageMaintenanceMode -CimSession $Name | Out-Null
            Start-Sleep -Seconds 5
        }
    }
    end {
        Write-Verbose "Returning current state of host"
        Get-S2DNodeMaintenanceState -Name $Name
    }
}

Function Disable-S2DNodeMaintenance {
    [cmdletbinding()]
    Param(
        [alias('ComputerName', 'StorageNodeFriendlyName')]
        [string]$Name = $Env:ComputerName,
        [switch]$OnlyCluster,
        [switch]$OnlyStorage
    )
    begin {
        Write-Verbose "Checking that the required powershell modules are available"
        $AvailableModules = Get-Module -ListAvailable
        if ( $AvailableModules.Name -inotcontains "FailoverClusters" -or $AvailableModules.Name -inotcontains "Storage" ) {
            throw "Required modules FailoverClusters and Storage are not available"
        }
    }
    process {
        if ( -not $OnlyCluster ) {
            Write-Verbose "Disabling Storage Maintenance Mode on disks in $Name"
            $ScaleUnit = Get-StorageFaultDomain -Type StorageScaleUnit -CimSession $Name | Where-Object { $_.FriendlyName -eq $Name }
            $ScaleUnit | Disable-StorageMaintenanceMode -CimSession $Name | Out-Null
            Start-Sleep -Seconds 5
        }
        if ( -not $OnlyStorage ) {
            Write-Verbose "Resuming $Name and moving roles back"
            $ClusterName = Get-Cluster -Name $Name | Select-Object -ExpandProperty Name
            $NodeState = (Get-ClusterNode -Name $Name -Cluster $ClusterName).State
            if ( $NodeState -ieq 'Paused' ) {
                Resume-ClusterNode -Name $Name -Failback Immediate -Cluster $ClusterName | Out-Null
            }
            elseif ($NodeState -ieq "Up") {
                Write-Verbose "Skipping $Name as it is not currently paused"
            }
            else {
                Write-Warning "$Name is currently $NodeState"
            }
        }
    }
    end {
        Write-Verbose "Returning current state of $Name"
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
        Write-Verbose "Checking that the required powershell modules are available"
        $AvailableModules = Get-Module -ListAvailable
        if ( $AvailableModules.Name -inotcontains "FailoverClusters" -or $AvailableModules.Name -inotcontains "Storage" ) {
            throw "Required modules FailoverClusters and Storage are not available"
        }
        if ($PSCmdlet.ParameterSetName -ieq 'Cluster') {
            Write-Verbose "Execution context: Cluster"
            Write-Verbose "Getting Node to Cluster mappings"
            $NodeMappings = @{ }
            $Name = foreach ($S2DCluster in $Cluster) {
                $Nodes = Get-ClusterNode -Cluster $S2DCluster | Select-Object -ExpandProperty Name
                Foreach ($Node in $Nodes) {
                    Write-Verbose "$Node is part of $S2DCluster"
                    $NodeMappings[$Node] = $S2DCluster
                }
                $Nodes
            }
        }
        $results = @()
    }
    process {
        Foreach ($ClusterNode in $Name) {
            Write-Verbose "$ClusterNode - Starting to gather state info"
            Write-Verbose "$ClusterNode - Gather physical disk details"
            $NodeDisks = Get-StorageSubSystem clu* -CimSession $ClusterNode | 
            Get-StorageNode | Where-Object { $_.Name -ilike "*$ClusterNode*" } | 
            Get-PhysicalDisk -PhysicallyConnected -CimSession $ClusterNode

            Write-Verbose "$ClusterNode - Gather Cluster Name"
            if ($PSCmdlet.ParameterSetName -ieq 'Node') {
                $ClusterName = Get-Cluster -Name $ClusterNode | Select-Object -ExpandProperty Name
            }
            else {
                $ClusterName = $NodeMappings[$ClusterNode]
            }
            Write-Verbose "$ClusterNode - Gather Cluster Node State"
            $ClusterNodeState = Get-ClusterNode -Name $ClusterNode -Cluster $ClusterName | Select-Object -ExpandProperty State 
            Write-Verbose "$ClusterNode - Gather Storage Node State"
            $StorageNodeState = switch ($NodeDisks.Where( { $_.OperationalStatus -icontains "In Maintenance Mode" } ).Count) {
                0 { "Up"; Break }
                { $_ -lt $NodeDisks.Count } { "PartialMaintenance"; Break }
                { $_ -eq $NodeDisks.Count } { "InMaintenance"; Break }
                default { "UNKNOWN" }
            }
            Write-Verbose "$ClusterNode - Compile results"
            $Results += [pscustomobject][ordered]@{
                Cluster      = $ClusterName
                Name         = $ClusterNode
                ClusterState = $ClusterNodeState
                StorageState = $StorageNodeState
            }
        }
    }
    end {
        Write-Verbose "Return state details"
        $results
    }
}
