param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateBaseUrl,
    [string]$spnAppId,
    [string]$spnPassword,
    [string]$tenant
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnAppId', $spnAppId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnPassword', $spnPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('tenant', $tenant, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('JumpboxDir', "C:\Jumpbox", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('JumpboxLogsDir', "C:\Jumpbox\Logs", [System.EnvironmentVariableTarget]::Machine)

$Env:JumpboxDir = "C:\Jumpbox"
$Env:JumpboxLogsDir = "$Env:JumpboxDir\Logs"

New-Item -Path $Env:JumpboxDir -ItemType directory -Force
New-Item -Path $Env:JumpboxLogsDir -ItemType directory -Force

Start-Transcript -Path $Env:JumpboxLogsDir\EnvironmentSetup.log

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateBaseUrl + "scripts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

# Installing PowerShell Module Dependencies
Write-Header "Installing NuGet"
Install-PackageProvider -Name NuGet -Force | out-null

# Installing tools
Write-Header "Installing Chocolatey Apps"
$chocolateyAppList = 'azure-cli,az.powershell,kubernetes-cli,ssms,putty'

try {
    choco config get cacheLocation
}
catch {
    Write-Host "Chocolatey not detected, trying to install now"
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

Write-Header "Chocolatey Apps Specified"

$appsToInstall = $chocolateyAppList -split "," | foreach { "$($_.Trim())" }

foreach ($app in $appsToInstall) {
    Write-Host "Installing $app"
    & choco install $app /y --force --no-progress | Write-Output
    
}

Write-Header "Fetching Artifacts for SqlServerK8s"
Write-Host "Downloading scripts/ConfigureDC.ps1"
Invoke-WebRequest ($templateBaseUrl + "scripts/ConfigureDC.ps1") -OutFile $Env:JumpboxDir\ConfigureDC.ps1
Write-Host "Downloading scripts/DCJoinJumpbox.ps1"
Invoke-WebRequest ($templateBaseUrl + "scripts/DCJoinJumpbox.ps1") -OutFile $Env:JumpboxDir\DCJoinJumpbox.ps1

# Configure Domain Controller
Write-Header "Installing and configuring Domain Controller"
.$Env:JumpboxDir\ConfigureDC.ps1

# Configure Domain Join Scripts
Write-Header "Configuring Domain Join Scripts"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:JumpboxDir\DCJoinJumpbox.ps1
Register-ScheduledTask -TaskName "DCJoinJumpbox" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force | out-null

# Remove DNS Server from SqlK8sJumpbox-nic
Write-Header "Removing DNS Server entry from NIC"
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name "SqlK8sJumpbox-nic"
$nic.DnsSettings.DnsServers.Clear()
$nic | Set-AzNetworkInterface | out-null

# Stop logging and Reboot Jumpbox
Write-Header "Rebooting Jumpbox"
Stop-Transcript
$logSuppress = Get-Content $Env:JumpboxLogsDir\EnvironmentSetup.log | Where { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:JumpboxLogsDir\EnvironmentSetup.log -Force
Restart-Computer -Force

# Add to Kerberos.md

#scp azureuser@sqlk8slinux:/home/azureuser/mssql22* C:\SQLContainerDeployment\SQL2022\

#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-0.pem mssql22-0:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-0.key mssql22-0:/etc/ssl/private/mssql.key -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-1.pem mssql22-1:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-1.key mssql22-1:/etc/ssl/private/mssql.key -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-2.pem mssql22-2:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-2.key mssql22-2:/etc/ssl/private/mssql.key -n sql22