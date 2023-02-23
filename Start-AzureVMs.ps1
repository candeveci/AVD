<#
.SYNOPSIS
  The script can be used to start Azure VMs, for example when they need to update using Update Management with Automation Account. 
.DESCRIPTION
The script does the following:
* Starting the Azure VM when status is not "running"

Required Powershell modules:
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'

.PARAMETER SubscriptionId
    Subscription ID of where the Session Hosts are hosted
.PARAMETER SkipTag
    The name of the tag, which will exclude the VM from scaling. The default value is SkipAutoShutdown
.PARAMETER TimeDifference
    The time diference with UTC (e.g. +2:00)                    
.NOTES
  Version:        1.0
  Author:         Siebren Mossel
  Creation Date:  15/02/2023
  Purpose/Change: Initial script development
#>

param(
	[Parameter(mandatory = $true)]
	[string]$SubscriptionId,
	
	[Parameter(mandatory = $true)]
	[string]$ResourceGroupName,

    [Parameter(mandatory = $false)]
	[string]$SkipTag = "SkipStart",
    
    [Parameter(mandatory = $false)]
	[string]$TimeDifference = "+2:00"

)

[array]$RequiredModules = @(
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
)


[string[]]$TimeDiffHrsMin = "$($TimeDifference):0".Split(':')
#Functions

function Write-Log {
    # Note: this is required to support param such as ErrorAction
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$Err,

        [switch]$Warn
    )

    [string]$MessageTimeStamp = (Get-LocalDateTime).ToString('yyyy-MM-dd HH:mm:ss')
    $Message = "[$($MyInvocation.ScriptLineNumber)] $Message"
    [string]$WriteMessage = "$MessageTimeStamp $Message"

    if ($Err) {
        Write-Error $WriteMessage
        $Message = "ERROR: $Message"
    }
    elseif ($Warn) {
        Write-Warning $WriteMessage
        $Message = "WARN: $Message"
    }
    else {
        Write-Output $WriteMessage
    }

}

	# Function to return local time converted from UTC
function Get-LocalDateTime {
    return (Get-Date).ToUniversalTime().AddHours($TimeDiffHrsMin[0]).AddMinutes($TimeDiffHrsMin[1])
}

# Authenticating

try
{


    Write-log "Logging in to Azure..."
    $connecting = Connect-AzAccount -identity 

}
catch {
        Write-Error -Message $_.Exception
        Write-log "Unable to sign in, terminating script.."
        throw $_.Exception

}

#starting script
Write-Log 'Starting script for starting Azure VMs'


Write-Log 'Checking if required modules are installed in the Automation Account'
# Checking if required modules are present 
foreach ($ModuleName in $RequiredModules) {
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-Log "$($ModuleName) is present"
    } 
    else {
        Write-Log "$($ModuleName) is not present. Make sure to import the required modules in the Automation Account. Check the desription"
        #throw
    }
}

#Getting Azure VMs
Write-Log 'Getting all Azure VMs'
$AzureVMs = Get-AzVM -ResourceGroupName $ResourceGroupName
if (!$AzureVMs) {
    Write-Log "There are no Azure Vms in the ResourceGroup $ResourceGroupName."
    Write-Log 'End'
    return
}

#Evaluate eacht session hosts
foreach ($vm in $AzureVMs) {
    $vmName = $vm.Name
    #Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Status).Statuses[1].Code
    #Gathering information about tags
    $VMSkip = (Get-AzVm -ResourceGroupName $ResourceGroupName -Name $vmName).Tags.Keys

    # If VM is Deallocated we can skip    
    if($VMStatus -eq 'PowerState/deallocated'){
        Write-Log "$vmName is in a deallocated state, starting VM"
        $StartVM = Start-AzVM -Name $vmName -ResourceGroupName $ResourceGroupName
        Write-Log "Starting $vmName ended with status: $($StartVM.Status)"
    }
    # If VM has skiptag we can skip
    if ($VMSkip -contains $SkipTag) {
        Write-Log "VM $vmName contains the skip tag and will be ignored"
        continue
    }
    # If VM is stopped, deallocate VM
    if ($VMStatus -eq 'PowerState/stopped'){
        Write-Log "$vmName is stopped, starting VM"
        $StartVM = Start-AzVM -Name $vmName -ResourceGroupName $ResourceGroupName
        Write-Log "Starting $vmName ended with status: $($StartVM.Status)"
    }

    #for running vms
    if($VMStatus -eq 'PowerState/running'){
        Write-Log "$vmName is already running"
        continue
    }  
}
Write-Log 'All VMs are processed'
Write-Log 'Disconnecting AZ Session'
#disconnect
$DisconnectInfo = Disconnect-AzAccount

Write-Log 'End'
