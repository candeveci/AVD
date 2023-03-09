<#
    See readme.md for more information.
    https://dev.azure.com/weareinspark/Managed%20Services%20-%20Infra/_git/Intern.Tooling?path=/Compute/Virtual-Machine/AutoShutdown
#>

param(
    [parameter(Mandatory = $True)]
    [String] $AzureSubscriptions,

    [parameter(Mandatory = $false)]
    [String] $AutoShutdownTagName = 'InSpark_AutoShutdownSchedule',

    [parameter(Mandatory = $false)]
    [String] $TimeZone = "W. Europe Standard Time",
    
    [parameter(Mandatory = $false)]
    [bool] $VerboseOutput = $False,

    [parameter(Mandatory = $false)]
    [bool]$Simulate = $true,

    [parameter(Mandatory = $false)]
    [bool]$ManagedIdentity = $false,

    [String]$VERSION = '4.06'
)

# Functions #
function Invoke-AzResourceGraphRestQuery {
    param(
        [parameter(Mandatory = $false)]
        [String] $Uri = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01',
        [parameter(Mandatory = $true)]
        [String] $Query,
        [parameter(Mandatory = $true)]
        [String] $Authorization
    )
    $Data = @()
    $RecordCount = 0
    $RequestBody = @{
        Uri = $Uri
        Method = 'POST'
        Header = @{
            Accept = 'application/json'
            'Content-Type' = 'application/json'
            Authorization = $('Bearer {0}' -f $Authorization)
        }
    }
    $Body = @{
        query = $Query
    } | ConvertTo-Json -Compress
    $Response = (Invoke-WebRequest -UseBasicParsing @RequestBody -body $Body).Content | ConvertFrom-Json
    $RecordCount = $Response.totalRecords
    $Data = $Response.data

    if ($RecordCount -gt 1000)
    {
        $RecordCount = $RecordCount - 1000
        $End = $false
        $Stop = $false
        do
        {
            $Body = @{
                query = $Query
                options = @{'$skipToken' = $Response.'$skipToken'}
            } | ConvertTo-Json -Compress
            $Response = (Invoke-WebRequest -UseBasicParsing @RequestBody -body $Body).Content | ConvertFrom-Json
            $RecordCount = $RecordCount - $Response.count
            $Data += $Response.data
            if ($End) {$Stop = $true}
            if ($RecordCount -lt 1000) { $End = $true }
        }
        until ($Stop) 
    }
    
    return $Data
}

function Write-TimeRangeMSG {
    param(
        [parameter(Mandatory = $true)]
        [String] $Action,
        [parameter(Mandatory = $true)]
        [String] $Resourceid,
        [parameter(Mandatory = $true)]
        [String] $T1,
        [parameter(Mandatory = $true)]
        [String] $T2
    )
    $Stop = (New-TimeSpan -Minutes $T1) | ForEach-Object { Get-Date -Format "HH:mm" -Hour $_.Hours -Minute $_.Minutes }
    $Start = (New-TimeSpan -Minutes $T2) | ForEach-Object { Get-Date -Format "HH:mm" -Hour $_.Hours -Minute $_.Minutes }
    return $("Type: TimeRange | Action: {0} | Range: {1}->{2} | Resourceid: {3}" -f $Action, $Start, $Stop, $Resourceid)
}

function Find-NthDay {
    param(
        [parameter(Mandatory = $true)]
        [string] $Day,

        [parameter(Mandatory = $true)]
        [int] $Ordinal
    )

    $FirstDay = Get-Date -Month $Current.Month -day 1
    do 
    {
        $FirstDay = $FirstDay.AddDays(1)
    } 
    until ($FirstDay.ToString("dddd") -eq $Day)

    if ($Ordinal -gt 1)
    {
        $Ordinal = ($Ordinal - 1) * 7
        $NthDay = $FirstDay.AddDays($Ordinal)
        return $NthDay
    }
    return $FirstDay
}

