function Find-AzSAvailableUpdates {
    <#
        .Synopsis
        Checks what updates are available for AzureStack
        .Description
        Can be used to find out what the latest AzureStack Update Version number is or
        what updates need to be applied to a specific version to get it up to date.
        .Parameter Version
        Current AzureStack Update Version to check against.
        .Parameter LatestOnly
        Returns the Version Number for the latest AzureStack Update.
        .Example
        > Find-AzSAvailableUpdates -Version 1.906.1.35
        This will return all updates that need to be applied to get up to date from
        AzureStack Update 1.1906.1.35
        .Example
        > Find-AzSAvailableUpdates -LatestOnly
        This will return only the latest available update version.
        .Notes
        ----------------------------------------------------------
        Version: 1.0.0
        Maintained By: Ben Thomas (@NZ_BenThomas)
        Last Updated: 2019-08-16
        ----------------------------------------------------------
        CHANGELOG:
            1.0.0
             - Initial Version
    #>
    [cmdletbinding(DefaultParameterSetName = "AllUpdates")]
    param(
        [parameter(ParameterSetName = "AllUpdates", Mandatory)]
        [ValidatePattern("^\d\.\d{4}\.\d+\.\d+$")]
        [string]$Version,
        [parameter(ParameterSetName = "LatestOnly")]
        [Switch]$LatestOnly
    )

    # Establishing Variables
    $publishedUpdates = @{ }
    $AvailableUpdates = @()
    $URI = 'https://aka.ms/azurestackautomaticupdate'

    try {
        Write-Verbose "Attempting to get AzureStack Update list from $URI"
        $Content = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $URI -ErrorAction Stop
    } catch {
        Write-Warning "Failed to get update list from $URI"
        Throw "$($PSItem.ToString())"
    }

    $Object = [xml]$Content.Substring(3)
    $UpdateCount = $Object.AzureStackUpdates.CurrentVersion.Count
    Write-Verbose "Found $($UpdateCount) updates"

    $latestUpdate = (
        $Object.AzureStackUpdates.CurrentVersion | 
        Sort-Object -Property Version | 
        Select-Object -Last 1
    ).ApplicableUpdate.Version

    if ($PSCmdlet.ParameterSetName -eq "AllUpdates") {
        Write-Verbose "Creating hashtable with the updates"
        $Object.AzureStackUpdates.CurrentVersion.Foreach{
            $publishedUpdates[$PSItem.Version] = $PSItem.ApplicableUpdate
        }
        Write-Verbose "Checking if $Version has any updates"
        
        if (!$publishedUpdates[$Version]) {
            Write-Verbose "No updates available`nChecking if it's already on the latest version"
            if ($Version -ne $latestUpdate) {
                Write-Error "$Version is not a valid AzureStack revision"
            } else {
                Write-Verbose "$Version is the newest version available"
                Write-Output "No updates available"
            }
        } else {
            Write-Verbose "$Version needs to be updated"
            $UpdatesAvailable = $true
            $Update = $publishedUpdates[$Version].Version
            Write-Verbose "  Found $($Update), checking for more"
            $AvailableUpdates += $Update
            do {
                $Update = $publishedUpdates[$Update].Version
                if (!$Update) {
                    $UpdatesAvailable = $false
                } else {
                    Write-Verbose "  Found $($Update), checking for more"
                    $AvailableUpdates += $Update
                }
            }until(
                $UpdatesAvailable -eq $false
            )
            Write-Output "The following updates are available for AzureStack $($Version):`n$($AvailableUpdates -join ', ')"
        }
    } else {
        Write-Output "$latestUpdate is the latest AzureStack Update"
    }
}
