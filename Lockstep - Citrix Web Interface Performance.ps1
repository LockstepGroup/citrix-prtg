###############################################################################
# 
# prtg citrix xenapp monitor (web interface performance)
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

$CheckServer = Get-TargetStatus $ComputerName "CitrixICAFileSigningService"

if ($CheckServer -ne $true) {
	return @"
<prtg>
  <error>1</error>
  <text>$CheckServer</text>
</prtg>
"@
}

###############################################################################
#### queries from citrix documentation: "Operations Guide - Monitoring.pdf"

# XenApp Performance Counters

$wql = "Select * from Win32_PerfFormattedData_ASPNET_ASPNET"
$QueryObject = Get-WmiObject -Query $wql -computername $computername
$ASPNETRequestsQueued = $QueryObject.RequestsQueued # baseline to determine thresholds
$ASPNETRequestsRejected = $QueryObject.RequestsRejected # greater than 1 = failure

# this is for the script metrics, not xenapp
$TimerInitialExecution = Get-Date


###############################################################################

$TimerStop = Get-Date

$InitialExecutionTime = $TimerInitialExecution - $TimerStart
$ExecutionTime = $TimerStop - $TimerStart

###############################################################################
# output

$XMLOutput = "<prtg>`n"

$XMLOutput += Set-PrtgResult "Sensor Initial WMI Connection Time" $InitialExecutionTime.TotalMilliseconds "ms"
$XMLOutput += Set-PrtgResult "Sensor Total Execution Time" $ExecutionTime.TotalMilliseconds "ms"

$XMLOutput += Set-PrtgResult "ASP.NET Requests Queued" $ASPNETRequestsQueued "Requests" -ShowChart
$XMLOutput += Set-PrtgResult "ASP.NET Requests Failed" $ASPNETRequestsRejected "Requests" -MaxWarn 1 -WarnMsg "Web Service requests denied; server too busy."
$XMLOutput += "  <text>OK</text>"
$XMLOutput += "</prtg>"

$XMLOutput
