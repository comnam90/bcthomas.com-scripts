<#
    .SYNOPSIS
        Query a cluster for cache daily write stats
    .DESCRIPTION
        Makes use of the 'Get-StorageHistory' command and the Cluster Performance
        History database to display stats for each cache drive in a cluster, such as
        estimated Drive Writes per Day (DWPD), average daily writes, and average
        write throughput.
    .EXAMPLE
        PS C:\> Get-S2DCacheChurn -Cluster S2D-Cluster -anonymize | Format-Table -AutoSize

        Returns a table containing each of the disks in each node in the Cluster 'S2D-Cluster'
        but the Cluster name and the Node names have been swapped out with generic values

        Cluster  ComputerName Disk   Size      EstDwpd AvgDailyWrite AvgWriteThroughput AvgCacheUsage
        -------  ------------ ----   ----      ------- ------------- ------------------ -------------
        Cluster1 Node1        Slot 0 745.21 GB 1.6x    1.18 TB       19.71 MB/s         3.35 GB
        Cluster1 Node1        Slot 1 745.21 GB 1.0x    756.15 GB     12.30 MB/s         21.51 GB
        Cluster1 Node1        Slot 2 745.21 GB 1.8x    1.28 TB       21.25 MB/s         4.45 GB
        Cluster1 Node1        Slot 3 745.21 GB 1.4x    1.02 TB       16.92 MB/s         2.44 GB
        Cluster1 Node2        Slot 0 745.21 GB 1.3x    1,000.90 GB   16.17 MB/s         2.23 GB
        Cluster1 Node2        Slot 1 745.21 GB 1.3x    932.73 GB     15.08 MB/s         2.05 GB
        Cluster1 Node2        Slot 2 745.21 GB 1.5x    1.11 TB       18.45 MB/s         2.86 GB
        Cluster1 Node2        Slot 3 745.21 GB 1.5x    1.09 TB       18.07 MB/s         2.49 GB
    .INPUTS
        None
    .OUTPUTS
        PSCustomObject
    .NOTES
        Written by: Ben Thomas (@NZ_BenThomas)
        Created: 2020/02/23
        URL: https://bcthomas.com
    #>
