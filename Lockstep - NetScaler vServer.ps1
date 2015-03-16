###############################################################################
#
# netscaler snmp monitoring for prtg
# jsanders@lockstepgroup.com
# 3/6/2014
#
###############################################################################
# script parameters

Param (
	[Parameter(Position=0)]
	[string]$vServerIndex
)

$TargetDevice = $env:prtg_host
$SnmpCommunityString = $env:prtg_snmpcommunity	

# parameter options to require this don't send enough info back to prtg. do it manual!
# is there a better way to handle this?
if (!($TargetDevice)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please set "Set placeholders as environment values" in sensor options</text>
</prtg>
"@
}

if (!($SnmpCommunityString)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please set "Set placeholders as environment values" in sensor options and provide SNMP community string in device settings</text>
</prtg>
"@
}


if (!($vServerIndex)) {
	return @"
<prtg>
  <error>1</error>
  <text>Required parameter not specified: please set vServer index (as integer) in sensor parameters</text>
</prtg>
"@
}

###############################################################################
# load the prtgshell module and the sharpsnmp modules


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


$ModuleImportSuccess = Import-MyModule sharpsnmp

if (!($ModuleImportSuccess)) {
	return @"
<prtg>
  <error>1</error>
  <text>sharpsnmp module not loaded: ensure the module is visible for 32-bit PowerShell</text>
</prtg>
"@
}


###############################################################################
# assembly loading

# load the assembly; this can be try/catch wrapped if error handling
# this doesn't error out if it's reloaded
if (!([Reflection.Assembly]::LoadWithPartialName("SharpSnmpLib")).GlobalAssemblyCache ) {
	return @"
<prtg>
  <error>1</error>
  <text>SharpSnmp Assembly not loaded: please ensure assembly is installed to GAC</text>
</prtg>
"@
}

###############################################################################