function Get-NthAction {
    param(
        [parameter(Mandatory = $true)]
        [object] $VM,

        [parameter(Mandatory = $true)]
        [object] $NthObject,

        [parameter(Mandatory = $true)]
        [string] $Type,

        [parameter(Mandatory = $true)]
        [string] $Action
    )

    $Output = @{
        MSG = ''
        TimeRange = ''
        Action = ''
    }
    if ($NthObject -match '|')
    {
        $Split = ($NthObject).split('|')
        $Range = ($Split)[0].split('_')
    }
    else 
    {
        $Range = ($NthObject).split('_')
    }

    $Ordinal = [int] $Range[0]
    $NthDay = (Find-NthDay -Ordinal $Ordinal -Day $Range[1]).ToString("dd")

    if ($NthObject -match '|' -and $NthDay -eq $Current.PreviousDay)
    {
        $Output.MSG += $("Type: {3} | {3}: {1} | Action: {2} | Resourceid: {0}" -f $VM.id, $NthObject, $('{0}_NextDay' -f $Type), 'Deallocation')
        $Output.TimeRange = $Split[1]
        return $Output
    }
    if ($NthDay -eq $Current.Day)
    {
        $Output.MSG += $("Type: {3} | {3}: {1} | Action: {2} | Resourceid: {0}" -f $VM.id, $NthObject, $Type, $Action)
        $Output.Action = $Action
        return $Output
    }
    else 
    {
        return $VM
    }
}

function Get-StartOrShutdownAction 
{
    param(
        [parameter(Mandatory = $true)]
        [object] $VM
    )
    $TempStore = @{
        StartVMs = @()
        DeallocateVMs = @()
        MSG = @()
    }

    ## Skip
    $SkipNth = ($VM.Skip).split(',')
    if ($SkipNth.count -gt 0 -and $SkipNth -ne '')
    {
        foreach ($Entry in $SkipNth)
        { 
            $NthAction = Get-NthAction -VM $VM -NthObject $Entry -Type 'SkipDayNth' -Action 'Skip'
            if (-not [String]::IsNullOrEmpty($NthAction.TimeRange)) 
            {
                $VM.TimeRange = $NthAction.TimeRange
            }
            if ($NthAction.Action -eq 'Skip')
            {
                $TempStore.MSG = $NthAction.MSG
                return $TempStore
            }
        }
    }

    if ($Current.WeekDay -in ($VM.skip).split(','))
    {
        $TempStore.MSG = $("Type: SkipDay | Action: Skip | Resourceid: {0}" -f $VM.id)
        return $TempStore
    }
    if ($Current.MonthDay -in ($VM.skip).split(','))
    {
       $TempStore.MSG = $("Type: SkipDate | Action: Skip | Resourceid: {0}" -f $VM.id)
        return $TempStore
    }

    ## StartDay
    $StartDayNth = ($VM.startday).split(',')
    if ($StartDayNth.count -gt 0 -and $StartDayNth -ne '')
    {
        foreach ($Entry in $StartDayNth)
        { 
            $NthAction = Get-NthAction -VM $VM -NthObject $Entry -Type 'StartDayNth' -Action 'Start'
            if (-not [String]::IsNullOrEmpty($NthAction.TimeRange)) 
            {
                $VM.TimeRange = $NthAction.TimeRange
            }
            if ($NthAction.Action -eq 'Start')
            {
                $TempStore.MSG = $NthAction.MSG
                $TempStore.StartVMs += $VM.id 
                return $TempStore
            }
        }
    }


    if ($Current.WeekDay -in ($VM.startday).split(',')) 
    {
        $TempStore.MSG = $("Type: StartDay | WeekDay: {1} | Action: Start | Resourceid: {0}" -f $VM.id,$Current.WeekDay)
        $TempStore.DeallocateVMs += $VM.id
        return $TempStore
    }
    if ($Current.MonthDay -in ($VM.startday).split(','))
    {
        $TempStore.MSG = $("Type: StartDate | Date: {1} | Action: Start | Resourceid: {0}" -f $VM.id,($Current.Date).ToString("dd MMMM yyyy"))
        $TempStore.DeallocateVMs += $VM.id
        return $TempStore
    }

    ## Day
    $DayNth = ($VM.day).split(',')
    if ($DayNth.count -gt 0 -and $DayNth -ne '')
    {
        foreach ($Entry in $DayNth)
        { 
            $NthAction = Get-NthAction -VM $VM -NthObject $Entry -Type 'DayNth' -Action 'Deallocation'
            if (-not [String]::IsNullOrEmpty($NthAction.TimeRange)) 
            {
                $VM.TimeRange = $NthAction.TimeRange
            }
            if ($NthAction.Action -eq 'Deallocation')
            {
                $TempStore.MSG = $NthAction.MSG
                $TempStore.DeallocateVMs += $VM.id 
                return $TempStore
            }
        }
    }

    if ($Current.WeekDay -in ($VM.day).split(',')) 
    {
        $TempStore.MSG = $("Type: Day | WeekDay: {1} | Action: Deallocation | Resourceid: {0}" -f $VM.id,$Current.WeekDay)
        $TempStore.DeallocateVMs += $VM.id
        return $TempStore
    }
    if ($Current.MonthDay -in ($VM.day).split(','))
    {
        $TempStore.MSG = $("Type: Date | Date: {1} | Action: Deallocation | Resourceid: {0}" -f $VM.id,($Current.Date).ToString("dd MMMM yyyy"))
        $TempStore.DeallocateVMs += $VM.id
        return $TempStore
    }

    # Place TimeRanges in a Map to be used later.
    $VMrange = ($VM.TimeRange).split(',')
    $Map = @{
        SkipResource = $false
        TimeRanges = @()
        Start = $false
    }
    foreach ($timeRange in $VMrange)
    {
        if ($timeRange -match '->') {
            try {
                $Stop = ($timeRange).split('->')[0].split(':').Trim()
                $StopMin = [convert]::ToInt32($Stop[0]) * 60 + [convert]::ToInt32($Stop[1]) 
            } catch {}

            try {
                $Start = ($timeRange).split('->')[2].split(':').Trim()
                $StartMin = [convert]::ToInt32($Start[0]) * 60 + [convert]::ToInt32($Start[1]) 
            } catch {}

            if ($null -ne $StopMin -and $null -ne $StartMin) 
            {
                $Map.timeranges += @($StopMin)
                $Map.timeranges += @($StartMin)
                $Map.Start = $true
            }
            else 
            {
                $Map.SkipResource = $true
                Write-Warning ('Invalid TimeRange Detected! | Skipping Resource | Resourceid: {0} | TimeRange: {1}' -f $VM.id, $timeRange)
            }
        }
        else
        {
            try {
                $Stop = ($timeRange).split(':')
                $StopMin = [convert]::ToInt32($Stop[0]) * 60 + [convert]::ToInt32($Stop[1])
            } catch {}

            if ($null -ne $StopMin) 
            {
                $Map.timeranges += @($StopMin)
                $Map.timeranges += @(1440)
            }
            else 
            {
                $Map.SkipResource = $true
                Write-Warning ('Invalid TimeRange Detected! | Skipping Resource | Resourceid: {0} | TimeRange: {1}' -f $VM.id, $timeRange)
            }
        }  
    }

    # Determine TimeRange to use.
    if (!$Map.SkipResource)
    {
        Write-Verbose $current.TimeMinutes
        write-verbose $($Map | ConvertTo-Json)
        $MapCount = ($Map.timeranges).Count
        if ($MapCount -eq 2)
        {
            if ($Map.timeranges[0] -lt $current.TimeMinutes -and $Map.timeranges[1] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Deallocation' -T1 $Map.timeranges[1] -T2 $Map.timeranges[0] -Resourceid $VM.id
                $TempStore.DeallocateVMs += $VM.id
                return $TempStore
            }
            if ($Map.Start -eq $true)
            {
                if ($Map.timeranges[1] -lt $current.TimeMinutes -and $Map.timeranges[0] -gt $current.TimeMinutes) 
                {
                    $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[0] -T2 $Map.timeranges[1] -Resourceid $VM.id
                    $TempStore.StartVMs += $VM.id
                    return $TempStore
                }
            }
        }
        if ($MapCount -eq 4)
        {
            if ($Map.timeranges[0] -lt $current.TimeMinutes -and $Map.timeranges[2] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[2] -T2 $Map.timeranges[0] -Resourceid $VM.id
                $TempStore.StartVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[2] -lt $current.TimeMinutes -and $Map.timeranges[3] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Deallocation' -T1 $Map.timeranges[3] -T2 $Map.timeranges[2] -Resourceid $VM.id
                $TempStore.DeallocateVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[3] -lt $current.TimeMinutes -and $Map.timeranges[0] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[3] -T2 $Map.timeranges[0] -Resourceid $VM.id
                $TempStore.StartVMs += $VM.id
                return $TempStore
            }
        }
        if ($MapCount -eq 6)
        {
            if ($Map.timeranges[0] -lt $current.TimeMinutes -and $Map.timeranges[2] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[2] -T2 $Map.timeranges[0] -Resourceid $VM.id
                $TempStore.StartVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[2] -lt $current.TimeMinutes -and $Map.timeranges[3] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Deallocation' -T1 $Map.timeranges[3] -T2 $Map.timeranges[2] -Resourceid $VM.id
                $TempStore.DeallocateVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[3] -lt $current.TimeMinutes -and $Map.timeranges[4] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[3] -T2 $Map.timeranges[4] -Resourceid $VM.id
                $TempStore.StartVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[4] -lt $current.TimeMinutes -and $Map.timeranges[5] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Deallocation' -T1 $Map.timeranges[5] -T2 $Map.timeranges[4] -Resourceid $VM.id
                $TempStore.DeallocateVMs += $VM.id
                return $TempStore
            }
            if ($Map.timeranges[5] -lt $current.TimeMinutes -and $Map.timeranges[0] -gt $current.TimeMinutes) 
            {
                $TempStore.MSG = Write-TimeRangeMSG -Action 'Start' -T1 $Map.timeranges[0] -T2 $Map.timeranges[5] -Resourceid $VM.id
                $TempStore.StartVMs += $VM.id
                return $TempStore
            }
        }
        return $TempStore
    }
}
# Functions end #

