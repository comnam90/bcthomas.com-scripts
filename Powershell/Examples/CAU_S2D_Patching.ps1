# Use Powershell Splatting for setting CAU cmdlet options
$CAUOptions = @{
    # Cluster to patch
    ClusterName                      = 'S2D-Cluster'
    # Time to wait for a node to reboot after patching
    RebootTimeoutMinutes             = 90
    # Time to wait for a node to enter paused state
    SuspendClusterNodeTimeoutMinutes = 90
    # Script to run on node before pausing and patching
    PreUpdateScript                  = '\\management-server\CAU-Share\CAU_S2D_PreNodePatching.ps1'
    # Script to run on node after patching and resuming
    PostUpdateScript                 = '\\Management-server\CAU-Share\CAU_S2D_PostNodePatching.ps1'
    # Number of times to attempt patching a node
    MaxRetriesPerNode                = 3
    # Number of nodes that can fail patching before CAU gives up
    MaxFailedNodes                   = 1
    # CAU mode to use
    CauPluginName                    = @('Microsoft.WindowsUpdatePlugin')
    CauPluginArguments               = @{ 'IncludeRecommendedUpdates' = 'True' }
    # Whether to allow CAU to run when cluster nodes are down
    RequireAllNodesOnline            = $true
    # Whether to enable required firewall rules on cluster nodes or not
    EnableFirewallRules              = $true
    # Skip confirmation
    Force                            = $true
}

# Set powershell transcript location
$TranscriptFolder = 'C:\logs'
$TranscriptFileName = "CAU-Run-$(Get-Date -Format yyyMMdd_hhmmss).log"
$TranscriptPath = "$($TranscriptFolder)\$($TranscriptFileName)"
if (!Test-path -path $TranscriptFolder) {
    New-Item -ItemType Directory -Path $TranscriptFolder -Force -Confirm:$false
}
Start-Transcript -Path $TranscriptPath -Force

# Execute CAU run
try {
    Invoke-CauRun  @CAUOptions
}
finally {
    Stop-Transcript
}
