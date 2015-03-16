###############################################################################
###############################################################################
#
# XenDesktop Desktop Usage
#
#  v1: December 2012
#  v2: December 2014
#
#  Josh Sanders
#  jsanders@lockstepgroup.com
#
###############################################################################
###############################################################################
# get params

Param (
	[Parameter(Position=0)]
	[string[]]$HostingServers
)

$TargetDevice = $env:prtg_host

###############################################################################
###############################################################################
# load snapin(s)

$snapins =
	"Citrix.Broker.Admin.V2"

$snapins | % {
	if ((Get-PSSnapin -Name $_ -ErrorAction SilentlyContinue) -eq $null) {
		Add-PsSnapin $_
	}
}

###############################################################################
###############################################################################
# functions

function Set-PrtgError {
	Param (
		[Parameter(Position=0)]
		[string]$PrtgErrorText
	)
	
	@"
<prtg>
  <error>1</error>
  <text>$PrtgErrorText</text>
</prtg>
"@

	exit
}

function Set-PrtgResult {
    Param (
    [Parameter(mandatory=$True,Position=0)]
    [string]$Channel,
    
    [Parameter(mandatory=$True,Position=1)]
    $Value,
    
    [Parameter(mandatory=$True,Position=2)]
    [string]$Unit,

    [Parameter(mandatory=$False)]
    [alias('mw')]
    [string]$MaxWarn,

    [Parameter(mandatory=$False)]
    [alias('minw')]
    [string]$MinWarn,
    
    [Parameter(mandatory=$False)]
    [alias('me')]
    [string]$MaxError,
    
    [Parameter(mandatory=$False)]
    [alias('wm')]
    [string]$WarnMsg,
    
    [Parameter(mandatory=$False)]
    [alias('em')]
    [string]$ErrorMsg,
    
    [Parameter(mandatory=$False)]
    [alias('mo')]
    [string]$Mode,
    
    [Parameter(mandatory=$False)]
    [alias('sc')]
    [switch]$ShowChart,
    
    [Parameter(mandatory=$False)]
    [alias('ss')]
    [ValidateSet("One","Kilo","Mega","Giga","Tera","Byte","KiloByte","MegaByte","GigaByte","TeraByte","Bit","KiloBit","MegaBit","GigaBit","TeraBit")]
    [string]$SpeedSize,

	[Parameter(mandatory=$False)]
    [ValidateSet("One","Kilo","Mega","Giga","Tera","Byte","KiloByte","MegaByte","GigaByte","TeraByte","Bit","KiloBit","MegaBit","GigaBit","TeraBit")]
    [string]$VolumeSize,
    
    [Parameter(mandatory=$False)]
    [alias('dm')]
    [ValidateSet("Auto","All")]
    [string]$DecimalMode,
    
    [Parameter(mandatory=$False)]
    [alias('w')]
    [switch]$Warning,
    
    [Parameter(mandatory=$False)]
    [string]$ValueLookup
    )
    
    $StandardUnits = @("BytesBandwidth","BytesMemory","BytesDisk","Temperature","Percent","TimeResponse","TimeSeconds","Custom","Count","CPU","BytesFile","SpeedDisk","SpeedNet","TimeHours")
    $LimitMode = $false
    
    $Result  = "  <result>`n"
    $Result += "    <channel>$Channel</channel>`n"
    $Result += "    <value>$Value</value>`n"
    
    if ($StandardUnits -contains $Unit) {
        $Result += "    <unit>$Unit</unit>`n"
    } elseif ($Unit) {
        $Result += "    <unit>custom</unit>`n"
        $Result += "    <customunit>$Unit</customunit>`n"
    }
    
	if (!( ($Value -is [int]) -or ($Value -is [int64]) )) { $Result += "    <float>1</float>`n" }
    if ($Mode)        { $Result += "    <mode>$Mode</mode>`n" }
    if ($MaxWarn)     { $Result += "    <limitmaxwarning>$MaxWarn</limitmaxwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitminwarning>$MinWarn</limitminwarning>`n"; $LimitMode = $true }
    if ($MaxError)    { $Result += "    <limitmaxerror>$MaxError</limitmaxerror>`n"; $LimitMode = $true }
    if ($WarnMsg)     { $Result += "    <limitwarningmsg>$WarnMsg</limitwarningmsg>`n"; $LimitMode = $true }
    if ($ErrorMsg)    { $Result += "    <limiterrormsg>$ErrorMsg</limiterrormsg>`n"; $LimitMode = $true }
    if ($LimitMode)   { $Result += "    <limitmode>1</limitmode>`n" }
    if ($SpeedSize)   { $Result += "    <speedsize>$SpeedSize</speedsize>`n" }
    if ($VolumeSize)  { $Result += "    <volumesize>$VolumeSize</volumesize>`n" }
    if ($DecimalMode) { $Result += "    <decimalmode>$DecimalMode</decimalmode>`n" }
    if ($Warning)     { $Result += "    <warning>1</warning>`n" }
    if ($ValueLookup) { $Result += "    <ValueLookup>$ValueLookup</ValueLookup>`n" }
    
    if (!($ShowChart)) { $Result += "    <showchart>0</showchart>`n" }
    
    $Result += "  </result>`n"
    
    return $Result
}


