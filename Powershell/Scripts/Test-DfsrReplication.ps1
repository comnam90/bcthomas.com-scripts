
Function Test-DFSRReplication {
    [cmdletbinding()]
    param(
        # Accepts an array of DFSR Servers
        [parameter(Mandatory=$false)]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        # Accepts a specific GroupName or a willdcard.
        [string]$GroupName = "*",
        # Accepts an array of Folders to look for in DFSR
        [string[]]$Folder,
        # Name of the file to create for replication testing.
        [string]$FileName = "DFSRTest_$(Get-Date -Format yyyyMMddmmhhss).txt",
        # Specifies a timeout period in minutes to wait for replication to complete
        [int32]$Timeout = 5
    )

    Foreach($SourceComputer in $ComputerName){
        $DFSRConnections = Get-DfsrConnection -SourceComputerName $SourceComputer -GroupName $GroupName

        if( -not $DFSRConnections.Count -ge 1){
            Write-Warning "No connections found matching criteria - Source Computer: $SourceComputer; Group Name: $GroupName"
            Continue
        }
        else{
            Write-Verbose "Found $($DFSRConnections.Count) connections for $SourceComputer"
        }

        Foreach ($Connection in $DFSRConnections) {
            Write-Verbose "  $SourceComputer has a connection to DFSR Group $($Connection.GroupName)"
            $DFSRMemberships = Get-DfsrMembership -GroupName $Connection.GroupName | Group -Property GroupName

            Foreach($Group in $DFSRMemberships){

                $DFSRMembership = $Group.Group

                if(!$PSBoundParameters['Folder']){
                    $Folder = $DFSRMembership.foldername | Sort-Object | Get-Unique
                }

                foreach ($FolderName in $Folder) {
                    Write-Verbose "    Finding members of $FolderName Folder in Group $($Group.Name)"
                    $Memberships = $DFSRMembership.where{ $_.FolderName -ieq $FolderName }
                    if( -not $Memberships -ge 1){
                        Write-Warning "$FolderName Folder not found in any of the DFSR Memberships for $SourceComputer"
                        Continue
                    }
                    else{
                        $Computers = $Memberships.ComputerName
                        $Exclude = $Memberships.Where{ $_.ReadOnly -eq $true } | Select-Object ComputerName

                        Foreach ($Computer in $Computers) {
                            if ($Computer -inotin $Exclude) {
                                Write-Verbose "      Identifying $Computer's replication partners"
                                $Targets = $Computers.where{ $_ -ine $Computer }
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

} # Function Test-DFSRReplication
