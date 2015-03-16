###############################################################################
# 
# prtg citrix xenapp monitor (xenapp performance + growth)
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

$CheckServer = Get-TargetStatus $ComputerName "IMAService"

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

# XenApp Performance Counters

$wql = "Select ApplicationResolutionTimems,DataStoreConnectionFailure,NumberofbusyXMLthreads,ResolutionWorkItemQueueReadyCount,WorkItemQueueReadyCount,ApplicationResolutionsPersec,ApplicationEnumerationsPersec,FilteredApplicationEnumerationsPersec from Win32_PerfFormattedData_MetaFrameXP_CitrixMetaFramePresentationServer"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$ApplicationResolutionTimems = $QueryObject.ApplicationResolutionTimems # baseline to determine thresholds
$DataStoreConnectionFailure = $QueryObject.DataStoreConnectionFailure # warning: over one minute
$NumberofbusyXMLthreads = $QueryObject.NumberofbusyXMLthreads # warning at 10; 16 is "full", there's 16 threads
$ResolutionWorkItemQueueReadyCount = $QueryObject.ResolutionWorkItemQueueReadyCount # warn at greater than zero
$WorkItemQueueReadyCount = $QueryObject.WorkItemQueueReadyCount # warn at greater than zero

# XenApp Growth Tracking
$ApplicationResolutionsPersec = $QueryObject.ApplicationResolutionsPersec
$ApplicationEnumerationsPersec = $QueryObject.ApplicationEnumerationsPersec
$FilteredApplicationEnumerationsPersec = $QueryObject.FilteredApplicationEnumerationsPersec

# this is for the script metrics, not xenapp
$TimerInitialExecution = Get-Date

# for growth tracking
$wql = "Select TotalSessions from Win32_TerminalService"
$QueryObject = Get-WmiObject -Query $wql -computername $computername

if ($QueryObject) {
	#windows 2008
	$TotalSessions = $QueryObject.TotalSessions
} else {
	#windows 2003
	$wql = "Select TotalSessions from Win32_PerfFormattedData_TermService_TerminalServices"
	$QueryObject = Get-WmiObject -Query $wql -computername $computername
	$TotalSessions = $QueryObject.TotalSessions
}


$wql = "Select LicenseServerConnectionFailure,LastRecordedLicenseCheckOutResponseTimems,AverageLicenseCheckOutResponseTimems from Win32_PerfFormattedData_CitrixLicensing_CitrixLicensing"
try {
	$QueryObject = Get-WmiObject -Query $wql -computername $computername -ErrorAction Stop
	$LicenseServerConnectionFailure = $QueryObject.LicenseServerConnectionFailure # warning at greater than 1 minute, failure at 1440 minutes (one day)
	$LastRecordedLicenseCheckOutResponseTimems = $QueryObject.LastRecordedLicenseCheckOutResponseTimems # warning at 2000 ms, error at 5000 ms

	# XenApp Growth Tracking
	$AverageLicenseCheckOutResponseTimems = $QueryObject.AverageLicenseCheckOutResponseTimems
} catch {
	# do nothing, just silence the error
}

###############################################################################

$TimerStop = Get-Date

$InitialExecutionTime = $TimerInitialExecution - $TimerStart
$ExecutionTime = $TimerStop - $TimerStart

###############################################################################
# output

$XMLOutput = "<prtg>`n"

$XMLOutput += Set-PrtgResult "Sensor Initial WMI Connection Time" $InitialExecutionTime.TotalMilliseconds "ms"
$XMLOutput += Set-PrtgResult "Sensor Total Execution Time" $ExecutionTime.TotalMilliseconds "ms"

if ($ApplicationResolutionTimems -ne $null) { $XMLOutput += Set-PrtgResult "Application Resolution Time" $ApplicationResolutionTimems "ms" -ShowChart }
if ($DataStoreConnectionFailure -ne $null) { $XMLOutput += Set-PrtgResult "Datastore Connection Failure" $DataStoreConnectionFailure "minutes" -MaxWarn 1 -WarnMsg "Data store disconnected for more than one minute." }
if ($NumberofbusyXMLthreads -ne $null) { $XMLOutput += Set-PrtgResult "Number of busy XML threads" $NumberofbusyXMLthreads "#" -ShowChart -MaxWarn 10 -MaxError 16 -WarnMsg "XML threads queue deep." -ErrorMsg "XML threads queue full." }
if ($ResolutionWorkItemQueueReadyCount -ne $null) { $XMLOutput += Set-PrtgResult "Resolution WorkItem Queue Ready Count" $ResolutionWorkItemQueueReadyCount "#" -ShowChart -MaxWarn 1 -WarnMsg "WorkItem requests queuing." }
if ($WorkItemQueueReadyCount -ne $null) { $XMLOutput += Set-PrtgResult "WorkItem Queue Ready Count" $WorkItemQueueReadyCount "#" -ShowChart -MaxWarn 1 -WarnMsg "WorkItem requests queuing." }

if ($LicenseServerConnectionFailure -ne $null) { $XMLOutput += Set-PrtgResult "Licensing: Server Connection Failure" $LicenseServerConnectionFailure "minutes" -MaxWarn 1 -MaxError 1440 -WarnMsg "Disconnected from Licensing Server (grace period)." -ErrorMsg "Disconnected from Licensing Server." }
if ($LastRecordedLicenseCheckOutResponseTimems -ne $null) { $XMLOutput += Set-PrtgResult "Licensing: Check-Out Response Time" $LastRecordedLicenseCheckOutResponseTimems "ms" -ShowChart -MaxWarn 2000 -MaxError 5000 -WarnMsg "High latency license check-outs from License Server." -ErrorMsg "Extremely high latency license check-outs from License Server." }

if ($ApplicationResolutionsPersec -ne $null) { $XMLOutput += Set-PrtgResult "Growth: Application Resolutions/sec" $ApplicationResolutionsPersec "#" }
if ($ApplicationEnumerationsPersec -ne $null) { $XMLOutput += Set-PrtgResult "Growth: Application Enumerations/sec" $ApplicationEnumerationsPersec "#" }
if ($FilteredApplicationEnumerationsPersec -ne $null) { $XMLOutput += Set-PrtgResult "Growth: Filtered Application Enumerations/sec" $FilteredApplicationEnumerationsPersec "#" }
if ($TotalSessions -ne $null) { $XMLOutput += Set-PrtgResult "Growth: Terminal Services Total Sessions" $TotalSessions "#" }
if ($AverageLicenseCheckOutResponseTimems -ne $null) { $XMLOutput += Set-PrtgResult "Growth: Average License Check-Out Response" $AverageLicenseCheckOutResponseTimems "ms" }

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput
