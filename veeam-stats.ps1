<#
        .SYNOPSIS
        PRTG Veeam Advanced Sensor
  
        .DESCRIPTION
        Advanced Sensor will Report Statistics about Backups during last 24 Hours and Actual Repository usage. It will then convert them into JSON, ready to add into InfluxDB and show it with Grafana
	
        .Notes
        NAME:  veeam-stats.ps1
        ORIGINAL NAME: PRTG-VeeamBRStats.ps1
        LASTEDIT: 16/07/2018
        VERSION: 0.4
        KEYWORDS: Veeam, PRTG, Grafana, InfluxDB,
   
        .Link
        http://mycloudrevolution.com/
        Minor Edits and JSON output for Grafana by https://jorgedelacruz.es/
        Minor Edits from JSON to Influx for Grafana by r4yfx
		
		Nicholas Charalambous
		Edited Repository to include ScaleOut Repository in Storage Free Space -- ginettanyk@gmail.com
		Added a few more notes where I had to hunt for understanding, mostly obvious, but on bad days we miss a lot of the obvious
 

 #Requires PS -Version 3.0
 #Requires -Modules VeeamPSSnapIn    
 #>
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
        [string] $BRHost = "localhost", # FQDN or IP Address for the Veeam Backup Server
    [Parameter(Position=1, Mandatory=$false)]
        $reportMode = "24", # Weekly, Monthly as String or Hour as Integer - Your report will be based on this value -- reference this value when you need to know what your results mean.
    [Parameter(Position=2, Mandatory=$false)]
        $repoCritical = 15, #If value drops below this percentage it will show as default red background for critical
    [Parameter(Position=3, Mandatory=$false)]
        $repoWarn = 30 # background defaults to yellow/orange -- or your color of choosing when it gets below this value.
  
)
# You can find the original code for PRTG here, thank you so much Markus Kraus - https://github.com/mycloudrevolution/Advanced-PRTG-Sensors/blob/master/Veeam/PRTG-VeeamBRStats.ps1
# Big thanks to Shawn, creating a awsome Reporting Script:
# http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/

#region: Start Load VEEAM Snapin (if not already loaded)
if (!(Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
	if (!(Add-PSSnapin -PassThru VeeamPSSnapIn)) {
		# Error out if loading fails
		Write-Error "`nERROR: Cannot load the VEEAM Snapin."
		Exit
	}
}
#endregion

#region: Functions
Function Get-vPCRepoInfo {
[CmdletBinding()]
        param (
                [Parameter(Position=0, ValueFromPipeline=$true)]
                [PSObject[]]$Repository
                )
        Begin {
                $outputAry = @()
                Function Build-Object {param($name, $repohost, $path, $free, $total)
                        $repoObj = New-Object -TypeName PSObject -Property @{
                                        Target = $name
										RepoHost = $repohost
                                        Storepath = $path
                                        StorageFree = [Math]::Round([Decimal]$free/1GB,2)
                                        StorageTotal = [Math]::Round([Decimal]$total/1GB,2)
                                        FreePercentage = [Math]::Round(($free/$total)*100)
                                }
                        Return $repoObj | Select Target, RepoHost, Storepath, StorageFree, StorageTotal, FreePercentage
                }
        }
        Process {
                Foreach ($r in $Repository) {
                	# Refresh Repository Size Info
					[Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb($r, $true)
					
					If ($r.HostId -eq "00000000-0000-0000-0000-000000000000") {
						$HostName = "cgyveeam"
					}
					Else {
						$HostName = $($r.GetHost()).Name.ToLower()
					}
					$outputObj = Build-Object $r.Name $Hostname $r.Path $r.info.CachedFreeSpace $r.Info.CachedTotalSpace
					}
                $outputAry += $outputObj
        }
        End {
                $outputAry
        }
}

#endregion

#region: Start BRHost Connection
$OpenConnection = (Get-VBRServerSession).Server
if($OpenConnection -eq $BRHost) {
	
} elseif ($OpenConnection -eq $null ) {
	
	Connect-VBRServer -Server $BRHost
} else {
    
    Disconnect-VBRServer
   
    Connect-VBRServer -Server $BRHost
}

$NewConnection = (Get-VBRServerSession).Server
if ($NewConnection -eq $null ) {
	Write-Error "`nError: BRHost Connection Failed"
	Exit
}
#endregion

#region: Convert mode (timeframe) to hours
If ($reportMode -eq "Monthly") {
        $HourstoCheck = 720
} Elseif ($reportMode -eq "Weekly") {
        $HourstoCheck = 168
} Else {
        $HourstoCheck = $reportMode
}
#endregion

#region: Collect and filter Sessions
# $vbrserverobj = Get-VBRLocalhost        # Get VBR Server object
# $viProxyList = Get-VBRViProxy           # Get all Proxies

# Modified for Scale-Out Repositories ## Nicholas Charalambous 2018-07-16 ginettanyk@gmail.com
[Array]$repoList = Get-VBRBackupRepository | Where-Object {$_.Type -ne "SanSnapshotOnly"}
[Array]$scaleouts = Get-VBRBackupRepository -scaleout
if ($scaleouts) {
		foreach ($scaleout in $scaleouts) {
				$extents = Get-VBRRepositoryExtent -Repository $scaleout
				foreach ($ex in $extents) {
						$repoList = $repoList + $ex.repository
				}
		}
}

$allSesh = Get-VBRBackupSession         # Get all Sessions (Backup/BackupCopy/Replica)
# $allResto = Get-VBRRestoreSession       # Get all Restore Sessions
$seshListBk = @($allSesh | ?{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Backup"})           # Gather all Backup sessions within timeframe
$seshListBkc = @($allSesh | ?{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "BackupSync"})      # Gather all BackupCopy sessions within timeframe
$seshListRepl = @($allSesh | ?{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Replica"})        # Gather all Replication sessions within timeframe
#endregion

#region: Collect Jobs
# $allJobsBk = @(Get-VBRJob | ? {$_.JobType -eq "Backup"})        # Gather Backup jobs
# $allJobsBkC = @(Get-VBRJob | ? {$_.JobType -eq "BackupSync"})   # Gather BackupCopy jobs
# $repList = @(Get-VBRJob | ?{$_.IsReplica})                      # Get Replica jobs
#endregion

#region: Get Backup session informations
$totalxferBk = 0
$totalReadBk = 0
$seshListBk | %{$totalxferBk += $([Math]::Round([Decimal]$_.Progress.TransferedSize/1GB, 0))}
$seshListBk | %{$totalReadBk += $([Math]::Round([Decimal]$_.Progress.ReadSize/1GB, 0))}
#endregion

#region: Preparing Backup Session Reports
$successSessionsBk = @($seshListBk | ?{$_.Result -eq "Success"})
$warningSessionsBk = @($seshListBk | ?{$_.Result -eq "Warning"})
$failsSessionsBk = @($seshListBk | ?{$_.Result -eq "Failed"})
$runningSessionsBk = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "Backup"})
$failedSessionsBk = @($seshListBk | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})
#endregion

#region:  Preparing Backup Copy Session Reports
$successSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Success"})
$warningSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Warning"})
$failsSessionsBkC = @($seshListBkC | ?{$_.Result -eq "Failed"})
$runningSessionsBkC = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "BackupSync"})
$IdleSessionsBkC = @($allSesh | ?{$_.State -eq "Idle" -and $_.JobType -eq "BackupSync"})
$failedSessionsBkC = @($seshListBkC | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})
#endregion

#region: Preparing Replicatiom Session Reports
$successSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Success"})
$warningSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Warning"})
$failsSessionsRepl = @($seshListRepl | ?{$_.Result -eq "Failed"})
$runningSessionsRepl = @($allSesh | ?{$_.State -eq "Working" -and $_.JobType -eq "Replica"})
$failedSessionsRepl = @($seshListRepl | ?{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})