# Main Start
Write-Output "Runbook started. Version: $VERSION"

# Connect to Azure
Disable-AzContextAutosave -Scope Process | Out-Null
if ($ManagedIdentity)
{
	Connect-AzAccount -Identity | Out-Null
}
else
{
    $Automation = Get-AutomationConnection -Name 'AzureRunAsConnection'
    Connect-AzAccount -ServicePrincipal -TenantId $Automation.TenantID -ApplicationId $Automation.ApplicationID -CertificateThumbprint $Automation.CertificateThumbprint | Out-Null
}

## Get AccessToken
$Authorization = $(Get-AzAccessToken).Token

## Get date formats used in script
$CurrentTime = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))
$Current = @{ 
    Time = $CurrentTime.ToString("HH:mm:ss")
    TimeMinutes = [int]$CurrentTime.ToString("HH") * 60 + [int]$CurrentTime.ToString("mm")
    WeekDay = $CurrentTime.ToString("dddd")
    PreviousDay = $CurrentTime.AddDays(-1).ToString("dd")
    Day = $CurrentTime.ToString("dd")
    Month = $CurrentTime.ToString("MM")
    MonthDay = $CurrentTime.ToString("ddMMMMyyyy")
    Date = $CurrentTime.ToUniversalTime()
}

if ($Simulate) {
    Write-Output "*** Running in SIMULATE mode. No power actions will be taken. ***"
} else {
    Write-Output "*** Running in LIVE mode. Schedules will be enforced. ***"
}

Write-Output "Current $TimeZone [$($current.Date.ToString("dddd, HH:mm, dd MMMM(MM) yyyy"))] will be checked against schedules"
Write-Output `r

# Execute
$AzureSubscriptions = (($AzureSubscriptions).Split(',') | ConvertTo-Json -Compress).replace('[','').replace(']','')
$Store = @{
    VMList = @()
    RGVMList = @()
    RGList = @()
    StartVMs = @()
    DeallocateVMs = @()
    FilteredVMList = @()
    StartVMsPowerState = @()
    DeallocateVMsPowerState = @()
}
## TimeRange Query Part
$TimeRangePart = @"
| extend
timerange1 = case(
    ASSC has 'Day:', 
    translate('[`" ]', '', tostring(split(split(split(ASSC, 'TimeRange:')[1], 'Day:')[0], ','))), 
    ''
),
timerange2 = case(
    ASSC has 'StartDay:', 
    translate('[`" ]', '', tostring(split(split(split(ASSC, 'TimeRange:')[1], 'StartDay:')[0], ','))), 
    ''
),
timerange3 = case(
    ASSC has 'Skip:', 
    translate('[`" ]', '', tostring(split(split(split(ASSC, 'TimeRange:')[1], 'Skip:')[0], ','))), 
    ''
),
timerange4 = case(
    ASSC has 'TimeRange:', 
    translate('[`" ]', '', tostring(split(ASSC, 'TimeRange:')[1])),
    ''
)
| extend
timerange = case(
    timerange1 != '',
    substring(timerange1, 0, (strlen(timerange1)-1)),
    timerange2 != '',
    substring(timerange2, 0, (strlen(timerange2)-1)),
    timerange3 != '',
    substring(timerange3, 0, (strlen(timerange3)-1)),
    timerange4 != '',
    timerange4,
    ''
)
"@

