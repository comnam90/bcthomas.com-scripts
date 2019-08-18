function Find-AzSAvailableUpdate {
    <#
        .Synopsis
        Checks what updates are available for AzureStack
        .Description
        Can be used to find out what the latest AzureStack Update Version number is or
        what updates need to be applied to a specific version to get it up to date.
        It returns an array of objects by default with all available updates, however
        this can be changes to a simple string output using the -SimpleOutput switch.
        .Parameter Version
        Current AzureStack Update Version to check against.
        .Parameter LatestOnly
        Returns the Version Number for the latest AzureStack Update.
        .Example
        > Find-AzSAvailableUpdate -Version 1.1906.1.35
        This will return all updates that need to be applied to get up to date from
        AzureStack Update 1.1906.1.35
        .Example
        > Find-AzSAvailableUpdate -LatestOnly
        This will return only the latest available update version.
        .Example
        > Find-AzSAvailableUpdates -Release 1906
        This will search for updates by Release number rather than Update Version.
        .Example
        > Find-AzSAvailableUpdate -Release 1906 -SimpleOutput
        Returns results as a simple string output rather than an object.
        .Notes
        ----------------------------------------------------------
        Version: 1.2.0
        Maintained By: Ben Thomas (@NZ_BenThomas)
        Last Updated: 2019-08-19
        ----------------------------------------------------------
        CHANGELOG:
            1.2.0
             - Added Release parameter for searching by release number
             - Changed ValidatePattern to ValidateScript for more descriptive
               error messages.
            1.1.0
             - Introduced Begin,Process,End
             - Changed to returning an object by default
             - Added switch for Simple output
            1.0.0
             - Initial Version
    #>
    [cmdletbinding(DefaultParameterSetName = "SpecificVersion")]
    param(
        [parameter(ParameterSetName = "SpecificVersion", Mandatory)]
        [ValidateScript( { if ($_ -match "^\d\.\d{4}\.\d+\.\d+$") { $true }else { throw "$_ is not a valid version number. Eg - 1.1906.0.30" } })]
        [string]$Version,
        [parameter(ParameterSetName = "Release", Mandatory)]
        [ValidateScript( { if ($_ -match "^\d{4}$") { $true }else { throw "$_ is not a valid release number. Eg - 1906" } })]
        [string]$Release,
        [parameter(ParameterSetName = "LatestOnly")]
        [Switch]$LatestOnly,
        [Switch]$SimpleOutput
    )

    begin {
        # Establishing Variables
        $publishedUpdates = @{ }
        $AvailableUpdates = @()
        $URI = 'https://aka.ms/azurestackautomaticupdate'
        $IsLatest = $false

        try {
            Write-Verbose "Attempting to get AzureStack Update list from $URI"
            $Content = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $URI -ErrorAction Stop
        } catch {
            Write-Warning "Failed to get update list from $URI"
            Throw "$($PSItem.ToString())"
        }
    }

    process {
        $Object = [xml]$Content.Substring(3)
        $UpdateCount = $Object.AzureStackUpdates.CurrentVersion.Count
        Write-Verbose "Found $($UpdateCount) updates"

        $latestUpdate = (
            $Object.AzureStackUpdates.CurrentVersion | 
            Sort-Object -Property Version | 
            Select-Object -Last 1
        ).ApplicableUpdate.Version

        if ($PSCmdlet.ParameterSetName -eq "Release") {
            Write-Verbose "Release $Release has been supplied, looking for matching versions"
            $PossibleVersion = $Object.AzureStackUpdates.CurrentVersion.Version |
            Where-Object { ([Version]$_).Minor -eq $Release } |
            Sort-Object |
            Select-Object -First 1
            if ($PossibleVersion) {
                Write-Verbose "  Found Version $PossibleVersion"
                $Version = $PossibleVersion
            } elseif (([version]$latestUpdate).Minor -eq $Release) {
                Write-Verbose "  Matched latest version $latestUpdate"
                $Version = $latestUpdate
            } else {
                Throw "No matching version found for $Release"
            }
        }

        if ($PSCmdlet.ParameterSetName -ne "LatestOnly") {
            Write-Verbose "Creating hashtable with the updates"
            $Object.AzureStackUpdates.CurrentVersion.Foreach{
                $publishedUpdates[$PSItem.Version] = $PSItem.ApplicableUpdate
            }
            Write-Verbose "Checking if $Version has any updates"
        
            if (!$publishedUpdates[$Version]) {
                Write-Verbose "No updates available, checking if it's already on the latest version"
                if ($Version -ne $latestUpdate) {
                    Write-Error "$Version is not a valid AzureStack revision"
                } else {
                    Write-Verbose "$Version is the newest version available"
                    $IsLatest = $true
                }
            } else {
                Write-Verbose "$Version needs to be updated"
                $UpdatesAvailable = $true
                $Update = $publishedUpdates[$Version]
                Write-Verbose "  Found $($Update.Version), checking for more"
                $UpdateDetails = Invoke-WebRequest -Uri $Update.MetadataFile.Uri -UseBasicParsing | 
                Select-Object -ExpandProperty Content | ForEach-Object {
                    ([xml]$_).UpdatePackageManifest.UpdateInfo
                }
                $AvailableUpdates += $UpdateDetails
                do {
                    $Update = $publishedUpdates[$Update.Version]
                    if (!$Update) {
                        $UpdatesAvailable = $false
                    } else {
                        Write-Verbose "  Found $($Update.Version), checking for more"
                        $UpdateDetails = Invoke-WebRequest -Uri $Update.MetadataFile.Uri -UseBasicParsing | 
                        Select-Object -ExpandProperty Content | ForEach-Object {
                            ([xml]$_).UpdatePackageManifest.UpdateInfo
                        }
                        $AvailableUpdates += $UpdateDetails
                    }
                }until(
                    $UpdatesAvailable -eq $false
                )
            }
        } else {
            Write-Verbose "$latestUpdate is the latest AzureStack Update"
            $IsLatest = $true
            $DetailsURI = (
                $Object.AzureStackUpdates.CurrentVersion | 
                Sort-Object -Property Version | 
                Select-Object -Last 1
            ).ApplicableUpdate.MetadataFile.Uri
            $AvailableUpdates += Invoke-WebRequest -Uri $DetailsURI -UseBasicParsing | 
            Select-Object -ExpandProperty Content | ForEach-Object {
                ([xml]$_).UpdatePackageManifest.UpdateInfo
            }
        }
    }

    end {
        if ($AvailableUpdates.Count -ge 1) {
            if (!$SimpleOutput) {
                $AvailableUpdates.ForEach{
                    $Type = Switch -Wildcard ($PSItem.UpdateName) {
                        "*Update*" { "Update" }
                        "*Hotfix*" { "Hotfix" }
                        default { "Unknown" }
                    }
                    [pscustomobject][ordered]@{
                        Type          = [string]$Type
                        Name          = [string]$PSItem.UpdateName
                        Description   = [string]$PSItem.Description
                        SizeMB        = [uint64]$PSItem.PackageSizeInMB
                        Version       = [version]$PSitem.Version
                        PreReqVersion = [version]$PSItem.MinVersionRequired
                        KBLink        = [uri]$PSItem.KBLink
                    }
                }
            } elseif ($PSCmdlet.ParameterSetName -eq "LatestOnly") {
                Write-Output "The latest update available: $($AvailableUpdates.Version)"
            } else {
                Write-Output "The following updates are available for $($Version):`n$($AvailableUpdates.Version -join ', ')"
            }
        } elseif ($IsLatest -and $SimpleOutput) {
            Write-Output "$Version is up to date"
        }
    }
}
