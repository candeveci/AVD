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

#Download and extract AzFilesHybrid files
$client2 = new-object System.Net.WebClient
$client2.DownloadFileTaskAsync("https://github.com/Azure-Samples/azure-files-samples/releases/download/v0.2.5/AzFilesHybrid.zip","C:\temp\AzFilesHybrid.zip")
Expand-Archive -Path .\AzFilesHybrid.zip .\

#Copy Module to Path
.\CopyToPSPath.ps1