$OIDList = ConvertFrom-Csv @"
ord,name,oid,desc
1,vsvrName,1.3.6.1.4.1.5951.4.1.3.1.1.1,The name of the vserver
2,vsvrIpAddress,1.3.6.1.4.1.5951.4.1.3.1.1.2,IP address of the vserver
3,vsvrPort,1.3.6.1.4.1.5951.4.1.3.1.1.3,the port of the vserver
4,vsvrType,1.3.6.1.4.1.5951.4.1.3.1.1.4,Protocol associated with the vserver
5,vsvrState,1.3.6.1.4.1.5951.4.1.3.1.1.5,"Current state of the server. Possible values are UP, DOWN, UNKNOWN, OFS(Out of Service), TROFS(Transition Out of Service), TROFS_DOWN(Down When going Out of Service)"
7,vsvrCurClntConnections,1.3.6.1.4.1.5951.4.1.3.1.1.7,Number of current client connections.
8,vsvrCurSrvrConnections,1.3.6.1.4.1.5951.4.1.3.1.1.8,Number of current connections to the actual servers behind the virtual server.
10,vsvrSurgeCount,1.3.6.1.4.1.5951.4.1.3.1.1.10,Number of requests in the surge queue.
30,vsvrTotalRequests,1.3.6.1.4.1.5951.4.1.3.1.1.30,Total number of requests received on this service or virtual server. (This applies to HTTP/SSL services and servers.)
31,vsvrTotalRequestBytes,1.3.6.1.4.1.5951.4.1.3.1.1.31,Total number of request bytes received on this service or virtual server.
32,vsvrTotalResponses,1.3.6.1.4.1.5951.4.1.3.1.1.32,Number of responses received on this service or virtual server. (This applies to HTTP/SSL services and servers.)
33,vsvrTotalResponseBytes,1.3.6.1.4.1.5951.4.1.3.1.1.33,Number of response bytes received by this service or virtual server.
34,vsvrTotalPktsRecvd,1.3.6.1.4.1.5951.4.1.3.1.1.34,Total number of packets received by this service or virtual server.
35,vsvrTotalPktsSent,1.3.6.1.4.1.5951.4.1.3.1.1.35,Total number of packets sent.
36,vsvrTotalSynsRecvd,1.3.6.1.4.1.5951.4.1.3.1.1.36,Total number of SYN packets received from clients on this service (only when directly accessed) or virtual server.
37,vsvrCurServicesDown,1.3.6.1.4.1.5951.4.1.3.1.1.37,The current number of services which are bound to this vserver and are in the state 'down'.
38,vsvrCurServicesUnKnown,1.3.6.1.4.1.5951.4.1.3.1.1.38,The current number of services which are bound to this vserver and are in the state 'unKnown'.
39,vsvrCurServicesOutOfSvc,1.3.6.1.4.1.5951.4.1.3.1.1.39,The current number of services which are bound to this vserver and are in the state 'outOfService'.
40,vsvrCurServicesTransToOutOfSvc,1.3.6.1.4.1.5951.4.1.3.1.1.40,The current number of services which are bound to this vserver and are in the state 'transitionToOutOfService'.
41,vsvrCurServicesUp,1.3.6.1.4.1.5951.4.1.3.1.1.41,The current number of services which are bound to this vserver and are in the state 'up'.
42,vsvrTotMiss,1.3.6.1.4.1.5951.4.1.3.1.1.42,Total vserver misses
43,vsvrRequestRate,1.3.6.1.4.1.5951.4.1.3.1.1.43,Request rate in requests per second for this service or virtual server.
44,vsvrRxBytesRate,1.3.6.1.4.1.5951.4.1.3.1.1.44,Request rate in bytes per second fot this service or virtual server.
45,vsvrTxBytesRate,1.3.6.1.4.1.5951.4.1.3.1.1.45,Response rate in bytes per second for this service or virtual server.
46,vsvrSynfloodRate,1.3.6.1.4.1.5951.4.1.3.1.1.46,Rate of unacknowledged SYN packets for this service or virtual server.
47,vsvrIp6Address,1.3.6.1.4.1.5951.4.1.3.1.1.47,IPv6 address of the v server
48,vsvrTotHits,1.3.6.1.4.1.5951.4.1.3.1.1.48,Total vserver hits
54,vsvrTotSpillOvers,1.3.6.1.4.1.5951.4.1.3.1.1.54,Number of times vserver experienced spill over.
56,vsvrTotalClients,1.3.6.1.4.1.5951.4.1.3.1.1.56,Total number of established client connections.
58,vsvrClientConnOpenRate,1.3.6.1.4.1.5951.4.1.3.1.1.58,Rate at which connections are opened for this virtual server per second.
59,vsvrFullName,1.3.6.1.4.1.5951.4.1.3.1.1.59,The name of the vserver
60,vsvrCurSslVpnUsers,1.3.6.1.4.1.5951.4.1.3.1.1.60,Number of aaa sessions on this vserver
61,vsvrTotalServicesBound,1.3.6.1.4.1.5951.4.1.3.1.1.61,The current number of services which are bound to this vserver.
62,vsvrHealth,1.3.6.1.4.1.5951.4.1.3.1.1.62,The percentage of UP services bound to this vserver.
63,vsvrTicksSinceLastStateChange,1.3.6.1.4.1.5951.4.1.3.1.1.63,Time (in 10 milliseconds) since the last state change.
64,vsvrEntityType,1.3.6.1.4.1.5951.4.1.3.1.1.64,The type of the vserver.
65,vsvrTotalServers,1.3.6.1.4.1.5951.4.1.3.1.1.65,Total number of established server connections.
66,vsvrActiveActiveState,1.3.6.1.4.1.5951.4.1.3.1.1.66,The state of the vserver based on ActiveActive configuration.
67,vsvrInvalidRequestResponse,1.3.6.1.4.1.5951.4.1.3.1.1.67,Number invalid requests/responses on this vserver
68,vsvrInvalidRequestResponseDropped,1.3.6.1.4.1.5951.4.1.3.1.1.68,Number invalid requests/responses dropped on this vserver
69,vsvrTdId,1.3.6.1.4.1.5951.4.1.3.1.1.69,Traffic Domain of the vserver
"@

###############################################################################

function GetPrefix ($name) {
	($OIDList | ? { $_.name -eq $name }).oid
}

function GetSnmpData($name,$index = -1) {
	if ($index -gt -1) {
		(Invoke-SnmpGet $TargetDevice $SnmpCommunityString ((GetPrefix $name) + ($OidSuffixes[$index].OidSuffix))).Data
	} else {
		Invoke-SnmpWalk $TargetDevice $SnmpCommunityString (GetPrefix $name)
	}
}

