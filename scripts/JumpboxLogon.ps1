# Connect to Azure Subscription
# Install SQL

Start-Transcript -Path $Env:DeploymentLogsDir\JumpboxLogon.log -Append

Write-Header "Automated Setup"

Write-Host "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
Write-Host "Connecting to Azure"
Connect-AzAccount -Identity | out-null

# Deploy Linux Server with public key authentication
Write-Header "Deploying Linux Server with public key authentication"

# Generate ssh keys
Write-Host "Generating ssh keys"
$linuxKeyFile = $Env:linuxVM.ToLower() + "_id_rsa"
New-Item -Path $HOME\.ssh  -ItemType directory -Force
ssh-keygen -q -t rsa -b 4096 -N '""' -f $HOME\.ssh\$linuxKeyFile
$publicKey = Get-Content $HOME\.ssh\$linuxKeyFile.pub

# Generate parameters for template deployment
Write-Host "Generating parameters for template deployment"
$templateParameters = @{}
$templateParameters.add("adminUsername", $Env:adminUsername)
$templateParameters.add("sshRSAPublicKey", $publicKey)
$templateParameters.add("linuxVM", $Env:linuxVM)

# Deploy Linux server
Write-Host "Deploying $Env:linuxVM"
New-AzResourceGroupDeployment -ResourceGroupName $Env:resourceGroup -Mode Incremental -Force -TemplateFile "C:\Deployment\templates\linux.json" -TemplateParameterObject $templateParameters

# Add known host
Write-Host "Adding $Env:linuxVM as known host"
ssh-keyscan -t ecdsa 10.$Env:vnetIpAddressRangeStr.16.5 >> $HOME\.ssh\known_hosts
(Get-Content $HOME\.ssh\known_hosts) | Set-Content -Encoding UTF8 $HOME\.ssh\known_hosts

Write-Host "To connect to $Env:linuxVM server you can now run ssh -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@10.192.16.5"

# Setup Service Accounts, SPNs and DNS entries
Write-Header "Creating Service Accounts, SPNs and DNS entries on $Env:dcVM"
if (($Env:installSQL2019 -eq "Yes") -or ($Env:installSQL2022 -eq "Yes")) {

    $netbiosNameLower = $Env:netbiosName.ToLower()
    $netbiosNameUpper = $Env:netbiosName.ToUpper()
    $domainPrefixUpper = $Env:domainPrefix.ToUpper()
    $domainPrefixDbPort = $Env:domainPrefix + ":1433"
    $domainPrefixListenerPort = $Env:domainPrefix + ":14033"
    $sqlsvc19 = $netbiosNameLower + "svc19"
    $sqlsvc22 = $netbiosNameLower + "svc22"
    
Write-Host "Configuring script for $dcVM"
$dcScript = @"
$SecurePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

New-ADUser $sqlsvc19 -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -KerberosEncryptionType AES256
New-ADUser $sqlsvc22 -AccountPassword $SecurePassword -PasswordNeverExpires $true -Enabled $true -KerberosEncryptionType AES256

setspn -S MSSQLSvc/mssql19-0.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-1.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-2.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-0.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-1.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-2.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-0:1433 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-1:1433 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-2:1433 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-0 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-1 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-2 $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-agl1.$Env:netbiosNameLower.$domainPrefixListenerPort $netbiosNameUpper\$sqlsvc19
setspn -S MSSQLSvc/mssql19-agl1:14033 $netbiosNameUpper\$sqlsvc19

setspn -S MSSQLSvc/mssql22-0.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-1.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-2.$Env:netbiosNameLower.$Env:domainPrefix $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-0.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-1.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-2.$Env:netbiosNameLower.$domainPrefixDbPort $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-0:1433 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-1:1433 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-2:1433 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-0 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-1 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-2 $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-agl1.$Env:netbiosNameLower.$domainPrefixListenerPort $netbiosNameUpper\$sqlsvc22
setspn -S MSSQLSvc/mssql22-agl1:14033 $netbiosNameUpper\$sqlsvc22

Add-DnsServerResourceRecordA -Name "mssql19-0" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-1" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-2" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-agl1" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.4.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "mssql22-0" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-1" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-2" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-agl1" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.5.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "influxdb" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.6.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "grafana" -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.6.1" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name $Env:linuxVM -ZoneName "$Env:netbiosNameLower.$Env:domainPrefix" -IPv4Address "10.$Env:vnetIpAddressRangeStr.16.5" -TimeToLive "00:20:00"
"@

    $dcFile = "$Env:DeploymentDir\scripts\SqlDomainDependencies.ps1"
    $dcScript | Out-File -FilePath $dcFile -force    

    Write-Host "Executing script on $dcVM"
    $dcResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:dcVM -CommandId "RunPowerShellScript" -ScriptPath File
    Write-Host "Script returned a result of $dcResult.Status"

Write-Host "Configuring script for $linuxVM"
$linuxScript = @"
sudo apt-get update -y;
sudo apt-get install resolvconf;
cp /etc/resolvconf/resolv.conf.d/head resolv.conf;
echo nameserver 10.$Env:vnetIpAddressRangeStr.16.4 >> resolv.conf;
sudo cp resolv.conf /etc/resolvconf/resolv.conf.d/head;
sudo systemctl enable --now resolvconf.service;
sudo apt-get install -y realmd;
sudo apt-get install -y software-properties-common;
sudo apt-get install -y packagekit;
sudo apt-get install -y sssd;
sudo apt-get install -y sssd-tools;
export DEBIAN_FRONTEND=noninteractive;
sudo -E apt -y -qq install krb5-user;
cp /etc/krb5.conf krb5.conf;
sed 's/default_realm = ATHENA.MIT.EDU/default_realm = $netbiosNameUpper.$domainPrefixUpper\n\trdns = false/' krb5.conf > krb5.conf.updated;
sudo cp krb5.conf.updated /etc/krb5.conf;
echo $adminPassword | sudo realm join $netbiosNameLower.$Env:domainPrefix -U '$Env:adminUser@$netbiosNameUpper.$domainPrefixUpper' -v;

curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
sudo apt-get remove adutil-preview
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y adutil

echo $adminPassword | kinit $Env:adminUser@$netbiosNameUpper.$domainPrefixUpper;

adutil keytab createauto -k mssql_mssql22-0.keytab -p 1433 -H mssql19-0.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc
adutil keytab createauto -k mssql_mssql22-1.keytab -p 1433 -H mssql19-1.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc
adutil keytab createauto -k mssql_mssql22-2.keytab -p 1433 -H mssql19-2.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc
adutil keytab createauto -k mssql_mssql22-0.keytab -p 1433 -H mssql22-0.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc
adutil keytab createauto -k mssql_mssql22-1.keytab -p 1433 -H mssql22-1.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc
adutil keytab createauto -k mssql_mssql22-2.keytab -p 1433 -H mssql22-2.$netbiosNameLower.$Env:domainPrefix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc

adutil keytab create -k mssql_mssql19-0.keytab -p $sqlsvc19 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
adutil keytab create -k mssql_mssql19-1.keytab -p $sqlsvc19 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
adutil keytab create -k mssql_mssql19-2.keytab -p $sqlsvc19 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
adutil keytab create -k mssql_mssql22-0.keytab -p $sqlsvc22 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
adutil keytab create -k mssql_mssql22-1.keytab -p $sqlsvc22 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
adutil keytab create -k mssql_mssql22-2.keytab -p $sqlsvc22 -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword
"@

    Write-Host "Executing script on $linuxVM"
    $linuxFile = "$Env:DeploymentDir\scripts\SqlDomainDependencies.sh"
    $linuxScript | Out-File -FilePath $linuxFile -force    

    $linuxResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:linuxVM -CommandId "RunShellScript" -ScriptPath $linuxFile
    Write-Host "Script returned a result of $linuxResult.Status"

    Write-Host "Downloading dependency files from $Env:linuxVM"
    New-Item -Path $Env:DeploymentDir\keytab  -ItemType directory -Force
    New-Item -Path $Env:DeploymentDir\keytab\SQL2019  -ItemType directory -Force
    New-Item -Path $Env:DeploymentDir\keytab\SQL2022  -ItemType directory -Force

    scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@{$Env:linuxVM}:/home/$Env:adminUsername/mssql_mssql19*.keytab $Env:DeploymentDir\keytab\SQL2019\
    scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@{$Env:linuxVM}:/home/$Env:adminUsername/mssql_mssql22*.keytab $Env:DeploymentDir\keytab\SQL2022\
}

Write-Host "Configuration ends: $(Get-Date)"

# Cleanup
Write-Header "Cleanup environment"
Get-ScheduledTask -TaskName JumpboxLogon | Unregister-ScheduledTask -Confirm:$false

Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\JumpboxLogon.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\JumpboxLogon.log -Force

[System.Environment]::SetEnvironmentVariable('adminUsername', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('netbiosName', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetName', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dcVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('linuxVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxNic', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2019', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2022', "", [System.EnvironmentVariableTarget]::Machine)
