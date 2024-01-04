param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateSuseUrl,
    [string]$netbiosName,
    [string]$domainSuffix,
    [string]$vnetName,
    [string]$vnetIpAddressRangeStr,
    [string]$jumpboxVM,
    [string]$jumpboxNic,
    [string]$installSQL2019,
    [string]$installSQL2022,
    [string]$dH2iAvailabilityGroup,
    [string]$dH2iLicenseKey,
    [string]$installMonitoring,
    [string]$suseLicenseKey
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateSuseUrl', $templateSuseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('netbiosName', $netbiosName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', $domainSuffix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetName', $vnetName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr', $vnetIpAddressRangeStr, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxVM', $jumpboxVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxNic', $jumpboxNic, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2019', $installSQL2019, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2022', $installSQL2022, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iAvailabilityGroup', $dH2iAvailabilityGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iLicenseKey', $dH2iLicenseKey, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installMonitoring', $installMonitoring, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('suseLicenseKey', $suseLicenseKey, [System.EnvironmentVariableTarget]::Machine)
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
New-Item -Path "$Env:DeploymentDir\susesrv" -ItemType directory -Force

Start-Transcript -Path $Env:DeploymentLogsDir\EnvironmentSetup.log

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateSuseUrl + "scripts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

# Installing PowerShell Module Dependencies
Write-Header "$(Get-Date) - Installing NuGet"
Install-PackageProvider -Name NuGet -Force

# Installing tools
Write-Header "$(Get-Date) - Installing Chocolatey Apps"
$chocolateyAppList = 'azure-cli,az.powershell,kubernetes-cli,microsoft-edge,ssms,sqlcmd'

try {
    choco config get cacheLocation
}
catch {
    Write-Host "$(Get-Date) - Chocolatey not detected, trying to install now"
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

Write-Header "$(Get-Date) - Chocolatey Apps Specified"

$appsToInstall = $chocolateyAppList -split "," | ForEach-Object { "$($_.Trim())" }

foreach ($app in $appsToInstall) {
    Write-Host "$(Get-Date) - Installing $app"
    & choco install $app /y --force --no-progress | Write-Output
}

Write-Header "$(Get-Date) - Fetching Artifacts for SqlServerK8s"
Write-Host "$(Get-Date) - Downloading scripts"
Invoke-WebRequest ($templateSuseUrl + "scripts/JumpboxLogon.ps1") -OutFile $Env:DeploymentDir\scripts\JumpboxLogon.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/GenerateSqlYaml.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateSqlYaml.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/GenerateSqlYamlHA.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateSqlYamlHA.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/InstallSQL.ps1") -OutFile $Env:DeploymentDir\scripts\InstallSQL.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/GenerateMonitorServiceYaml.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateMonitorServiceYaml.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/GenerateMonitoringFiles.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateMonitoringFiles.ps1
Invoke-WebRequest ($templateSuseUrl + "scripts/InstallMonitoring.ps1") -OutFile $Env:DeploymentDir\scripts\InstallMonitoring.ps1

Write-Host "$(Get-Date) - Downloading SQL Server 2019 yaml and ini files"
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2019/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\krb5-conf.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2019/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger_debug.ini
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2019/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger.ini
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2019/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2019/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf-encryption.yaml

Write-Host "$(Get-Date) - Downloading SQL Server 2022 yaml and ini files"
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2022/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\krb5-conf.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2022/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger_debug.ini
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2022/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger.ini
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2022/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/SQL2022/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf-encryption.yaml

Write-Host "$(Get-Date) - Downloading SQL Monitor yaml and json files"
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Grafana/dashboards.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\dashboards.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Grafana/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\deployment.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Grafana/influxdb.json") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\influxdb.json
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Grafana/influxdb.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\influxdb.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/InfluxDB/config.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\config.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/InfluxDB/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\deployment.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/InfluxDB/storage.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\storage.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Telegraf/config.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\config.yaml
Invoke-WebRequest ($templateSuseUrl + "yaml/Monitor/Telegraf/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\deployment.yaml

Write-Host "$(Get-Date) - Downloading AdventureWorks2019 backup file"
Invoke-WebRequest ($templateSuseUrl + "backups/AdventureWorks2019.bak") -OutFile $Env:DeploymentDir\backups\AdventureWorks2019.bak

Write-Host "$(Get-Date) - Downloading susesrv files"
Invoke-WebRequest ($templateSuseUrl + "susesrv/osdisk.zip") -OutFile $Env:DeploymentDir\susesrv\osdisk.zip
Invoke-WebRequest ($templateSuseUrl + "susesrv/susesrv_id_rsa") -OutFile $Env:DeploymentDir\susesrv\susesrv_id_rsa
Invoke-WebRequest ($templateSuseUrl + "susesrv/susesrv_id_rsa.pub") -OutFile $Env:DeploymentDir\susesrv\susesrv_id_rsa.pub

Write-Host "$(Get-Date) - Downloading Longhorn"
Invoke-WebRequest ($templateSuseUrl + "longhorn-1.5.3.zip") -OutFile $Env:DeploymentDir\longhorn-1.5.3.zip

Write-Host "$(Get-Date) - Downloading Metallb"
Invoke-WebRequest ($templateSuseUrl + "metallb-0.13.11.zip") -OutFile $Env:DeploymentDir\metallb-0.13.11.zip

Write-Header "$(Get-Date) - Making alterations to Edge"
# Disable Microsoft Edge sidebar
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name         = 'HubsSidebarEnabled'
$Value        = '00000000'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
  New-Item -Path $RegistryPath -Force
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Disable Microsoft Edge first-run Welcome screen
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name         = 'HideFirstRunExperience'
$Value        = '00000001'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
  New-Item -Path $RegistryPath -Force
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Disabling Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

# Configure Domain Controller
Write-Header "$(Get-Date) - Installing Domain Controller on $Env:jumpboxVM"
Write-Host "$(Get-Date) - Installing AD DS feature"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

Write-Host "$(Get-Date) - Configuring Domain"
Import-Module ADDSDeployment
Install-ADDSForest -CreateDnsDelegation:$false -DatabasePath "C:\Windows\NTDS" -DomainMode "WinThreshold" -DomainName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -DomainNetbiosName $($Env:netbiosName.toUpper()) -ForestMode "WinThreshold" -InstallDns:$true -LogPath "C:\Windows\NTDS" -NoRebootOnCompletion:$true -SafeModeAdministratorPassword $securePassword -SysvolPath "C:\Windows\SYSVOL" -Force

# Install Hyper-V and dependencies
Write-Header "Installing Hyper-V"
Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools

# Configure Jumpbox Logon Script
Write-Header "$(Get-Date) - Configuring Jumpbox Logon Script"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\JumpboxLogon.ps1
#Register-ScheduledTask -TaskName "JumpboxLogon" -Trigger $Trigger -User "$($Env:netbiosName.toUpper())\$Env:adminUsername" -Action $Action -RunLevel "Highest" -Force

# Stop logging and Reboot Jumpbox
Write-Header "$(Get-Date) - Rebooting $Env:jumpboxVM"
Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\EnvironmentSetup.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\EnvironmentSetup.log -Force
Restart-Computer