function GetFullOid($name,[int]$index = -1) {
	if ($index -gt -1) {
		(GetPrefix $name) + ($OidSuffixes[$index].OidSuffix)
	} else {
		GetPrefix $name
	}
}


###############################################################################

$vsvrName = Invoke-SnmpWalk $TargetDevice $SnmpCommunityString ($OIDList[0].oid) # this gets the vsvrNames and their full OIDs
$OidSuffixes = $vsvrName | % {
	$ThisOID = $_
	"" | select @{
		n = "Name"
		e = {
			$ThisOID.Data
		}
	},@{
		n = "OidSuffix"
		e = {
			$ThisOID.OID -replace ("." + ($OIDList[0].oid))
		}
	}
}

###############################################################################
<#
$OidsToPoll = @("vsvrName","vsvrIpAddress","vsvrPort","vsvrType","vsvrState" | % {
	GetFullOid $_ $VsvrIndex
})

Invoke-SnmpGet $TargetDevice $SnmpCommunityString $OidsToPoll
#>
###############################################################################

function GetAllValues($VsvrIndex) {

	$ReturnedData = Invoke-SnmpGet $TargetDevice $SnmpCommunityString @(
		$OIDList | % { $_.name } | % { GetFullOid $_ $VsvrIndex }
	)

	$i = 0; $vServerData = foreach ($OID in $OidList) {
		"" | select @{
			n = "name"
			e = {
				$OID.name
			}
		},@{
			n = "desc"
			e = {
				$OID.desc
			}
		},@{
			n = "value"
			e = {
				$ReturnedData[$i].Data
			}
		},@{
			n = "FullOid"
			e = {
				$ReturnedData[$i].OID
			}
		}
		$i++
	}
	
	$vServerData
}

###############################################################################

$vServerData = GetAllValues $vServerIndex

###############################################################################
# type definitions

$TypeEntityState = "","down","unknown","busy","outOfService","transitionToOutOfService","","up","transitionToOutOfServiceDown"

$TypeEntityProtocolType = "http","ftp","tcp","udp","sslBridge","monitor","monitorUdp","nntp","httpserver","httpclient","rpcserver","rpcclient","nat","any","ssl","dns","adns","snmp","ha","monitorPing","sslOtherTcp","aaa","secureMonitor","sslvpnUdp","rip","dnsClient","rpcServer","rpcClient","","","","","","","","dhcrpa","","","sipudp","","","","","dnstcp","adnstcp","rtsp","","push","sslPush","dhcpClient","radius","","serviceUnknown"
$TypeVServerType = "unknown","loadbalancing","loadbalancinggroup","sslvpn","contentswitching","cacheredirection"

###############################################################################
# output

$ReturnText = ($vServerData[0].value + ": " + $TypeEntityProtocolType[$vServerData[3].value] + " " + $TypeVServerType[$vServerData[35].value] + " (" + $vServerData[1].value + ":" + $vServerData[2].value + ")")

$XMLOutput = "<prtg>`n"
$XMLOutput += Set-PrtgResult "vServer State" ([int]$vServerData[4].value) "state" -ValueLookup lockstep.sensor.citrix.netscaler.vsvrState
$XMLOutput += Set-PrtgResult "Current Client Connections" ([int]$vServerData[5].value) "connections"
$XMLOutput += Set-PrtgResult "Current Server Connections" ([int]$vServerData[6].value) "connections"
$XMLOutput += Set-PrtgResult "Total Requests" ([int]$vServerData[8].value) "requests" -Mode "Counter"
#$XMLOutput += Set-PrtgResult "Services Down" ([int]$vServerData[15].value) "services"
#$XMLOutput += Set-PrtgResult "Services Up" ([int]$vServerData[19].value) "services"
$XMLOutput += Set-PrtgResult "Total Hits" ([int]$vServerData[26].value) "connections" -Mode "Counter"
$XMLOutput += Set-PrtgResult "Total Client Connections" ([int]$vServerData[28].value) "connections" -Mode "Counter"
$XMLOutput += Set-PrtgResult "Percentage of Services Up" ([int]$vServerData[33].value) "percent" # this doesn't seem to be a 100% reliable 

#uptime $vServerData[34]

$XMLOutput += "  <text>$ReturnText</text>"
$XMLOutput += "</prtg>"

$XMLOutput