## Day Query Part
$DayPartQuery = @"
| extend
daypart1 = case(
    ASSC has 'StartDay:', 
    translate('[`" ]', '', tostring(split(split(split(ASSC, 'StartDay:')[0], 'Day:')[1], ','))),
    ''
),
daypart2 = case(
    ASSC has 'Skip:', 
    translate('[`" ]', '', tostring(split(split(split(ASSC, 'Skip:')[0], 'Day:')[1], ','))),
    ''
)
| extend
day = case(
    daypart1 != '',
    substring(daypart1, 0, (strlen(daypart1)-1)),
    daypart2 != '',
    substring(daypart2, 0, (strlen(daypart2)-1)),
    ''
)
"@

## StartDay + Skip Script Part
$StartSkipPartQuery = @"
| extend
startday = case(
    ASSC has 'StartDay:', 
    translate('[" ]', '', tostring(split(split(split(ASSC, 'StartDay:')[1], 'Skip:')[0], ','))),
    ''
),
skip = case(
    ASSC has 'Skip:', 
    translate('[`" ]', '', tostring(array_slice(split(split(ASSC, 'Skip:')[1], ','), 0, 1))),
    ''
)
"@

## Get ResourceGroups Tagged with AutoShutdownSchedule
if ($VerboseOutput) { Write-Output "[Processing]: Type: Gathering | Action: ResourceGroups" }
$QueryRG = @"
resourcecontainers
| where subscriptionId in ({0})
| extend ASSC = tags['{1}']
| where ASSC != ''
{2}
{3}
{4}
| extend
ASSC = translate('[`" ]', '', tostring(ASSC))
| project name, subscriptionId, {1} = ASSC, timerange, day, startday, skip
"@ -f $AzureSubscriptions, $AutoShutdownTagName, $TimeRangePart, $DayPartQuery, $StartSkipPartQuery 

if ($VerboseOutput) { Write-Output $QueryRG }
$Store.RGList = Invoke-AzResourceGraphRestQuery -Authorization $Authorization -Query $QueryRG
if ($VerboseOutput) { $Store.RGList }

## Get VMs in Resource Groups
foreach ($RG in $Store.RGList)
{
    if ($VerboseOutput) { Write-Output $("[Processing]: Type: Gathering | ResourceGroup: {0} | Action: VMs" -f $RG.Name) }
    $QueryRGVM = @"
resources
| where subscriptionId in ({0})
| extend resourceGroup = split(id,'/')[4]
| where resourceGroup == '{1}' and type == 'microsoft.compute/virtualmachines'
| extend ASSC = tags['{2}']
{8}
{9}
{10}
| extend
{2} = case(
    ASSC == '',
    translate('[`" ]', '', '{3}'),
    ASSC
),
timerange = case(
    ASSC == '',
    '{4}',
    timerange
),
day = case(
    ASSC == '',
    '{5}',
    day
),
skip = case(
    ASSC == '',
    '{6}',
    skip
),
startday = case(
    ASSC == '',
    '{7}',
    startday
)
| extend 
ASSC = translate('[`" ]', '', tostring(ASSC))
| project name, id, resourceGroup, subscriptionId, {2}, timerange, day, startday, skip
"@ -f $AzureSubscriptions, $RG.name, $AutoShutdownTagName, $RG.AutoShutdownSchedule, $RG.timerange, $RG.day, $RG.skip, $RG.startday, $TimeRangePart, $DayPartQuery, $StartSkipPartQuery
    
    if ($VerboseOutput) { Write-Output $QueryRGVM }
    $Store.RGVMList += Invoke-AzResourceGraphRestQuery -Authorization $Authorization -Query $QueryRGVM
    if ($VerboseOutput) { $Store.RGVMList }
}

## Get VMs in subscription Tagged with AutoShutdownSchedule
if ($VerboseOutput) { Write-Output "[Processing]: Type: Gathering | Action: VMs" }
$QueryVM = @"
resources
| where subscriptionId in ({0}) and type == 'microsoft.compute/virtualmachines'
| extend ASSC = tags['{1}']
| where ASSC != ''
{2}
{3}
{4}
| extend
ASSC = translate('[`" ]', '', tostring(ASSC))
| project name, id, resourceGroup, subscriptionId, {1} = ASSC, timerange, day, startday, skip
"@ -f $AzureSubscriptions, $AutoShutdownTagName, $TimeRangePart, $DayPartQuery, $StartSkipPartQuery 

if ($VerboseOutput) { Write-Output $QueryVM }
$Store.VMList += Invoke-AzResourceGraphRestQuery -Authorization $Authorization -Query $QueryVM
if ($VerboseOutput) { $Store.VMList }