[cmdletbinding()]
param(
    # List of clusters to query
    [parameter(Mandatory)]
    [string[]]$cluster,
    # (Optional) Only query the last 24 hours
    [switch]$lastDay,
    # (Optional) Anonymize resource names
    [switch]$anonymize
)
begin {
    # Helper Functions
    function New-S2DCacheDiskObj {
        param (
            [string]$FriendlyName = $null,
            [string]$PhysicalLocation = $Null,
            [string]$SerialNumber = $null
        )
        $Object = New-Module -AsCustomObject -ScriptBlock {
            [string]$FriendlyName = $null
            [string]$PhysicalLocation = $Null
            [string]$SerialNumber = $null

            Function ToString {
                return ("{0}" -f $PhysicalLocation)
            }

            function ToLongString {
                return ("{0}|{1}|{2}" -f $PhysicalLocation, $FriendlyName, $SerialNumber)
            }
            Export-ModuleMember -Variable * -Function *
        }
        $Object.FriendlyName = $FriendlyName
        $Object.PhysicalLocation = $PhysicalLocation
        $Object.SerialNumber = $SerialNumber

        Return $Object
    }

    function Format-Bytes {
        param(
            $Bytes
        )
        switch ([math]::Truncate([Math]::log($Bytes, 1024))) {
            0 { "{0} B" -f $Bytes }
            1 { "{0:N2} KB" -f ($Bytes / 1KB) }
            2 { "{0:N2} MB" -f ($Bytes / 1MB) }
            3 { "{0:N2} GB" -f ($Bytes / 1GB) }
            4 { "{0:N2} TB" -f ($Bytes / 1TB) }
            5 { "{0:N2} PB" -f ($Bytes / 1PB) }
        }
    }
        
    # Establish Variables
    $ClusterCounter = 0
}
Process {
    Foreach ($PSItem in $Cluster) {
        Try {
            # Check Cluster Version is Supported
            Write-Verbose "[$((Get-Date).ToShortTimeString())]$PSItem - Checking the storage pool is compatible"
            $SPVersion = Invoke-Command -ComputerName $PSItem -ScriptBlock {
                Get-StoragePool S2D* -IsPrimordial:$false -Verbose:$false | Select-Object FriendlyName, Version
            }
            if ($SPVersion.Version -inotlike "*2019*") {
                Throw "[$((Get-Date).ToShortTimeString())]Skipping $PSItem because it is incompatible.`nStorage Pool: $($SPVersion.FriendlyName)`nCurrent level: $($SPVersion.Version)`nRequired Level: Windows Server 2019"
            }
        }
        Catch {
            Write-Warning $_.Exception.Message
            Continue
        }
        $ClusterCounter++
        $ClusterName = $PSItem
        # Find Nodes in Cluster
        Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - Querying the cluster for nodes"
        $Nodes = Get-StorageSubSystem CLU* -CimSession $ClusterName -Verbose:$false | `
            Get-StorageNode -CimSession $ClusterName -Verbose:$false
        Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName -   Found $($Nodes.Count) Nodes ($($Nodes.Name -join ','))"
        $NodeCounter = 0
        # Look though Nodes
        ($Nodes | Sort-Object Name).Foreach{
            $NodeCounter++
            $ComputerName = $PSItem.Name.Split(".")[0]
            # Find node Cache Disks
            Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName - Querying the node for Cache Disks"
            $cacheDisks = $PSItem | `
                Get-PhysicalDisk -Usage Journal -PhysicallyConnected -CimSession $ComputerName
            if ($cacheDisks.Count -gt 0) {
                Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName -   Discovered $($cacheDisks.Count) Cache Disks"
                # Loop through Cache Disks
                ($cacheDisks | Sort-Object PhysicalLocation).Foreach{
                    <#
                            Check if we only want the last day of data.
                            Query the storage history for the device and timeframe.
                            Use the timeframe to work out the average daily write.
                        #>
                    if ($lastDay) {
                        Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName - $($PSitem.PhysicalLocation) - Querying last 24 hours of storage history"
                        $StorageHistory = Invoke-Command $Computername {
                            $Using:PSItem | Get-StorageHistory -NumberOfHours 24
                        }
                    }
                    else {
                        Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName - $($PSitem.PhysicalLocation) - Querying available storage history"
                        $StorageHistory = Invoke-Command $Computername {
                            $Using:PSItem | Get-StorageHistory
                        }
                    }
                    $TimePeriod = New-TimeSpan -Start $StorageHistory.StartTime -End $StorageHistory.EndTime
                    $DailyWrite = (
                        $StorageHistory.TotalWriteBytes / $TimePeriod.TotalDays
                    )
                    <#
                            Find the current timeframe returned by storage history.
                            Query the Cluster Performance History database to get the related
                            throughput statistics and find the average write throughput
                        #>
                    $timeframe = switch ($TimePeriod.TotalDays) {
                        { $_ -le 1 } { "LastDay"; break }
                        { $_ -le 8 } { "LastWeek"; break }
                        { $_ -le 35 } { "LastMonth"; break }
                        default { "LastYear"; break }
                    }
                    Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName - $($PSitem.PhysicalLocation) - Querying Cluster Performance History"
                    $clusterPerf = Invoke-Command $Computername {
                        $Using:PSItem | Get-ClusterPerformanceHistory -PhysicalDiskSeriesName PhysicalDisk.Cache.Size.Dirty, PhysicalDisk.Throughput.Write -TimeFrame $Using:timeframe
                    }
                    $avgThroughput = $clusterPerf.Where{ $_.MetricID -ilike "*Throughput*" } | `
                        Measure-Object -Property Value -Average | `
                        Select-Object -ExpandProperty Average
                    $avgUsage = $clusterPerf.Where{ $_.MetricID -ilike "*Dirty*" } | `
                        Measure-Object -Property Value -Average | `
                        Select-Object -ExpandProperty Average

                    <#
                            Format and return the data, anonymizing if required.
                        #>
                    Write-Verbose "[$((Get-Date).ToShortTimeString())]$ClusterName - $ComputerName - $($PSitem.PhysicalLocation) - Formatting results"
                    # Format Cache Disk Object
                    $cacheDiskObj = New-S2DCacheDiskObj -FriendlyName $PSItem.FriendlyName -PhysicalLocation $PSItem.PhysicalLocation -SerialNumber $PSItem.SerialNumber

                    # Return final object
                    if (!$anonymize) {
                        [pscustomobject][ordered]@{
                            Cluster            = $ClusterName
                            ComputerName       = $ComputerName
                            Disk               = $cacheDiskObj
                            Size               = Format-Bytes -Bytes $PSItem.Size
                            EstDwpd            = "{0:N1}x" -f ( $DailyWrite / $PSItem.Size )
                            AvgDailyWrite      = Format-Bytes -Bytes $DailyWrite
                            AvgWriteThroughput = "$(Format-Bytes -Bytes $avgThroughput)/s"
                            AvgCacheUsage      = Format-Bytes -Bytes $avgUsage
                        }
                    }
                    else {
                        # Remove identifiable information
                        $cacheDiskObj.SerialNumber = Get-Random
                        [pscustomobject][ordered]@{
                            Cluster            = "Cluster{0}" -f $ClusterCounter
                            ComputerName       = "Node{0}" -f $NodeCounter
                            Disk               = $cacheDiskObj
                            Size               = Format-Bytes -Bytes $PSItem.Size
                            EstDwpd            = "{0:N1}x" -f ( $DailyWrite / $PSItem.Size )
                            AvgDailyWrite      = Format-Bytes -Bytes $DailyWrite
                            AvgWriteThroughput = "$(Format-Bytes -Bytes $avgThroughput)/s"
                            AvgCacheUsage      = Format-Bytes -Bytes $avgUsage
                        }
                    }
                }
            }
            else {
                Write-Warning "$ClusterName did return any Cache disks for $ComputerName"
                Continue
            }
        }
    }
}
