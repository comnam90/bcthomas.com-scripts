<#
    .Synopsis
    Tests replication between DFS-R Partners is working
    .Description
    This script is designed to query replication groups and folders for a
    server, and then test replication to and from all replication partners.
    It creates a file in each replicated folder, and waits for the file to
    become available on the replication partner or reach a timeout.
    .Parameter ComputerName
    One or more servers running DFS-R
    .Parameter GroupName
    (Optional) The name of a DFS-R the server should be part of.
    .Parameter Folder
    (Optional) A specific folder to test.
    .Parameter FileName
    (Optional) The name of the test file that will be created.
    .Parameter Timeout
    (Optional) Number of minutes to wait for replication to complete.
    .Example
    > Test-DfsrReplication -ComputerName DFSR01
    This will find all DFS-R Groups and folders on DFSR01, and the servers
    that DFSR01 replications with. It will create test files on each of the
    folders, and measure the time it takes to replicate to the DFS-R 
    partners. If the partner's aren't read-only, it will also test replication
    back in the other direction.
    .Example
    > Test-DfsrReplication -ComputerName DFSR01 -GroupName "User Data"
    This will only test folders on DFSR01 that are part of the "User Data"
    DFS-R Group.
    .Example
    > Test-DfsrReplication -ComputerName DFSR01 -Folder "Data"
    This will only test the "Data" folder on DFSR01 and it's replication
    partners.
    .Example
    > Test-DfsrReplication -ComputerName DFSR01 -Timeout 10
    This will extend the timeout period from the default 5 minutes to
    10 minutes. It can be useful for slow links between DFS-R partners
    and also for servers with high change that might have a backlog.
    .Notes
    ----------------------------------------------------------
    Version: 1.1.0
    Maintained By: Ben Thomas (@NZ_BenThomas)
    Last Updated: 2019-10-13
    ----------------------------------------------------------
    CHANGELOG:
        1.1.0
            - Added -OneWay switch
        1.0.0
            - Initial Version
#>
[cmdletbinding()]
param(
    # Accepts an array of DFSR Servers
    [parameter(Mandatory = $false)]
    [alias("SourceComputer")]
    [string[]]$ComputerName = $env:COMPUTERNAME,
    # Accepts a specific GroupName or a willdcard.
    [string]$GroupName = "*",
    # Accepts an array of Folders to look for in DFSR
    [alias("FolderName")]
    [string[]]$Folder,
    # Name of the file to create for replication testing.
    [string]$FileName = "DFSRTest_$(Get-Date -Format yyyyMMddmmhhss).txt",
    # Specifies a timeout period in minutes to wait for replication to complete
    [int32]$Timeout = 5,
    # Tests replication only in one direction
    [switch]$OneWay
)

Foreach ($SourceComputer in $ComputerName) {
    $DFSRConnections = Get-DfsrConnection -SourceComputerName $SourceComputer -GroupName $GroupName

    if ( -not $DFSRConnections.Count -ge 1) {
        Write-Warning "No connections found matching criteria - Source Computer: $SourceComputer; Group Name: $GroupName"
        Continue
    }
    else {
        Write-Verbose "Found $($DFSRConnections.Count) connections for $SourceComputer"
    }

    Foreach ($Connection in $DFSRConnections) {
        Write-Verbose "  $SourceComputer has a connection to DFSR Group $($Connection.GroupName)"
        $Groups = Get-DfsrMembership -GroupName $Connection.GroupName | Group-Object -Property GroupName

        Foreach ($Group in $Groups) {

            $DFSRMembership = $Group.Group

            if (!$PSBoundParameters['Folder']) {
                $Folder = $DFSRMembership.foldername | Sort-Object | Get-Unique
            }

            foreach ($FolderName in $Folder) {
                Write-Verbose "    Finding members of $FolderName Folder in Group $($Group.Name)"
                $Memberships = $DFSRMembership.where{ $_.FolderName -ieq $FolderName }
                if ( -not $Memberships -ge 1) {
                    Write-Warning "$FolderName Folder not found in any of the DFSR Memberships for $SourceComputer"
                    Continue
                }
                else {
                    if ( -not $OneWay) {
                        $Computers = $Memberships.ComputerName
                    }
                    else {
                        $Computers = $SourceComputer
                    }
                    $Exclude = $Memberships.Where{ $_.ReadOnly -eq $true } | Select-Object ComputerName

                    Foreach ($Computer in $Computers) {
                        if ($Computer -inotin $Exclude) {
                            Write-Verbose "      Identifying $Computer's replication partners"
                            $Targets = $Memberships.ComputerName.where{ $_ -ine $Computer }
                            $SourceFolder = $Memberships.Where{ $_.ComputerName -ieq $Computer }.ContentPath.Replace(':', '$')
                            $SourcePath = "\\$($Computer)\$($SourceFolder)\"

                            foreach ($Target in $Targets) {
                                Write-Verbose "        Testing replication to $Target"
                                $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
                                $TargetFolder = $Memberships.Where{ $_.ComputerName -ieq $Target }.ContentPath.Replace(':', '$')
                                $TargetPath = "\\$($Target)\$($TargetFolder)"
                                $TempFile = New-Item -ItemType File -Path $SourcePath -Name "$($Target)_$($FileName)"
                                Write-Verbose "          Source: $($TempFile.FullName)"
                                Write-Verbose "          Target: $TargetPath\$($TempFile.Name)"
                                $Result = $false

                                do {
                                    $Result = Test-Path -Path "$TargetPath\$($TempFile.Name)"
                                }until(
                                    $Result -eq $true -or `
                                        $Stopwatch.Elapsed.TotalMinutes -ge $timeout
                                )

                                [pscustomobject][ordered]@{
                                    GroupName             = $Group.Name
                                    FolderName            = $FolderName
                                    SourceComputer        = $Computer
                                    TargetComputer        = $Target
                                    ReplicationSuccessful = $Result
                                    ElapsedTime           = $StopWatch.Elapsed.TotalSeconds
                                }

                                $TempFile | Remove-Item -Force
                                $StopWatch.Restart()

                            } # Foreach Target

                        } # If not in Exclude

                    } # Foreach Computer

                } # If Not Found in Memberships

            } # Foreach FolderName

        } # Foreach Group

    } # Foreach Connection

} # Foreach SourceComputer