# Combine Query Results
if ($VerboseOutput) { Write-Output "[Processing]: Type: Merging | Action: VMs" }
if ($Store.RGVMList.Count -gt 0)
{
    foreach ($VM in $Store.RGVMList)
    {
        if ($VM.id -in $Store.VMList.id)
        {
            $VM_override = $Store.VMList | Where-Object id -eq $VM.id
            $Store.FilteredVMList += $VM_override
        }
        else 
        {
            $Store.FilteredVMList += $VM
        }
    }
}
else 
{
    $Store.FilteredVMList += $Store.VMList
}
if ($VerboseOutput) {
    Write-Output 'RGVMList:'
    $Store.RGVMList
    Write-Output 'VMList:'
    $Store.VMList
    Write-Output 'FilteredVMList:'
    $Store.FilteredVMList
}

# Match Schedule
Write-Output "[Processing]: Type: Matching | Matched Items:"
foreach ($VM in $Store.FilteredVMList)
{
    $Result = Get-StartOrShutdownAction -VM $VM
    Write-Output $Result.MSG
    if (-not [String]::IsNullOrEmpty($Result.DeallocateVMs)) { $Store.DeallocateVMs += $Result.DeallocateVMs }
    if (-not [String]::IsNullOrEmpty($Result.StartVMs)) { $Store.StartVMs += $Result.StartVMs }
}
Write-Output `r 
if ($VerboseOutput) { 
    Write-Output $Store.DeallocateVMs
    Write-Output $Store.StartVMs
}

## Get PowerState Query
$Query = "
resources
| where type == 'microsoft.compute/virtualmachines' and id in ({0})
| extend 
powerstate = split(todynamic(properties).extended.instanceView.powerState.code,'/')[1]
| project name, id, resourceGroup, subscriptionId, powerstate
"

# Enforce Deallocated PowerState
if ($Store.DeallocateVMs.Count -gt 0)
{
    Write-Output $("[Processing]: Type: Deallocation | Actions to Preform: {0} | Preformed Actions:" -f $Store.DeallocateVMs.Count)
    $DeallocateVMs = ($Store.DeallocateVMs | ConvertTo-Json -Compress).replace('[','').replace(']','')
    $Store.DeallocateVMsPowerState = Invoke-AzResourceGraphRestQuery -Authorization $Authorization -Query $($Query -f $DeallocateVMs)
    foreach ($VM in $Store.DeallocateVMsPowerState)
    {
        if ($VM.powerstate -eq 'running' -or $VM.powerstate -eq 'stopped')
        {
            if($Simulate)
            {
                Write-Output ("Type: Deallocation | Action: SIMULATION | Resourceid: {0}" -f $VM.id)
            }
            else 
            {
                Set-AzContext -Subscription $VM.subscriptionId | Out-Null
                Write-Output ("Type: Deallocation | Action: Deallocation | Resourceid: {0}" -f $VM.id)
                Stop-AzVM -Name $VM.name -ResourceGroupName $VM.resourceGroup -Force | Out-Null
            }
        }
        else 
        {
            Write-Output  $("Type: Deallocation | Action: None | Reason: AlreadyDeallocated | Resourceid: {0}" -f $VM.id)
        }
    }
    Write-Output `r
}

# Enforce Running PowerState
if ($Store.StartVMs.Count -gt 0)
{
    Write-Output $("[Processing]: Type: Start | Actions to Preform: {0} | Preformed Actions:" -f $Store.StartVMs.Count)
    $StartVMs = ($Store.StartVMs | ConvertTo-Json -Compress).replace('[','').replace(']','')
    $Store.StartVMsPowerState = Invoke-AzResourceGraphRestQuery -Authorization $Authorization -Query $($Query -f $StartVMs)
    foreach ($VM in $Store.StartVMsPowerState)
    {
        if ($VM.powerstate -eq 'deallocated' -or $VM.powerstate -eq 'stopped')
        {
            if($Simulate)
            {
                Write-Output ("Type: Start | Action: SIMULATION | Resourceid: {0}" -f $VM.id)
            }
            else 
            {
                Set-AzContext -Subscription $VM.subscriptionId | Out-Null
                Write-Output ("Type: Start | Action: Start | Resourceid: {0}" -f $VM.id)
                Start-AzVM -Name $VM.name -ResourceGroupName $VM.resourceGroup | Out-Null
            }
        }
        else 
        {
            Write-Output  $("Type: Start | Action: None | Reason: AlreadyRunning | Resourceid: {0}" -f $VM.id)
        }
    }
}
