###############################################################################
# 
# prtg terminal services licensing server monitor
# mar 15, 2013
# jsanders@lockstepgroup.com
#
###############################################################################
#
# this presently monitors "license usage," although not that well, because per-user RDS isn't enforced/tracked.
# this means that this sensor will currently always report a valid number of licenses, but none issued.
#
# what this needs to monitor:
#  what server does the target recognize as the licensing host?
#  is the licensing host licensed?
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

$CheckServer = Get-TargetStatus $ComputerName "TermServLicensing"

if ($CheckServer -ne $true) {
	return @"
<prtg>
  <error>1</error>
  <text>$CheckServer</text>
</prtg>
"@
}

###############################################################################

function Get-RDSLicensingDetails {
	Param (
		[Parameter(mandatory=$True,Position=0)]
		[string]$ComputerName
	)

	$LicenseServer = $null

	try {
		$reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName)
		$regkey = $reg.OpenSubkey("SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services")
		$LicenseServer = $regkey.GetValue("LicenseServers")
	} catch {
		write-host "value missing or no permissions"
	}

	$LicenseDetails = Get-WmiObject -class "Win32_TerminalServiceSetting" -ComputerName $ComputerName -Namespace "root\CIMV2\TerminalServices" -Authentication 6 | Select LicensingName,LicensingType,LicenseServer

	$LicenseDetails.LicenseServer = $LicenseServer

	$LicenseDetails
}


###############################################################################
# license status

# ProductVersionID of 0 is "unsupported" or "invalid"
$LicensingData = Get-WmiObject -class "Win32_TSLicenseKeyPack" -filter "ProductVersionID > 0" -ComputerName $ComputerName -ErrorAction SilentlyContinue| Select TotalLicenses,IssuedLicenses,AvailableLicenses,ProductVersion

if (!($LicensingData)) {
	return @"
<prtg>
  <error>1</error>
  <text>Service running, but no licensing data returned</text>
</prtg>
"@
}

$ReturnText = $LicensingData.ProductVersion

###############################################################################
# output

$XMLOutput = "<prtg>`n"

$XMLOutput += Set-PrtgResult "Total Licenses" $LicensingData.TotalLicenses "#"
$XMLOutput += Set-PrtgResult "Total Licenses" $LicensingData.IssuedLicenses "#"
$XMLOutput += Set-PrtgResult "Total Licenses" $LicensingData.AvailableLicenses "#"

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput
