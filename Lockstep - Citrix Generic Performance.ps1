###############################################################################
# 
# prtg citrix xenapp monitor (generic performance)
# mar 4, 2013
# jsanders@lockstepgroup.com
#
###############################################################################
#
# Citrix documentation on this subject
# http://support.citrix.com/article/CTX133540
#
###############################################################################
#
# PRTG configuration:
#   ensure the executing security context has the needed permissions
#    this likely means "Use Windows credentials of parent device"
#   also set "Parameters to "%host" (without the quotes).
#
###############################################################################
# script parameters

Param (
	[Parameter(Position=0)]
	[string]$ComputerName
)

# parameter options to require this don't send enough info back to prtg. do it manual!
# is there a better way to handle this?
if (!($ComputerName)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please provide target hostname (or %host)</text>
</prtg>
"@
}

$TimerStart = Get-Date

###############################################################################
# load the prtgshell module

function Import-MyModule {
	Param(
		[string]$Name
	)
	
	if ( -not (Get-Module -Name $Name) ) {
		if ( Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name } ) {
			Import-Module -Name $Name
			$true # module installed + loaded
		} else {
			$false # module not installed
		}
	}
	else {
		$true # module already loaded
	}
}

$ModuleImportSuccess = Import-MyModule PrtgShell

if (!($ModuleImportSuccess)) {
	return @"
<prtg>
  <error>1</error>
  <text>PrtgShell module not loaded: ensure the module is visible for 32-bit PowerShell</text>
</prtg>
"@
}

###############################################################################
# initial wmi connection tests (fail-fast)

function Get-TargetStatus {
	Param (
		[Parameter(mandatory=$True,Position=0)]
		[string]$ComputerName,
		[Parameter(Position=1)]
		[string]$ServiceName = "SamSs"
	)

	$wmi = [WMISearcher]""
	$wmi.options.timeout = '0:0:5' # 5-second timeout
	$wmi.scope.path = "\\$ComputerName\Root\CIMV2"
	$wmi.query = 'Select Status from Win32_Service where Name= "' + $ServiceName + '"'
	
	try {
		$ServiceStatus = ($wmi.Get() | select Status).Status
	} catch {
		if ($_.Exception.InnerException) {
			return "Error: $($ComputerName): " + $_.Exception.InnerException.Message
		} else {
			return "Error: $($ComputerName): " + $_.Exception.Message
		}
	}
	
	if ($ServiceStatus -eq "OK") {
		return $true
	} else {
		return "Error: $($ComputerName): $ServiceName not running."
	}
}

$CheckServer = Get-TargetStatus $ComputerName

if ($CheckServer -ne $true) {
	return @"
<prtg>
  <error>1</error>
  <text>$CheckServer</text>
</prtg>
"@
}

###############################################################################

$ReturnText = "OK" # this is the default

###############################################################################
#### queries from citrix documentation: "Operations Guide - Monitoring.pdf"

# system counters

$wql = "Select PercentProcessorTime from Win32_PerfFormattedData_PerfOS_Processor where name='_total'"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$SystemPercentProcessorTime = $QueryObject.PercentProcessorTime # warn at 80% for 15 minutes

# this is for the script metrics, not xenapp
$TimerInitialExecution = Get-Date

$wql = "Select ProcessorQueueLength from Win32_PerfFormattedData_PerfOS_System"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$SystemProcessorQueueLength = $QueryObject.ProcessorQueueLength # warn at 5 (per Core) for 5 minutes

$wql = "Select AvailableBytes,PagesPerSec from Win32_PerfFormattedData_PerfOS_Memory"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$SystemAvailableBytes = $QueryObject.AvailableBytes # warn at <30% of total RAM
$SystemPagesPerSec = $QueryObject.PagesPerSec # warn at >10

$wql = "Select CurrentUsage from Win32_PageFileUsage"
$QueryObject = @(Get-WmiObject -Query $wql -computername $computername)
$SystemPagefileCurrentUsage = $QueryObject[0].CurrentUsage # warn at >40%

if ($QueryObject.Count -gt 1) {
	$ReturnText = "Multiple Page Files!"
}

$wql = "Select PercentDiskTime,CurrentDiskQueueLength,AvgDisksecPerRead,AvgDisksecPerTransfer,AvgDisksecPerWrite from Win32_PerfFormattedData_PerfDisk_PhysicalDisk where name='_Total'"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$SystemPercentDiskTime = $QueryObject.PercentDiskTime # warn at >70% consistently
$SystemCurrentDiskQueueLength = $QueryObject.CurrentDiskQueueLength # warn at >=1 (per spindle) consistently
$SystemAvgDisksecPerRead = $QueryObject.AvgDisksecPerRead # warn at >=15ms consistently
$SystemAvgDisksecPerTransfer = $QueryObject.AvgDisksecPerTransfer # warn at >=15ms consistently
$SystemAvgDisksecPerWrite = $QueryObject.AvgDisksecPerWrite # warn at >=15ms consistently


###############################################################################

$TimerStop = Get-Date

$InitialExecutionTime = $TimerInitialExecution - $TimerStart
$ExecutionTime = $TimerStop - $TimerStart

###############################################################################
# output

$XMLOutput = "<prtg>`n"

$XMLOutput += Set-PrtgResult "Sensor Initial WMI Connection Time" $InitialExecutionTime.TotalMilliseconds "ms" -ShowChart
$XMLOutput += Set-PrtgResult "Sensor Total Execution Time" $ExecutionTime.TotalMilliseconds "ms" -ShowChart
$XMLOutput += Set-PrtgResult "Processor Time (Percent)" $SystemPercentProcessorTime "Percent" -ShowChart -MaxWarn 80 -WarnMsg "CPU Usage high"
$XMLOutput += Set-PrtgResult "Processor Queue Length" $SystemProcessorQueueLength "#" -ShowChart
$XMLOutput += Set-PrtgResult "Memory - Available Bytes" $SystemAvailableBytes "BytesMemory" -ShowChart
$XMLOutput += Set-PrtgResult "Memory - Pages/sec" $SystemPagesPerSec "#" -ShowChart -MaxWarn 10 -WarnMsg "Potential memory bottleneck"
$XMLOutput += Set-PrtgResult "Page File Percent Usage" $SystemPagefileCurrentUsage "Percent" -ShowChart
$XMLOutput += Set-PrtgResult "Disk Time (Percent)" $SystemPercentDiskTime "Percent" -ShowChart -MaxWarn 40 -WarnMsg "High Page File usage"
$XMLOutput += Set-PrtgResult "Disk Queue Length (Current)" $SystemCurrentDiskQueueLength "#" -ShowChart -MaxWarn 70 -WarnMsg "High disk queue length"
$XMLOutput += Set-PrtgResult "Disk Average Seconds Per Read" $SystemAvgDisksecPerRead "ms" -ShowChart -MaxWarn 15 -WarnMsg "High Average Disk Seconds Per Read"
$XMLOutput += Set-PrtgResult "Disk Average Seconds Per Transfer" $SystemAvgDisksecPerTransfer "ms" -ShowChart -MaxWarn 15 -WarnMsg "High Average Disk Seconds Per Transfer"
$XMLOutput += Set-PrtgResult "Disk Average Seconds Per Write" $SystemAvgDisksecPerWrite "ms" -ShowChart -MaxWarn 15 -WarnMsg "High Average Disk Seconds Per Write"

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput
