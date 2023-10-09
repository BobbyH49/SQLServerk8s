param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateBaseUrl,
    [string]$spnAppId,
    [string]$spnPassword,
    [string]$tenant,
    [string]$netbiosName,
    [string]$domainSuffix,
    [string]$dcVM,
    [string]$jumpboxVM,
    [string]$jumpboxNic
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
[System.Environment]::SetEnvironmentVariable('netbiosName', $netbiosName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', $domainSuffix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dcVM', $dcVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxVM', $jumpboxVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxNic', $jumpboxNic, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "C:\Deployment", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "C:\Deployment\Logs", [System.EnvironmentVariableTarget]::Machine)

$Env:DeploymentDir = "C:\Deployment"
$Env:DeploymentLogsDir = "$Env:DeploymentDir\Logs"

New-Item -Path $Env:DeploymentDir -ItemType directory -Force
New-Item -Path $Env:DeploymentLogsDir -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\scripts" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\SQL2019" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\SQL2022" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\Monitor" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\Monitor\Grafana" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\Monitor\InfluxDB" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\yaml\Monitor\Telegraf" -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\backups" -ItemType directory -Force

Start-Transcript -Path $Env:DeploymentLogsDir\EnvironmentSetup.log

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
Write-Host "Downloading scripts"
Invoke-WebRequest ($templateBaseUrl + "scripts/ConfigureDC.ps1") -OutFile $Env:DeploymentDir\scripts\ConfigureDC.ps1
Invoke-WebRequest ($templateBaseUrl + "scripts/DCJoinJumpbox.ps1") -OutFile $Env:DeploymentDir\scripts\DCJoinJumpbox.ps1

Write-Host "Downloading SQL Server 2019 yaml and ini files"
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/dxemssql.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\dxemssql.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/headless-services.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\headless-services.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\krb5-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger_debug.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/pod-service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\pod-service.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\service.yaml

Write-Host "Downloading SQL Server 2022 yaml and ini files"
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/dxemssql.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\dxemssql.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/headless-services.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\headless-services.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\krb5-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger_debug.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/pod-service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\pod-service.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\service.yaml

Write-Host "Downloading SQL Monitor yaml and json files"
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/Grafana/Dashboard.json") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\Dashboard.json
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/Grafana/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\deployment.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/Grafana/service.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\service.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/InfluxDB/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\deployment.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/InfluxDB/service.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\service.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/InfluxDB/storage.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\storage.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/Telegraf/config.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\config.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/Monitor/Telegraf/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\deployment.yaml

Write-Host "Downloading AdventureWorks2019 backup file"
Invoke-WebRequest ($templateBaseUrl + "backups/AdventureWorks2019.bak") -OutFile $Env:DeploymentDir\backups\AdventureWorks2019.bak

# Configure Domain Controller
Write-Header "Installing and configuring Domain Controller"
.$Env:DeploymentDir\scripts\ConfigureDC.ps1

# Configure Domain Join Scripts
Write-Header "Configuring Domain Join Scripts"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\DCJoinJumpbox.ps1
Register-ScheduledTask -TaskName "DCJoinJumpbox" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force | out-null

# Remove DNS Server from Jumpbox Nic
Write-Header "Removing DNS Server entry from $Env:jumpboxNic"
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $Env:jumpboxNic
$nic.DnsSettings.DnsServers.Clear()
$nic | Set-AzNetworkInterface | out-null

# Stop logging and Reboot Jumpbox
Write-Header "Rebooting $Env:jumpboxVM"
Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\EnvironmentSetup.log | Where { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\EnvironmentSetup.log -Force
Restart-Computer -Force

# Add to Kerberos.md

#scp azureuser@sqlk8slinux:/home/azureuser/mssql22* C:\SQLContainerDeployment\SQL2022\

#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-0.pem mssql22-0:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-0.key mssql22-0:/etc/ssl/private/mssql.key -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-1.pem mssql22-1:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-1.key mssql22-1:/etc/ssl/private/mssql.key -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-2.pem mssql22-2:/etc/ssl/certs/mssql.pem -n sql22
#kubectl cp \..\SQLContainerDeployment\SQL2022\mssql22-2.key mssql22-2:/etc/ssl/private/mssql.key -n sql22