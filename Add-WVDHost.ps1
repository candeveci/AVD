<#  
.SYNOPSIS  
    Adds a WVD Session Host to an existing WVD Hostpool.
.DESCRIPTION  
    This scripts adds a WVD Session Host to an existing WVD Hostpool by performing the following action:
    - Download the WVD agent
    - Download the WVD Boot Loader
    - Install the WVD Agent
    - Install the WVD Boot Loader
.NOTES  
    File Name  : add-wvdHost.ps1
    Author     : InSpark
    Version    : v1.0.0
.EXAMPLE
    .\add-WVDHost.ps1
.DISCLAIMER
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

param(
	[string] $LogDir="$env:windir\system32\logfiles",
	[string] $wvdRegistrationKey
)

#Set Variables
$RootFolder = "C:\WVDInstall\"
$BootLoaderInstaller = $RootFolder+"Microsoft.RDInfra.RDAgentBootLoader.msi"
$AgentInstaller = $RootFolder+"Microsoft.RDInfra.RDAgent.msi"


function LogWriter($message)
{
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}

# Define logfile
$LogFile=$LogDir+"\WVD.addWVDHost.log"

#Create Folder structure
if (!(Test-Path -Path $RootFolder)){New-Item -Path $RootFolder -ItemType Directory}

#Download all source file async and wait for completion
LogWriter("Download WVD Agent & bootloader")
$files = @(
    @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"; path = $AgentInstaller}
    @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"; path = $BootLoaderInstaller}
)
$workers = foreach ($f in $files)
{ 
    $wc = New-Object System.Net.WebClient
    Write-Output $wc.DownloadFileTaskAsync($f.url, $f.path)
}
$workers.Result

LogWriter("Installing WVD boot loader - current path is ${PSScriptRoot}")
Start-Process -wait -FilePath $BootLoaderInstaller -ArgumentList "/q"
LogWriter("Installing WVD agent")
Start-Process -wait -FilePath $AgentInstaller -ArgumentList "/q RegistrationToken=${wvdRegistrationKey}"

#LogWriter("Finally restarting session host")
#Restart-Computer -Force
