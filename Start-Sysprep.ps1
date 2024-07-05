# This powershell script is used for sysprepping an image

param(
	[string] $LogDir="$env:windir\system32\logfiles"
)
function LogWriter($message)
{
	write-host($message)
	if ([System.IO.Directory]::Exists($LogDir)) {write-output($message) | Out-File $LogFile -Append}
}

# Define logfile
$LogFile=$LogDir+"\AVD.Sysprep.log"

# Main
LogWriter("Starting sysprepping")


	LogWriter("Removing existing Remote Desktop Agent Boot Loader")
	$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Agent Boot Loader"}
	if ($app -ne $null) {$app.uninstall()}
	LogWriter("Removing existing Remote Desktop Services Infrastructure Agent")
	$app=Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -match "Remote Desktop Services Infrastructure Agent"}
	if ($app -ne $null) {$app.uninstall()}
	Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\RDMonitoringAgent" -Force -ErrorAction Ignore

	LogWriter("Cleaning up reliability messages")
	$key="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Reliability"
	Remove-ItemProperty -Path $key -Name "DirtyShutdown" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "DirtyShutdownTime" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "LastAliveStamp" -ErrorAction Ignore
	Remove-ItemProperty -Path $key -Name "TimeStampInterval" -ErrorAction Ignore
	
	LogWriter("Removing pending AppXPackages")
	LogWriter(Get-AppxPackage -AllUsers | where{$_.NonRemovable -ne $true -and $_.PackageUserInformation -match "pending removal"}|ft)
	Get-AppxPackage -AllUsers | where{$_.NonRemovable -ne $true -and $_.PackageUserInformation -match "pending removal"}| Remove-AppxPackage -AllUsers
	
	LogWriter("Removing assignments to language packs - AppXPackages")
	$Packages = Get-AppxPackage -AllUsers | ? {$_.packagefullname.contains('Microsoft.LanguageExperiencePack')}
	foreach($package in $packages){
		write-host("Removing package: "+$package.packagefullname)
		Remove-AppxPackage -AllUsers -Package $package.packagefullname
	}
	Get-AppxPackage | where{$_.Name -match "winget"} | Remove-AppxPackage
 	#Remove Winget and Notepad, otherwise sysprep fails
	Get-AppxPackage -Name Notepad* | Remove-AppxPackage
	Get-AppxPackage -Name Microsoft.Winget.Source | Remove-AppxPackage
	
	LogWriter("Saving time zone info for re-deploy")
	$timeZone=(Get-TimeZone).Id
	LogWriter("Current time zone is: "+$timeZone)
	New-Item -Path "HKLM:\SOFTWARE" -Name "InSpark" -Force
	New-Item -Path "HKLM:\SOFTWARE\InSpark" -Name "AVD.Runtime" -force	
	New-ItemProperty -Path "HKLM:\SOFTWARE\InSpark\AVD.Runtime" -Name "TimeZone.Origin" -Value $timeZone -force
	
	LogWriter("Starting sysprep to generalize session host")
	Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep" -ArgumentList "/generalize /oobe /shutdown"