###############################################################################
###############################################################################
# hypervisor connection/data collection

if (!$TargetDevice) {
	Set-PrtgError "Ensure sensor has 'Set placeholders as environment values' enabled."
} 

if (!$HostingServers) {
	$DesktopData = @(Get-BrokerDesktop -AdminAddress $TargetDevice)
} else {
	$DesktopData = @()
	
	foreach ($HostingServer in $HostingServers) {
		$DesktopData += @(Get-BrokerDesktop -AdminAddress $TargetDevice) |
			Where-Object { $_.HostingServerName -eq $HostingServer }
	}
}


###############################################################################
###############################################################################
# creating return object


$DesktopMetrics = "" | Select-Object Total,InMaintenanceMode,IsAssigned,NotAssigned,Unregistered,PoweredOn,PoweredOff,Disconnected,InUse

$DesktopMetrics.Total = 			$DesktopData.Count
$DesktopMetrics.InMaintenanceMode = @($DesktopData | ? { $_.InMaintenanceMode -eq $true }).Count
$DesktopMetrics.IsAssigned = 		@($DesktopData | ? { $_.IsAssigned -eq $true }).Count
$DesktopMetrics.NotAssigned = 		@($DesktopData | ? { $_.IsAssigned -eq $false }).Count
$DesktopMetrics.PoweredOn = 		@($DesktopData | ? { $_.PowerState -eq "On" }).Count
$DesktopMetrics.PoweredOff = 		@($DesktopData | ? { $_.PowerState -eq "Off" }).Count
$DesktopMetrics.Disconnected = 		@($DesktopData | ? { $_.SummaryState -eq "Disconnected" }).Count
$DesktopMetrics.InUse =				@($DesktopData | ? { $_.SummaryState -eq "InUse" }).Count
$DesktopMetrics.Unregistered = 		@($DesktopData | ? { $_.SummaryState -eq "Unregistered" }).Count


###############################################################################
###############################################################################
# THIS REALLY NEEDS TO BE UPDATED
# returning data for prtg


$XMLOutput = @"
<prtg>
"@

foreach ($prop in $DesktopMetrics.psobject.properties) {
	$channelname = $prop.name	
	$channelvalue = $prop.value

	$XMLOutput += @"

  <result>
    <channel>$channelname</channel>
    <value>$channelvalue</value>
    <Unit>Count</Unit>$channellimit
  </result>
"@
}



$XMLOutput += @"

  <text>OK</text>
</prtg>
"@

Write-Host $XMLOutput
