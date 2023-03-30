<#
.SYNOPSIS
    This script installs the applications and tools needed for the Project implementation for Azure Virtual Desktop.
.DESCRIPTION
    This script installs the applications and tools needed for the Project implementation for Azure Virtual Desktop.
.EXAMPLE
    PS C:\> .\InstallProjectVMApplications.ps1"
.INPUTS
    None
.OUTPUTS
    None
.NOTES
    Created by Siebren Mossel (InSpark)
#>

#download directory
$path = "C:\Temp"
If(!(test-path $path))
{
      New-Item -ItemType Directory -Force -Path $path
}

Set-Location $path

#Install NuGet
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

#Install NuGet
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

#install module
Install-Module Az.DesktopVirtualization -Force
Install-Module -Name PowerShellGet -Force

Add-WindowsCapability -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -Online
Add-WindowsCapability -Name "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -Online

#Download files and extract AzFilesHybrid files
$client = new-object System.Net.WebClient
$client.DownloadFileTaskAsync("https://github.com/Azure-Samples/azure-files-samples/releases/download/v0.2.5/AzFilesHybrid.zip","C:\Temp\AzFilesHybrid.zip")
$client.DownloadFileTaskAsync("https://download.microsoft.com/download/8/d/d/8ddd685d-7d55-42e2-9555-6ab365050734/Administrative%20Templates%20(.admx)%20for%20Windows%2011%20September%202022%20Update.msi","C:\Temp\Windows11ADMX.msi")
$client.DownloadFileTaskAsync("https://aka.ms/fslogix_download","C:\Temp\FSLogix.zip")
$client.DownloadFileTaskAsync("https://download.microsoft.com/download/2/E/E/2EEEC938-C014-419D-BB4B-D184871450F1/admintemplates_x64_5391-1000_en-us.exe","C:\Temp\admintemplates_x64_5391-1000_en-us.exe")
$client.DownloadFileTaskAsync("https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/misc/ReaderADMTemplate.zip","C:\Temp\ReaderADMTemplate.zip")

#Extract AzFilesHybrid files
Expand-Archive -Path .\AzFilesHybrid.zip .\

#Rename PolicyDefinitions to PolicyDefitionsOld and create new folder
Rename-Item C:\Windows\PolicyDefinitions C:\Windows\PolicyDefinitionsOld
New-Item -Path 'C:\Windows\PolicyDefinitions' -ItemType Directory

#Install Windows 11 ADMX Files and copy to PolicyDefitions
msiexec /i C:\Temp\Windows11ADMX.msi /qn
Robocopy /S 'C:\Program Files (x86)\Microsoft Group Policy\Windows 11 September 2022 Update (22H2)\PolicyDefinitions' C:\Windows\PolicyDefinitions

#FSLogix ADMX
Expand-Archive -Path C:\Temp\FSLogix.zip C:\Temp\FSLogix
Copy-Item C:\Temp\FSLogix\fslogix.admx C:\Windows\PolicyDefinitions
Copy-Item C:\Temp\FSLogix\fslogix.adml C:\Windows\PolicyDefinitions\en-us

#Office 365 ADMX
C:\Temp\admintemplates_x64_5391-1000_en-us.exe /extract:C:\Temp\ADMX /quiet
Robocopy /S C:\Temp\ADMX\admx C:\Windows\PolicyDefinitions

#Adobe Reader ADMX
Expand-Archive -Path C:\Temp\ReaderADMTemplate.zip C:\Temp\ADMX\AdobeReaderDC
Robocopy /S 'C:\Temp\ADMX\AdobeReaderDC' C:\Windows\PolicyDefinitions

#Use Local ADMX instead of central store
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Group Policy" /v EnableLocalStoreOverride /t REG_DWORD /d 1 /f

#Copy Module to Path
.\CopyToPSPath.ps1