$RepoReport = $repoList | Get-vPCRepoInfo | Select     @{Name="Repository Name"; Expression = {$_.Target}},
                                                       @{Name="Host"; Expression = {$_.RepoHost}},
                                                       @{Name="Path"; Expression = {$_.Storepath}},
                                                       @{Name="Free (GB)"; Expression = {$_.StorageFree}},
                                                       @{Name="Total (GB)"; Expression = {$_.StorageTotal}},
                                                       @{Name="Free (%)"; Expression = {$_.FreePercentage}},
                                                       @{Name="Status"; Expression = {
                                                       If ($_.FreePercentage -lt $repoCritical) {"Critical"} 
                                                       ElseIf ($_.FreePercentage -lt $repoWarn) {"Warning"}
                                                       ElseIf ($_.FreePercentage -eq "Unknown") {"Unknown"}
                                                       Else {"OK"}}} | `
                                                       Sort "Repository Name" 
#endregion

#region: Number of Endpoints
$number_endpoints = 0
foreach ($endpoint in Get-VBREPJob ) {
$number_endpoints++;
}
#endregion
 

#region: Influxdb Output for Telegraf

$Count = $successSessionsBk.Count
$body="veeam-stats successfulbackups=$Count"
Write-Host $body

$Count = $warningSessionsBk.Count
$body="veeam-stats warningbackups=$Count"
Write-Host $body

$Count = $failsSessionsBk.Count
$body="veeam-stats failesbackups=$Count"
Write-Host $body

$Count = $failedSessionsBk.Count
$body="veeam-stats failedbackups=$Count"
Write-Host $body

$Count = $runningSessionsBk.Count
$body="veeam-stats runningbackups=$Count"
Write-Host $body

$Count = $successSessionsBkC.Count
$body="veeam-stats successfulbackupcopys=$Count"
Write-Host $body

$Count = $warningSessionsBkC.Count
$body="veeam-stats warningbackupcopys=$Count"
Write-Host $body

$Count = $failsSessionsBkC.Count
$body="veeam-stats failesbackupcopys=$Count"
Write-Host $body

$Count = $failedSessionsBkC.Count
$body="veeam-stats failedbackupcopys=$Count"
Write-Host $body

$Count = $runningSessionsBkC.Count
$body="veeam-stats runningbackupcopys=$Count"
Write-Host $body

$Count = $IdleSessionsBkC.Count
$body="veeam-stats idlebackupcopys=$Count"
Write-Host $body

$Count = $successSessionsRepl.Count
$body="veeam-stats successfulreplications=$Count"
Write-Host $body

$Count = $warningSessionsRepl.Count
$body="veeam-stats warningreplications=$Count"
Write-Host $body

$Count = $failsSessionsRepl.Count
$body="veeam-stats failesreplications=$Count"
Write-Host $body

$Count = $failedSessionsRepl.Count
$body="veeam-stats failedreplications=$Count"
Write-Host $body

$body="veeam-stats totalbackuptransfer=$totalxferBk"

foreach ($Repo in $RepoReport){
$Name = "REPO " + $Repo."Repository Name" -replace '\s','_'
$Free = $Repo."Free (%)"
$body="veeam-stats $Name=$Free"
Write-Host $body
	}

foreach ($SORepo in $SORepoReport){
$Name = "REPO " + $SORepo."Repository Name" -replace '\s','_'
$Free = $SORepo."Free (%)"
$body="veeam-stats $Name=$Free"
Write-Host $body
	}	
	
$body="veeam-stats protectedendpoints=$number_endpoints"
Write-Host $body

$body="veeam-stats totalbackupread=$totalReadBk"
Write-Host $body

$Count = $runningSessionsRepl.Count
$body="veeam-stats runningreplications=$Count"
Write-Host $body

#endregion

#region: Debug
if ($DebugPreference -eq "Inquire") {
	$RepoReport | ft * -Autosize
    
    $SessionObject = [PSCustomObject] @{
	    "Successful Backups"  = $successSessionsBk.Count
	    "Warning Backups" = $warningSessionsBk.Count
	    "Failes Backups" = $failsSessionsBk.Count
	    "Failed Backups" = $failedSessionsBk.Count
	    "Running Backups" = $runningSessionsBk.Count
	    "Warning BackupCopys" = $warningSessionsBkC.Count
	    "Failes BackupCopys" = $failsSessionsBkC.Count
	    "Failed BackupCopys" = $failedSessionsBkC.Count
	    "Running BackupCopys" = $runningSessionsBkC.Count
	    "Idle BackupCopys" = $IdleSessionsBkC.Count
	    "Successful Replications" = $successSessionsRepl.Count
        "Warning Replications" = $warningSessionsRepl.Count
        "Failes Replications" = $failsSessionsRepl.Count
        "Failed Replications" = $failedSessionsRepl.Count
        "Running Replications" = $RunningSessionsRepl.Count
    }
    $SessionResport += $SessionObject
    $SessionResport
}
#endregion
