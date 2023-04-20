<#  
.SYNOPSIS  
    Adds an AVD Session Host to an existing AVD Host pool.
.DESCRIPTION  
    This scripts adds a AVD Session Host to an existing AVD Hostpool by performing the following action:
    - Download the WVD agent
    - Download the WVD Boot Loader
    - Install the WVD Agent
    - Install the WVD Boot Loader
.NOTES  
    File Name  : add-wvdHost.ps1
    Author     : InSpark
    Version    : v1.0.0
.EXAMPLE
    .\add-WVDHost.ps1 -avdRegistrationKey <yourRegistrationKey>
.DISCLAIMER
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

param(
    [string] $avdRegistrationKey,
    [string] $LogDir = "$env:windir\system32\logfiles",
    [bool] $isAzureADJoined = $false,
    [bool] $isIntuneManaged = $false	
)

#Set Variables
$RootFolder = "C:\AVDInstall\"
$BootLoaderInstaller = $RootFolder + "Microsoft.RDInfra.RDAgentBootLoader.msi"
$AgentInstaller = $RootFolder + "Microsoft.RDInfra.RDAgent.msi"


function LogWriter($message) {
    write-host($message)
    if ([System.IO.Directory]::Exists($LogDir)) { write-output($message) | Out-File $LogFile -Append }
}

# Define logfile
$LogFile = $LogDir + "\WVD.addAVDHost.log"

#Create Folder structure
if (!(Test-Path -Path $RootFolder)) { New-Item -Path $RootFolder -ItemType Directory }


if ($isAzureADJoined) {
    LogWriter("Azure ad join preview flag enabled")
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\AzureADJoin"
    if (Test-Path -Path $registryPath) {
        LogWriter("Setting reg key JoinAzureAd")
        New-ItemProperty -Path $registryPath -Name JoinAzureAD -PropertyType DWord -Value 0x01
    }
    else {
        LogWriter("Creating path for azure ad join registry keys: $registryPath")
        New-item -Path $registryPath -Force | Out-Null
        LogWriter("Setting reg key JoinAzureAD")
        New-ItemProperty -Path $registryPath -Name JoinAzureAD -PropertyType DWord -Value 0x01
    }
    if ($isIntuneManaged) {
        LogWriter("Setting reg key MDMEnrollmentId")
        New-ItemProperty -Path $registryPath -Name MDMEnrollmentId -PropertyType String -Value "0000000a-0000-0000-c000-000000000000"
    }
}

#Download all source file async and wait for completion
LogWriter("Download WVD Agent & bootloader")
$files = @(
    @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"; path = $AgentInstaller }
    @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"; path = $BootLoaderInstaller }
)
$workers = foreach ($f in $files) { 
    $wc = New-Object System.Net.WebClient
    Write-Output $wc.DownloadFileTaskAsync($f.url, $f.path)
}
$workers.Result

LogWriter("Installing AVD boot loader - current path is ${PSScriptRoot}")
Start-Process -wait -FilePath $BootLoaderInstaller -ArgumentList "/q"
LogWriter("Installing AVD agent")
Start-Process -wait -FilePath $AgentInstaller -ArgumentList "/q RegistrationToken=${avdRegistrationKey}"
