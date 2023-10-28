param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateBaseUrl,
    [string]$netbiosName,
    [string]$domainSuffix,
    [string]$vnetName,
    [string]$vnetIpAddressRangeStr,
    [string]$dcVM,
    [string]$linuxVM,
    [string]$jumpboxVM,
    [string]$jumpboxNic,
    [string]$installSQL2019,
    [string]$installSQL2022
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('netbiosName', $netbiosName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', $domainSuffix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetName', $vnetName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr', $vnetIpAddressRangeStr, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dcVM', $dcVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('linuxVM', $linuxVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxVM', $jumpboxVM, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxNic', $jumpboxNic, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2019', $installSQL2019, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2022', $installSQL2022, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "C:\Deployment", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "C:\Deployment\Logs", [System.EnvironmentVariableTarget]::Machine)

$Env:DeploymentDir = "C:\Deployment"
$Env:DeploymentLogsDir = "$Env:DeploymentDir\Logs"

New-Item -Path $Env:DeploymentDir -ItemType directory -Force
New-Item -Path $Env:DeploymentLogsDir -ItemType directory -Force
New-Item -Path "$Env:DeploymentDir\templates" -ItemType directory -Force
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
Install-PackageProvider -Name NuGet -Force

# Installing tools
Write-Header "Installing Chocolatey Apps"
$chocolateyAppList = 'azure-cli,az.powershell,kubernetes-cli,microsoft-edge,ssms'

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
Write-Host "Downloading templates"
Invoke-WebRequest ($templateBaseUrl + "templates/linux.json") -OutFile $Env:DeploymentDir\templates\linux.json

Write-Host "Downloading scripts"
Invoke-WebRequest ($templateBaseUrl + "scripts/JumpboxLogon.ps1") -OutFile $Env:DeploymentDir\scripts\JumpboxLogon.ps1

Write-Host "Downloading SQL Server 2019 yaml and ini files"
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/dxemssql.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\dxemssql.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/headless-services.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\headless-services.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\krb5-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger_debug.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf-encryption.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/pod-service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\pod-service.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2019/service.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\service.yaml

Write-Host "Downloading SQL Server 2022 yaml and ini files"
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/dxemssql.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\dxemssql.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/headless-services.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\headless-services.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\krb5-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger_debug.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger.ini
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf.yaml
Invoke-WebRequest ($templateBaseUrl + "yaml/SQL2022/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf-encryption.yaml
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

Write-Header "Making alterations to Edge"
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

# Connect to Azure Subscription
Write-Header "Connecting to Azure"
Connect-AzAccount -Identity
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Configure Domain Controller
Write-Header "Installing Domain Controller on $Env:dcVM"
Write-Host "Configuring CreateDC script for $Env:dcVM"
$dcCreateScript = @"

# Install AD DS feature
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Restart

`$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

# Configure Domain
Import-Module ADDSDeployment
Install-ADDSForest -CreateDnsDelegation:`$false -DatabasePath "C:\Windows\NTDS" -DomainMode "WinThreshold" -DomainName "$($netbiosName.toLower()).$domainSuffix" -DomainNetbiosName $($netbiosName.toUpper()) -ForestMode "WinThreshold" -InstallDns:`$true -LogPath "C:\Windows\NTDS" -NoRebootOnCompletion:`$true -SafeModeAdministratorPassword `$securePassword -SysvolPath "C:\Windows\SYSVOL" -Force

# Reboot Computer
Restart-Computer

"@

$dcCreateFile = "$Env:DeploymentDir\scripts\CreateDC.ps1"
$dcCreateScript | Out-File -FilePath $dcCreateFile -force    

Write-Host "Executing CreateDC script on $Env:dcVM"
$dcCreateResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:dcVM -CommandId "RunPowerShellScript" -ScriptPath $dcCreateFile
Write-Host "Script returned a result of $($dcCreateResult.Status)"
$dcCreateResult | Out-File -FilePath $Env:DeploymentLogsDir\CreateDC.log -force

# Remove DNS Server from Jumpbox Nic
Write-Header "Removing DNS Server entry from $Env:jumpboxNic"
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $Env:jumpboxNic
$nic.DnsSettings.DnsServers.Clear()
$nic | Set-AzNetworkInterface

# Refresh DNS Settings
Write-Header "Refreshing DNS Settings"
ipconfig /release
ipconfig /renew

# Join Azure VM to domain
Write-Header "Joining $Env:jumpboxVM to the domain"
Write-Host "Joining $Env:jumpboxVM to domain"
$domainUsername="$($Env:netbiosName.toUpper())\$Env:adminUsername"
$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($domainUsername, $securePassword)

$joinSuccess = 0
$attempts = 1
while (($joinSuccess = 0) -and ($attempts -le 10)) {
  try {
    Add-Computer -DomainName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -Credential $credential
    $joinSuccess = 1
  }
  catch {
    $attempts += 1
    Write-Host "Failed to join $Env:jumpboxVM to the domain - Attempt $Env:attempts"
    if ($attempts = 10) {
      Write-Host $Error[0]
    }
  }
}

Write-Header "Configuring Domain and DNS on $Env:dcVM"

Write-Host "Configuring ConfigureDC script for $Env:dcVM"
$dcConfigureScript = @"

`$SecurePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

# Creating new SQL Service Accounts
New-ADUser "$($Env:netbiosName.toLower())svc19" -AccountPassword `$SecurePassword -PasswordNeverExpires `$true -Enabled `$true -KerberosEncryptionType AES256
New-ADUser "$($Env:netbiosName.toLower())svc22" -AccountPassword `$SecurePassword -PasswordNeverExpires `$true -Enabled `$true -KerberosEncryptionType AES256

# Generating all of the SPNs
setspn -S MSSQLSvc/mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-0.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-2.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-0:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-1:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-2:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-0 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-1 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-2 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-agl1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):14033 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"
setspn -S MSSQLSvc/mssql19-agl1:14033 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc19"

setspn -S MSSQLSvc/mssql22-0.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-1.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-2.$($Env:netbiosName.toLower()).$Env:domainSuffix $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-0.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-2.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-0:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-1:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-2:1433 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-0 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-1 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-2 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-agl1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):14033 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"
setspn -S MSSQLSvc/mssql22-agl1:14033 $($Env:netbiosName.toUpper())\"$($Env:netbiosName.toLower())svc22"

