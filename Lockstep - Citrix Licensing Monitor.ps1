###############################################################################
# 
# prtg citrix licensing server monitor
# mar 14, 2013
# jsanders@lockstepgroup.com
#
###############################################################################
#
# tests to run:
#   - test that licensing is installed (check that wmi namespace exists)
#   - test that licensing WMI functions (try/catch the wmi query)
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
			return "Error: ($ComputerName): " + $_.Exception.InnerException.Message
		} else {
			return "Error: ($ComputerName): " + $_.Exception.Message
		}
	}
	
	if ($ServiceStatus -eq "OK") {
		return $true
	} else {
		return "Error: ($ComputerName): $ServiceName not running."
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
# license status

$ReturnText = "OK" #default value

$LicensingData = Get-WmiObject -class "Citrix_GT_License_Pool" -Namespace "ROOT\CitrixLicensing" -ComputerName $ComputerName | Select Count,InUseCount,PooledAvailable,Overdraft,PLD,LicenseType,PercentAvailable,PercentInUse

$LicensingData | % {
	$_.PercentAvailable = [float] ("{0:N2}" -f (($_.PooledAvailable/$_.Count)*100))
	$_.PercentInUse = [float] ("{0:N2}" -f (($_.InUseCount/$_.Count)*100))
}

###############################################################################
# services status

$ServiceNames = @("Citrix Licensing"
                  "Citrix_GTLicensingProv"
                  "CitrixLicensingConfigService"
				  "CtxLSPortSvc")

$Services = Get-Service $ServiceNames -ComputerName $ComputerName -ErrorAction SilentlyContinue


###############################################################################
# output

$XMLOutput = "<prtg>`n"

foreach ($Service in $Services) {
	if ($Service.Status -ne "Running") { $State = 1 } else { $State = 0 }
	$XmlOutput += Set-PrtgResult $("Service: " + $Service.DisplayName) $State state -me 0 -em "Service is not running"
}

foreach ($License in $LicensingData) {
	$XMLOutput += Set-PrtgResult ($License.PLD + ": Percent In Use") $License.PercentInUse "Percent" -MaxWarn 90 -MaxError 100 -WarnMsg (($License.PercentInUse).toString() + "% of licenses allocated.") -ErrorMsg "No more licenses available." -ShowChart
	$XMLOutput += Set-PrtgResult ($License.PLD + ": Available") $License.PooledAvailable "#"
}

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput
