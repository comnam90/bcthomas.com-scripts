# Overview

## PatchStatusHelper.ps1

Contains functions to help check a machine's patch level against patches available online, without using Windows APIs

### Functions

- Get-OSVersion
- New-WUObject
- Get-WindowsUpdateRelease
- Get-PatchStatus

### Examples

#### Get-WindowsUpdateRelease

```
> Get-WindowsUpdateRelease -Build 18363

Name      ReleaseDate            Version        KBURL
----      -----------            -------        -----
KB4528760 14/01/2020 12:00:00 AM 10.0.18363.592 https://support.microsoft.com/en-us/help/4528760
KB4530684 10/12/2019 12:00:00 AM 10.0.18363.535 https://support.microsoft.com/en-us/help/4530684
KB4524570 12/11/2019 12:00:00 AM 10.0.18363.476 https://support.microsoft.com/en-us/help/4524570


> (Get-WindowsUpdateRelease -Build 18363) -join ','

KB4528760 (14/01/2020),KB4530684 (10/12/2019),KB4524570 (12/11/2019)


> (Get-WindowsUpdateRelease -Build 18363).ToLongString()       

KB4528760|14/01/2020|10.0.18363.592|https://support.microsoft.com/en-us/help/4528760
KB4530684|10/12/2019|10.0.18363.535|https://support.microsoft.com/en-us/help/4530684
KB4524570|12/11/2019|10.0.18363.476|https://support.microsoft.com/en-us/help/4524570
```

#### Get-OSVersion

```
> Get-OSVersion

Major  Minor  Build  Revision
-----  -----  -----  --------
10     0      18362  535


> write-host (Get-OSVersion)

10.0.18362.535
```

#### Get-PatchStatus

```
> Get-PatchStatus

ComputerName   : LT001
UpToDate       : False
Status         : N-1
CurrentUpdate  : KB4530684 (10/12/2019)
MissingUpdates : KB4528760 (14/01/2020)


> (Get-PatchStatus).CurrentUpdate

Name      ReleaseDate            URL                                              Version
----      -----------            ---                                              -------
KB4530684 10/12/2019 12:00:00 AM https://support.microsoft.com/en-us/help/4530684 10.0.18362.535


> Get-PatchStatus -ComputerName SQL,FILE1 | ft -au

ComputerName UpToDate Status CurrentUpdate          MissingUpdates
------------ -------- ------ -------------          --------------
SQL             False N-1    KB4530715 (10/12/2019) KB4534273 (14/01/2020)
FILE1           False N-31   KB4464455 (13/11/2018) {KB4534273 (14/01/2020), KB4530715 (10/12/2019), KB4523205 (12/1...
```

## Find-AzSAvailableUpdate.ps1

Checks what updates are available for AzureStack.

### Functions

- Find-AzSAvailableUpdate

### Examples
- https://bcthomas.com/2019/09/updating-your-azurestack-make-sure-you-dont-miss-any-steps/

## S2D-Maintenance.ps1

Contains powershell functions, designed to make it easier to perform maintenance on S2D Clusters and nodes.

### Functions

- Enable-S2DNodeMaintenance
- Disable-S2DNodeMaintenance
- Get-S2DNodeMaintenanceState
- Stop-S2DCluster
- Start-S2DCluster

### Examples
- https://bcthomas.com/2019/05/perform-better-storage-spaces-direct-maintenance-with-these-powershell-functions/
- https://bcthomas.com/2019/06/best-practices-for-patching-s2d-and-azurestack-hci-clusters-part-1/

## Install-OMSAgents.ps1

Used to install OMS Agents locally and remotely.

### Functions

- Install-OMSAgents

### Examples

- https://bcthomas.com/2019/05/installing-azure-monitor-log-analytics-agents-with-powershell/