# Add all of the DNS entry records
Add-DnsServerResourceRecordA -Name "mssql19-0" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-2" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-agl1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "mssql22-0" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-2" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-agl1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "influxdb" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.6.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "grafana" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.6.1" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name $Env:linuxVM -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.16.5" -TimeToLive "00:20:00"

# Create a DNSForwarder for the AKS cluster
Add-DnsServerConditionalForwarderZone -Name "privatelink.$Env:azureLocation.azmk8s.io" -MasterServers "168.63.129.16"

"@

$dcConfigureFile = "$Env:DeploymentDir\scripts\ConfigureDC.ps1"
$dcConfigureScript | Out-File -FilePath $dcConfigureFile -force    

Write-Host "Executing ConfigureDC script on $Env:dcVM"
$dcConfigureResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:dcVM -CommandId "RunPowerShellScript" -ScriptPath $dcConfigureFile
Write-Host "Script returned a result of $($dcConfigureResult.Status)"
$dcConfigureResult | Out-File -FilePath $Env:DeploymentLogsDir\ConfigureDC.log -force

# Configure Jumpbox Logon Script
Write-Header "Configuring Jumpbox Logon Script"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\JumpboxLogon.ps1
Register-ScheduledTask -TaskName "JumpboxLogon" -Trigger $Trigger -User "$($Env:netbiosName.toUpper())\$Env:adminUsername" -Action $Action -RunLevel "Highest" -Force

# Stop logging and Reboot Jumpbox
Write-Header "Rebooting $Env:jumpboxVM"
Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\EnvironmentSetup.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\EnvironmentSetup.log -Force
Restart-Computer
