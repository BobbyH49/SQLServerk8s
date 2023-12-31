param (
    [string]$adminUsername,
    [string]$adminPassword,
    [string]$resourceGroup,
    [string]$azureLocation,
    [string]$templateAksUrl,
    [string]$netbiosName,
    [string]$domainSuffix,
    [string]$vnetName,
    [string]$vnetIpAddressRangeStr,
    [string]$dcVM,
    [string]$linuxVM,
    [string]$jumpboxVM,
    [string]$jumpboxNic,
    [string]$installSQL2019,
    [string]$installSQL2022,
    [string]$aksCluster,
    [string]$dH2iAvailabilityGroup,
    [string]$dH2iLicenseKey,
    [string]$installMonitoring
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateAksUrl', $templateAksUrl, [System.EnvironmentVariableTarget]::Machine)
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
[System.Environment]::SetEnvironmentVariable('aksCluster', $aksCluster, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iAvailabilityGroup', $dH2iAvailabilityGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iLicenseKey', $dH2iLicenseKey, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installMonitoring', $installMonitoring, [System.EnvironmentVariableTarget]::Machine)
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
Invoke-WebRequest ($templateAksUrl + "scripts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
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
Write-Host "$(Get-Date) - Downloading templates"
Invoke-WebRequest ($templateAksUrl + "templates/linux.json") -OutFile $Env:DeploymentDir\templates\linux.json

Write-Host "$(Get-Date) - Downloading scripts"
Invoke-WebRequest ($templateAksUrl + "scripts/JumpboxLogon.ps1") -OutFile $Env:DeploymentDir\scripts\JumpboxLogon.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/GenerateSqlYaml.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateSqlYaml.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/GenerateSqlYamlHA.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateSqlYamlHA.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/InstallSQL.ps1") -OutFile $Env:DeploymentDir\scripts\InstallSQL.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/GenerateMonitorServiceYaml.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateMonitorServiceYaml.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/GenerateMonitoringFiles.ps1") -OutFile $Env:DeploymentDir\scripts\GenerateMonitoringFiles.ps1
Invoke-WebRequest ($templateAksUrl + "scripts/InstallMonitoring.ps1") -OutFile $Env:DeploymentDir\scripts\InstallMonitoring.ps1

Write-Host "$(Get-Date) - Downloading SQL Server 2019 yaml and ini files"
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2019/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\krb5-conf.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2019/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger_debug.ini
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2019/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2019\logger.ini
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2019/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2019/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2019\mssql-conf-encryption.yaml

Write-Host "$(Get-Date) - Downloading SQL Server 2022 yaml and ini files"
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2022/krb5-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\krb5-conf.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2022/logger_debug.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger_debug.ini
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2022/logger.ini") -OutFile $Env:DeploymentDir\yaml\SQL2022\logger.ini
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2022/mssql-conf.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/SQL2022/mssql-conf-encryption.yaml") -OutFile $Env:DeploymentDir\yaml\SQL2022\mssql-conf-encryption.yaml

Write-Host "$(Get-Date) - Downloading SQL Monitor yaml and json files"
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Grafana/dashboards.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\dashboards.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Grafana/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\deployment.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Grafana/influxdb.json") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\influxdb.json
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Grafana/influxdb.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Grafana\influxdb.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/InfluxDB/config.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\config.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/InfluxDB/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\deployment.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/InfluxDB/storage.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\InfluxDB\storage.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Telegraf/config.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\config.yaml
Invoke-WebRequest ($templateAksUrl + "yaml/Monitor/Telegraf/deployment.yaml") -OutFile $Env:DeploymentDir\yaml\Monitor\Telegraf\deployment.yaml

Write-Host "$(Get-Date) - Downloading AdventureWorks2019 backup file"
Invoke-WebRequest ($templateAksUrl + "backups/AdventureWorks2019.bak") -OutFile $Env:DeploymentDir\backups\AdventureWorks2019.bak

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

# Connect to Azure Subscription
Write-Header "$(Get-Date) - Connecting to Azure"
Connect-AzAccount -Identity
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Configure Domain Controller
Write-Header "$(Get-Date) - Installing Domain Controller on $Env:dcVM"
Write-Host "$(Get-Date) - Configuring CreateDC script for $Env:dcVM"
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

Write-Host "$(Get-Date) - Executing CreateDC script on $Env:dcVM"
$dcCreateResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:dcVM -CommandId "RunPowerShellScript" -ScriptPath $dcCreateFile
Write-Host "$(Get-Date) - Script returned a result of $($dcCreateResult.Status)"
$dcCreateResult | Out-File -FilePath $Env:DeploymentLogsDir\CreateDC.log -force

# Remove DNS Server from Jumpbox Nic
Write-Header "$(Get-Date) - Removing DNS Server entry from $Env:jumpboxNic"
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name $Env:jumpboxNic
$nic.DnsSettings.DnsServers.Clear()
$nic | Set-AzNetworkInterface

# Join Azure VM to domain
Write-Header "$(Get-Date) - Joining $Env:jumpboxVM to the domain"
$domainUsername="$($Env:netbiosName.toUpper())\$Env:adminUsername"
$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($domainUsername, $securePassword)

$joinSuccess = 0
$retries = 1
$maxAttempts = 60
while (($joinSuccess -eq 0) -and ($retries -le 2)) {
  # Refresh DNS Settings
  Write-Header "$(Get-Date) - Refreshing DNS Settings"
  ipconfig /release
  ipconfig /renew
  $attempts = 1
  while (($joinSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
    try {
      Write-Host "$(Get-Date) - Joining $Env:jumpboxVM to the domain - Attempt $attempts"
      Add-Computer -DomainName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -Credential $credential -ErrorAction Stop
      $joinSuccess = 1
    }
    catch {
      Write-Host "$(Get-Date) - Failed to join $Env:jumpboxVM to the domain - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds 10
      }
      else {
        Write-Host $Error[0]
      }
      $attempts += 1
    }
  }
  $retries += 1
}

Write-Header "$(Get-Date) - Configuring Domain and DNS on $Env:dcVM"

Write-Host "$(Get-Date) - Configuring ConfigureDC script for $Env:dcVM"
$dcConfigureScript = @"

`$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

# Creating new SQL Service Accounts
New-ADUser "$($Env:netbiosName.toLower())svc19" -AccountPassword `$securePassword -PasswordNeverExpires `$true -Enabled `$true -KerberosEncryptionType AES256
New-ADUser "$($Env:netbiosName.toLower())svc22" -AccountPassword `$securePassword -PasswordNeverExpires `$true -Enabled `$true -KerberosEncryptionType AES256

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

Write-Host "$(Get-Date) - Executing ConfigureDC script on $Env:dcVM"
$dcConfigureResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:dcVM -CommandId "RunPowerShellScript" -ScriptPath $dcConfigureFile
Write-Host "$(Get-Date) - Script returned a result of $($dcConfigureResult.Status)"
$dcConfigureResult | Out-File -FilePath $Env:DeploymentLogsDir\ConfigureDC.log -force

# Configure Jumpbox Logon Script
Write-Header "$(Get-Date) - Configuring Jumpbox Logon Script"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\JumpboxLogon.ps1
Register-ScheduledTask -TaskName "JumpboxLogon" -Trigger $Trigger -User "$($Env:netbiosName.toUpper())\$Env:adminUsername" -Action $Action -RunLevel "Highest" -Force

# Stop logging and Reboot Jumpbox
Write-Header "$(Get-Date) - Rebooting $Env:jumpboxVM"
Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\EnvironmentSetup.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\EnvironmentSetup.log -Force
Restart-Computer
