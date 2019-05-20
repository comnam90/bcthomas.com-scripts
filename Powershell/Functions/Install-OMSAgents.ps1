
function Install-OMSAgents {
    <#
        .Synopsis
        Used to install OMS Agents
        .Description
        Used to install OMS Agents locally and remotely. It will download the required installer by
        default, but you can also specify a path to the installer if you don't have internet access 
        for all machines you wish to install it on, or want to save bandwidth.
        .Parameter ComputerName
        Array of Computer Names to install the OMS agent on.
        .Parameter WorkspaceID
        Azure Log Analytics Workspace ID.
        .Parameter WorkspaceKey
        Azure Log Analytics Workspace Key.
        .Parameter OMSDownloadPath
        Specify the directory on each machine to download the installer to.
        .Parameter InstallerPath
        Specify a local or UNC path to the MMA installer if you don't want to download it automatically.
        Requires all servers you want to be able to install the Agent on to have access to the share hosting
        the installer.
        .Parameter OverrideExisting
        Triggers overriding existing workspaces on machines with the agent already installed.
        .Example
        Install-OMSAgents -ComputerName Server01 -WorkspaceID xxxxxx -WorkspaceKey xxxxx
        This will default to downloading and installing the Microsoft Monitoring Agent
        on Server01 from the internet, and configure it to point to the specified 
        Azure Log Analytics Workspace
        .Example
        Install-OMSAgents -ComputerName 'Server01','Server02' -InstallerPath \\nas01\share01\MMASetup-AMD64.exe -WorkspaceID xxx -WorkspaceKey xxx
        This will install on Server01 and Server02 using the installer found on NAS01.
        .Notes
        Big shout out to John Savill (@ntfaqguy) for the original script I used
        to create this function, it can be found on his website
        https://savilltech.com/2018/01/21/deploying-the-oms-agent-automatically/
        ---------------------------------------------------------------
        Version: 1.0.0
        Maintained By: Ben Thomas (@NZ_BenThomas)
        Last Updated: 2019-05-20
        ---------------------------------------------------------------
        CHANGELOG:
            1.0.0
             - Initial version
             - Updated @ntfaqguy's script to a function
             - Added support for remotely running against multiple machines
             - Added parameters to specify a central installer rather than
               downloading the agent on every machine.
             - Added a switch for overridding existing Agent installs with
               new workspace details.
        .Link
        https://bcthomas.com
    #>
    [cmdletbinding(DefaultParameterSetName = 'Download')]
    param(
        [string[]]$ComputerName = 'Localhost',
        [parameter(Mandatory)]
        [string]$WorkspaceID,
        [parameter(Mandatory)]
        [string]$WorkspaceKey,
        [parameter(ParameterSetName = 'Download')]
        [string]$OMSDownloadPath = 'C:\Temp',
        [parameter(Mandatory, ParameterSetName = 'Offline')]
        [string]$InstallerPath,
        [switch]$OverrideExisting
    ) 
    begin {
        #region: Helper Functions
        function Get-InstalledSoftware {
            param(
                [string]$ComputerName = 'localhost',
                [string]$ProductName = '*'
            )

            $UninstallKey = ”SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall” 
            $reg = [microsoft.win32.registrykey]::OpenRemoteBaseKey(‘LocalMachine’, $ComputerName) 
            $regkey = $reg.OpenSubKey($UninstallKey) 
            $subkeys = $regkey.GetSubKeyNames() 

            foreach ($key in $subkeys) {
                $thisKey = $UninstallKey + ”\\” + $key 
                $thisSubKey = $reg.OpenSubKey($thisKey)
                $DisplayName = $($thisSubKey.GetValue(“DisplayName”))
                if ($DisplayName -ilike $ProductName) {
                    [pscustomobject][ordered]@{
                        ComputerName    = $ComputerName
                        ProductName     = $($thisSubKey.GetValue(“DisplayName”))
                        DisplayVersion  = $($thisSubKey.GetValue(“DisplayVersion”))
                        InstallLocation = $($thisSubKey.GetValue(“InstallLocation”))
                        Publisher       = $($thisSubKey.GetValue(“Publisher”))
                    }
                }
            } 
        }
        #endregion

        Write-Verbose "Establish Sessions to target machines"
        $Sessions = @{ }
        $ExcludedComputers = @()
        $OverrideComputers = @()
        $Results = @()
        foreach ($Computer in $ComputerName) {
            try {
                $NewSession = New-PSSession -ComputerName $Computer -Name $Computer -ErrorAction Stop
                Write-verbose "Checking if OMS Agent is installed on $Computer"
                $MMAObj = Get-InstalledSoftware -ProductName 'Microsoft Monitoring Agent' -ComputerName $Computer
                if ($MMAObj -and ( -not $OverrideExisting) ) {
                    throw "Agent is already installed"
                }
                elseif ($MMAObj -and $OverrideExisting) {
                    Write-Warning "Agent found on $Computer, the existing settings on this`nMachine will be overridden."
                    $OverrideComputers += $Computer
                }
                else {
                    Write-Verbose "No Agent found, install scheduled."
                }
                $Sessions.Add($Computer, $NewSession)
            }
            catch {
                Write-Warning "An error occured and $Computer will be excluded.`nError Details: $($PSItem.ToString())"
                $ExcludedComputers += $Computer
                Continue
            }
        }
    }
    Process {
        Foreach ($Computer in $ComputerName) {
            if ($Computer -iin $ExcludedComputers) {
                Write-Warning "Skipping $Computer as it's excluded"
            }
            else {
                try {
                    $Install = $true
                    if ($Computer -iin $OverrideComputers) {
                        $Install = $false
                    }
                    if ($PSCmdlet.ParameterSetName -eq 'Download') {
                        # Download the required installer onto the remove machine
                        Write-Verbose "Downloading MMASetup-AMD64.exe to $Computer $OMSDownloadPath"
                        $InstallerPath = Invoke-Command -session $Sessions[$computer] `
                            -ArgumentList $OMSDownloadPath, $Install `
                            -ErrorAction Stop `
                            -ScriptBlock {

                            param(
                                $OMSDownloadPath,
                                $Install
                            )

                            $OMS64bitDownloadURL = "https://go.microsoft.com/fwlink/?LinkId=828603"
                            $OMSDownloadFileName = "MMASetup-AMD64.exe"
                            $OMSDownloadFullPath = "$OMSDownloadPath\$OMSDownloadFileName"
                            
                            if ($Install) {
                                #Create temporary folder if it does not exist
                                if (-not (Test-Path -Path $OMSDownloadPath)) { 
                                    New-Item -Path $OMSDownloadPath -ItemType Directory | Out-Null 
                                }
                                
                                Write-host "$env:computername - Downloading the agent..."
                                #Download to the temporary folder
                                Invoke-WebRequest -Uri $OMS64bitDownloadURL -OutFile $OMSDownloadFullPath | Out-Null
                            }
                            "$OMSDownloadFullPath"
                        }
                    }
                    $Workspaces = Invoke-Command -Session $Sessions[$Computer] `
                        -ArgumentList $InstallerPath, $WorkspaceID, $WorkspaceKey, $OverrideExisting, $Install `
                        -ErrorAction Stop `
                        -ScriptBlock {

                        Param(
                            $InstallerPath,
                            $WorkspaceID,
                            $WorkspaceKey,
                            $OverrideExisting,
                            $Install
                        )

                        Write-host "$env:computername - Installing the agent..." 
                        if ((-Not (Test-Path -Path $InstallerPath)) -and $Install ) {
                            throw "$ComputerName cannot access $InstallerPath"
                        }
                        elseif ($Install) {
                            #Install the agent
                            $ArgumentList = '/C:"setup.exe /qn ADD_OPINSIGHTS_WORKSPACE=0 AcceptEndUserLicenseAgreement=1"'
                            Start-Process $InstallerPath -ArgumentList $ArgumentList -ErrorAction Stop -Wait | Out-Null
                        }
                    
                        #Check if the CSE workspace is already configured
                        $AgentCfg = New-Object -ComObject AgentConfigManager.MgmtSvcCfg
                        $OMSWorkspaces = $AgentCfg.GetCloudWorkspaces()
        
                        $CSEWorkspaceFound = $false
                        foreach ($OMSWorkspace in $OMSWorkspaces) {
                            if ($OMSWorkspace.workspaceId -eq $WorkspaceID) {
                                $CSEWorkspaceFound = $true
                            }
                            elseif ($OverrideExisting) {
                                $AgentCfg.RemoveCloudWorkspace($OMSWorkspace.workspaceId)
                                $AgentCfg.ReloadConfiguration()
                            }
                        }
        
                        if (!$CSEWorkspaceFound) {
                            Write-host "$env:computername - Adding CSE OMS Workspace..."
                            $AgentCfg.AddCloudWorkspace($WorkspaceID, $WorkspaceKey)
                            Restart-Service HealthService
                        }
                        else {
                            Write-Warning "CSE OMS Workspace already configured"
                        }
        
                        # Get all configured OMS Workspaces
                        sleep 5
                        $AgentCfg.GetCloudWorkspaces()
                    }
                    
                    $Results += [pscustomobject][ordered]@{
                        ComputerName = $Computer
                        AgentID      = $Workspaces.AgentID
                        WorkspaceID  = $Workspaces.WorkspaceID
                        Status       = $Workspaces.ConnectionStatusText
                    }
                }
                catch {
                    Write-Warning "Installation failed on $Computer`nRan into an issue: $($PSItem.ToString())"
                    Continue
                }
            }
        }
    }
    End {
        foreach ($connection in $Sessions.Keys) {
            $Sessions[$connection] | Remove-PSSession -Confirm:$false
        }
        $Results
    }
}
