param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateBaseUrl,
    [string]$dnsIpAddress,
    [string]$netbiosName,
    [string]$domainSuffix,
    [string]$dcVM
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dnsIpAddress', $dnsIpAddress, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('netbiosName', $netbiosName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', $domainSuffix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dcVM', $dcVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "C:\Deployment", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "C:\Deployment\Logs", [System.EnvironmentVariableTarget]::Machine)

$Env:DeploymentDir = "C:\Deployment"
$Env:DeploymentLogsDir = "$Env:DeploymentDir\Logs"

New-Item -Path $Env:DeploymentDir -ItemType directory -Force
New-Item -Path $Env:DeploymentLogsDir -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\scripts" -ItemType directory -Force

Start-Transcript -Path $Env:DeploymentLogsDir\DCSetup.log

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateBaseUrl + "scripts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

Write-Header "Fetching Artifacts for SqlServerK8s"
Write-Host "Downloading scripts"
Invoke-WebRequest ($templateBaseUrl + "scripts/ConfigureDC.ps1") -OutFile $Env:DeploymentDir\scripts\ConfigureDC.ps1

# Configure Domain Controller
Write-Header "Installing and configuring Domain Controller"
.$Env:DeploymentDir\scripts\ConfigureDC.ps1

# Remove DNS Server from Domain Controller Nic
$dcNic = "$Env:dcVM-nic"
Write-Header "Removing DNS Server entry from $dcNic"
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $dcNic
$nic.DnsSettings.DnsServers.Clear()
$nic | Set-AzNetworkInterface | out-null

# Stop logging and Reboot Jumpbox
#Write-Header "Rebooting $Env:jumpboxVM"
#Stop-Transcript
#$logSuppress = Get-Content $Env:DeploymentLogsDir\EnvironmentSetup.log | Where { $_ -notmatch "Host Application: powershell.exe" }
#$logSuppress | Set-Content $Env:DeploymentLogsDir\EnvironmentSetup.log -Force
#Restart-Computer -Force

$publicIpAddress = "$Env:dcVM-ip"
Remove-AzPublicIpAddress -Name $publicIpAddress -ResourceGroupName $resourceGroup -Force
Restart-Computer -Force
