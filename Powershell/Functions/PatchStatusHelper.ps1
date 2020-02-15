Function Get-OSVersion {
    [cmdletbinding()]
    param(
        [parameter(Position = 0, ValueFromPipelineByPropertyName = $true)]
        [alias("CN", "MachineName")]
        [string]$ComputerName = $Env:COMPUTERNAME
    )
    Write-Verbose "Querying registry on $ComputerName"
    if ($ComputerName -inotin @('Localhost', $Env:COMPUTERNAME)) {
        # Query remote machines via Invoke-Command
        $OSVersionInfo = Invoke-Command -computername $ComputerName -ScriptBlock { Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" }
    } else {
        # Invoke-Command not required when running locally.
        $OSVersionInfo = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    }
    Write-Verbose "Converting to [Version] PSType"
    if ($null -eq $OSVersionInfo.CurrentMajorVersionNumber) {
        [version]$LocalVersion = "{0}.{1}.{2}" -f $OSVersionInfo.CurrentVersion, $OSVersionInfo.CurrentBuild, $OSVersionInfo.UBR
    } else {
        [version]$LocalVersion = "{0}.{1}.{2}.{3}" -f $OSVersionInfo.CurrentMajorVersionNumber, $OSVersionInfo.CurrentMinorVersionNumber, $OSVersionInfo.CurrentBuildNumber, $OSVersionInfo.UBR
    }
    Write-Verbose "Returning resulting object"
    $LocalVersion
}

function New-WUObject {
    param (
        [string]$Name = $null,
        [datetime]$ReleaseDate = (Get-Date),
        [version]$Version = $null,
        [string]$URL = $Null
    )
    $Object = New-Module -AsCustomObject -ScriptBlock {
        [string]$Name = $null
        [datetime]$ReleaseDate = Get-Date
        [version]$Version = $null
        [string]$URL = $Null
    
        Function ToString {
            return ("{0} ({1})" -f $Name, $ReleaseDate.ToShortDateString())
        }

        function ToLongString {
            return ("{0}|{1}|{2}|{3}" -f $Name, $ReleaseDate.ToShortDateString(),$Version.Tostring(),$URL)
        }
        Export-ModuleMember -Variable * -Function *
    }
    $Object.Name = $Name
    $Object.ReleaseDate = $ReleaseDate
    $Object.Version = $Version
    $Object.URL = $URL

    Return $Object
}

Function Get-WindowsUpdateRelease {
    [cmdletbinding()]
    param(
        [ValidateSet(
            10240,
            10586,
            14393,
            15063,
            16299,
            17134,
            17763,
            18362,
            18363
        )]
        $Build,
        [switch]$Latest
    )
    Begin {
        $URLTable = @{
            10240 = "https://support.microsoft.com/en-us/help/4000823"
            10586 = "https://support.microsoft.com/en-us/help/4000824"
            14393 = "https://support.microsoft.com/en-us/help/4000825"
            15063 = "https://support.microsoft.com/en-us/help/4018124"
            16299 = "https://support.microsoft.com/en-us/help/4043454"
            17134 = "https://support.microsoft.com/en-us/help/4099479"
            17763 = "https://support.microsoft.com/en-us/help/4464619"
            18362 = "https://support.microsoft.com/en-us/help/4498140"
            18363 = "https://support.microsoft.com/en-us/help/4498140"
        }
        $Pattern = '^.*\"(?<DateString>\w+\s\d+,\s\d+)\s*[\?\-]\s*(?<KBID>\w+\s*\d+)\s\(OS\sBuilds*\s*\w*\s(?<OSBuild>\d{5}\.\d+)\s*\)\",$'
        $Pattern2 = '^.*\"(?<DateString>\w+\s\d+,\s\d+)\s*[\?\-]\s*(?<KBID>\w+\s*\d+)\s\(OS\sBuilds*\s(?<OSBuild>\d{5}\.\d+)\s\w+\s(?<OSBuildAlternative>.+)\)\",$'
    }
    Process {
        $Lines = @()
        if ($Build) {
            $URLS = $URLTable[$Build]
        } else {
            $URLs = $URLTable.Values | Get-Unique
        }
        foreach ($URL in $URLs) {
            $Data = Invoke-WebRequest $URL -UseBasicParsing -InformationAction SilentlyContinue
            $Lines += $Data.content | findstr.exe /R /C:".*heading.*OS Builds*"
        }
        Write-Verbose "Found $($Lines.Count) Patches"
        $Capture = Switch -regex ($Lines) {
            $Pattern2 {
                Write-Verbose "$_ matches Pattern2"
                New-WUObject -Name $Matches['KBID'] `
                    -ReleaseDate (Get-Date $Matches['DateString']) `
                    -Version ([version]("10.0." + $Matches['OSBuild'])) `
                    -URL ("https://support.microsoft.com/en-us/help/$($Matches['KBID'] -replace 'KB\s*','')")
                New-WUObject -Name $Matches['KBID'] `
                    -ReleaseDate (Get-Date $Matches['DateString']) `
                    -Version ([version]("10.0." + $Matches['OSBuildAlternative'])) `
                    -URL ("https://support.microsoft.com/en-us/help/$($Matches['KBID'] -replace 'KB\s*','')")
                Continue
            }
            $Pattern {
                Write-Verbose "$_ matches Pattern"
                New-WUObject -Name $Matches['KBID'] `
                    -ReleaseDate (Get-Date $Matches['DateString']) `
                    -Version ([version]("10.0." + $Matches['OSBuild'])) `
                    -URL ("https://support.microsoft.com/en-us/help/$($Matches['KBID'] -replace 'KB\s*','')")
                Continue
            }
            default { Write-Verbose "$_ isn't a valid string" }
        }
        if ($Build) {
            Write-Verbose "Filtering to match requested build"
            $Capture = $Capture | Where-Object { $_.Version.Build -eq $Build }
        }
    }
    End {
        if ($Latest) {
            Write-Verbose "Returning only the latest release"
            $LatestDate = $Capture.ReleaseDate | Sort-Object -Descending | Get-Unique | Select-Object -First 1
            $Capture | Where-Object { $_.ReleaseDate -eq $LatestDate }
        } else {
            Write-Verbose "Returning all results"
            $Capture
        }
    }
}

Function Get-PatchStatus {
    [cmdletbinding()]
    param(
        [string[]]$ComputerName = $Env:COMPUTERNAME
    )
    begin {
        if ($ComputerName.Count -eq 1) {
            $OSVersion = Get-OSVersion -ComputerName $ComputerName[0]
            if ($OSVersion.major -ge 10) {
                $WUReleases = Get-WindowsUpdateRelease -Build $OSVersion.Build
            } else {
                Write-Warning "$Computer is not running a supported OS. Must be release 1507 or newer."
                Break
            }
        } else {
            $WUReleases = Get-WindowsUpdateRelease
        }
    }
    Process {
        foreach ($Computer in $ComputerName) {
            $OSVersion = Get-OSVersion -ComputerName $Computer
            if ($OSVersion.major -ge 10) {
                $CurrentUpdate = $WUReleases | Where-Object { $_.Version -eq $OSVersion }
                $LatestRelease = $WUReleases.Version | Where-Object { $_.Build -eq $OSVersion.Build } | Sort-Object -Descending | Select-Object -First 1
                if ($OSVersion -lt $LatestRelease) {
                    Write-Verbose "$OSVersion is less than $LatestRelease"
                    $UpdatesMissing = $WUReleases | Where-Object { $_.Version -gt $OSVersion -and $_.Version.Build -eq $OSVersion.Build }
                    $UpdatesBehind = ($UpdatesMissing | Measure-Object -Property Name).Count
                    [pscustomObject][ordered]@{
                        ComputerName   = $Computer
                        UpToDate       = $false
                        Status         = "N-$($UpdatesBehind)"
                        DaysBehind     = (New-TimeSpan -Start $CurrentUpdate.ReleaseDate -End $UpdatesMissing[0].ReleaseDate).TotalDays
                        CurrentUpdate  = $CurrentUpdate
                        MissingUpdates = $UpdatesMissing
                    }
                } else {
                    [pscustomObject][ordered]@{
                        ComputerName   = $Computer
                        UpToDate       = $true
                        Status         = "N-0"
                        DaysBehind     = 0
                        CurrentUpdate  = $CurrentUpdate
                        MissingUpdates = $null
                    }
                }
            } else {
                Write-Warning "$Computer is not running a supported OS. Must be release 1507 or newer."
            }
        }
    }
}
