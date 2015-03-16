###############################################################################
# 
# prtg citrix xenapp farm monitor
# mar 15, 2013
# jsanders@lockstepgroup.com
#
###############################################################################
#
# this depends on one of these snapin modules being installed on the prtg server or probe server:
#  - Citrix.XenApp.Commands.Client.Install_x64.msi
#  - Citrix.XenApp.Commands.Client.Install_x86.msi
# these can be located on the XenApp installation CD
#
##############################################################################
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

"Citrix.XenApp.Commands" | % {
	# checks if snapins are installed/registered
	if (!(Get-PSSnapin -Registered $_ -ErrorAction SilentlyContinue)) {
		$ErrorText = "Snapin $_ missing!"
		return @"
<prtg>
  <error>1</error>
  <text>$ErrorText</text>
</prtg>
"@
	}
	# checks if snapins are loaded
	if ((Get-PSSnapin -Name $_ -ErrorAction SilentlyContinue) -eq $null) {
		Add-PsSnapin $_
	}
}

###############################################################################

try {
	$XenAppSessions = Get-XASession -ComputerName $ComputerName
	
	$XenAppUsersConnectedSessions = @($XenAppSessions | ? { $_.State -eq "Connected" }).Count
	$XenAppUsersDisconnectedSessions = @($XenAppSessions | ? { $_.State -eq "Disconnected" }).Count

	$XenAppAdministratorsCount = @(Get-XAAdministrator -ComputerName $ComputerName).Count
	$XenAppServersInFarm = @(Get-XAServer -ComputerName $ComputerName).Count

	$XenAppApplications = Get-XAApplication -ComputerName $ComputerName

	$XenAppPublishedApplicationsCount = @($XenAppApplications | ? { $_.ApplicationType -eq "ServerInstalled" }).Count
	$XenAppPublishedDesktopsCount = @($XenAppApplications | ? { $_.ApplicationType -eq "ServerDesktop" }).Count
	$XenAppPublishedContentCount = @($XenAppApplications | ? { $_.ApplicationType -eq "Content" }).Count

	$XenAppWorkerGroupsCount = @(Get-XAWorkerGroup -ComputerName $ComputerName).Count

	$XenAppZoneCount = @(Get-XAZone -ComputerName $ComputerName).Count
} catch {
	if ($_.Exception.InnerException) {
		$ErrorText = "Error: $($ComputerName): " + $_.Exception.InnerException.Message
	} else {
		$ErrorText = "Error: $($ComputerName): " + $_.Exception.Message
	}
	
	return @"
<prtg>
  <error>1</error>
  <text>$ErrorText</text>
</prtg>
"@
}


###############################################################################
# output

$XMLOutput = "<prtg>`n"

$XMLOutput += Set-PrtgResult "ICA Sessions: Connected" $XenAppUsersConnectedSessions "#" -ShowChart
$XMLOutput += Set-PrtgResult "ICA Sessions: Disconnected" $XenAppUsersDisconnectedSessions "#" -ShowChart
$XMLOutput += Set-PrtgResult "Administrators (Users + Groups)" $XenAppAdministratorsCount "#"
$XMLOutput += Set-PrtgResult "Zones" $XenAppZoneCount "#"
$XMLOutput += Set-PrtgResult "Servers in farm" $XenAppServersInFarm "#"
$XMLOutput += Set-PrtgResult "Server Worker Groups" $XenAppWorkerGroupsCount "#"
$XMLOutput += Set-PrtgResult "Published Applications" $XenAppPublishedApplicationsCount "#"
$XMLOutput += Set-PrtgResult "Published Desktops" $XenAppPublishedDesktopsCount "#"
$XMLOutput += Set-PrtgResult "Published Content Items" $XenAppPublishedContentCount "#"

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput
