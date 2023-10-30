# Connect to Azure Subscription
# Download Kerberos keytabs and TLS certificates
# Install SQL and HA

Start-Transcript -Path $Env:DeploymentLogsDir\JumpboxLogon.log -Append

Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
Write-Header "$(Get-Date) - Connecting to Azure"
Connect-AzAccount -Identity

# Deploy Linux Server with public key authentication
Write-Header "$(Get-Date) - Deploying Linux Server with private key authentication"

# Generate ssh keys
Write-Host "$(Get-Date) - Generating ssh keys"
$linuxKeyFile = "$($Env:linuxVM.toLower())_id_rsa"
New-Item -Path $HOME\.ssh  -ItemType directory -Force
ssh-keygen -q -t rsa -b 4096 -N '""' -f $HOME\.ssh\$linuxKeyFile
$publicKey = Get-Content $HOME\.ssh\$linuxKeyFile.pub

# Generate parameters for template deployment
Write-Host "$(Get-Date) - Generating parameters for template deployment"
$templateParameters = @{}
$templateParameters.add("adminUsername", $Env:adminUsername)
$templateParameters.add("sshRSAPublicKey", $publicKey)
$templateParameters.add("linuxVM", $Env:linuxVM)

# Deploy Linux server
Write-Host "$(Get-Date) - Deploying $Env:linuxVM"
New-AzResourceGroupDeployment -ResourceGroupName $Env:resourceGroup -Mode Incremental -Force -TemplateFile "C:\Deployment\templates\linux.json" -TemplateParameterObject $templateParameters

# Add known host
Write-Host "$(Get-Date) - Adding $Env:linuxVM as known host"
ssh-keyscan -t ecdsa 10.$Env:vnetIpAddressRangeStr.16.5 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa $Env:linuxVM >> $HOME\.ssh\known_hosts
(Get-Content $HOME\.ssh\known_hosts) | Set-Content -Encoding UTF8 $HOME\.ssh\known_hosts

Write-Host "$(Get-Date) - To connect to $Env:linuxVM server you can now run ssh -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$Env:linuxVM"

Write-Header "$(Get-Date) - Generate and download Kerberos keytab and TLS certificates"
Write-Host "$(Get-Date) - Configuring script for $Env:linuxVM"
$linuxScript = @"

# Update hostname and get latest updates
cp /etc/hosts /home/$Env:adminUsername/hosts
echo 127.0.0.1 $Env:linuxVM >> /home/$Env:adminUsername/hosts
sudo cp /home/$Env:adminUsername/hosts /etc/hosts
sudo apt-get update -y;

# Installing and configuring resolvconf
sudo apt-get install resolvconf;
cp /etc/resolvconf/resolv.conf.d/head /home/$Env:adminUsername/resolv.conf;
echo nameserver 10.$Env:vnetIpAddressRangeStr.16.4 >> /home/$Env:adminUsername/resolv.conf;
sudo cp /home/$Env:adminUsername/resolv.conf /etc/resolvconf/resolv.conf.d/head;
sudo systemctl enable --now resolvconf.service;

# Joining $Env:linuxVM to the domain
sudo apt-get install -y realmd;
sudo apt-get install -y software-properties-common;
sudo apt-get install -y packagekit;
sudo apt-get install -y sssd;
sudo apt-get install -y sssd-tools;
export DEBIAN_FRONTEND=noninteractive;
sudo -E apt -y -qq install krb5-user;
cp /etc/krb5.conf /home/$Env:adminUsername/krb5.conf;
sed 's/default_realm = ATHENA.MIT.EDU/default_realm = $($Env:netbiosName.toUpper()).$($Env:domainSuffix.toUpper())\n\trdns = false/' /home/$Env:adminUsername/krb5.conf > /home/$Env:adminUsername/krb5.conf.updated;
sudo cp /home/$Env:adminUsername/krb5.conf.updated /etc/krb5.conf;
echo $Env:adminPassword | sudo realm join $($Env:netbiosName.toLower()).$Env:domainSuffix -U '$Env:adminUsername@$($Env:netbiosName.toUpper()).$($Env:domainSuffix.toUpper())' -v;

# Installing adutil
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -;
sudo curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list;
sudo apt-get remove adutil-preview;
sudo apt-get update;
sudo ACCEPT_EULA=Y apt-get install -y adutil;

# Obtaining Kerberos Ticket
echo $Env:adminPassword | kinit $Env:adminUsername@$($Env:netbiosName.toUpper()).$($Env:domainSuffix.toUpper());

# Generating keytab files
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-0.keytab -p 1433 -H mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-1.keytab -p 1433 -H mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-2.keytab -p 1433 -H mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-0.keytab -p 1433 -H mssql22-0.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-1.keytab -p 1433 -H mssql22-1.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql22-2.keytab -p 1433 -H mssql22-2.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;

adutil keytab create -k /home/$Env:adminUsername/mssql_mssql19-0.keytab -p "$($Env:netbiosName.toLower())svc19" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;
adutil keytab create -k /home/$Env:adminUsername/mssql_mssql19-1.keytab -p "$($Env:netbiosName.toLower())svc19" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;
adutil keytab create -k /home/$Env:adminUsername/mssql_mssql19-2.keytab -p "$($Env:netbiosName.toLower())svc19" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;
adutil keytab create -k /home/$Env:adminUsername/mssql_mssql22-0.keytab -p "$($Env:netbiosName.toLower())svc22" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;
adutil keytab create -k /home/$Env:adminUsername/mssql_mssql22-1.keytab -p "$($Env:netbiosName.toLower())svc22" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;
adutil keytab create -k /home/$Env:adminUsername/mssql_mssql22-2.keytab -p "$($Env:netbiosName.toLower())svc22" -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword;

# Removing error when generating certificates due to missing .rnd file
cp /etc/ssl/openssl.cnf /home/$Env:adminUsername/openssl.cnf;
sed 's/RANDFILE\t\t= `$ENV::HOME\/.rnd/#RANDFILE\t\t= `$ENV::HOME\/.rnd/' /home/$Env:adminUsername/openssl.cnf > /home/$Env:adminUsername/openssl.cnf.updated;
sudo cp /home/$Env:adminUsername/openssl.cnf.updated /etc/ssl/openssl.cnf;

# Generating certificate and private key files
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql19-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql19-0.key -out /home/$Env:adminUsername/mssql19-0.pem -days 365;
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql19-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql19-1.key -out /home/$Env:adminUsername/mssql19-1.pem -days 365;
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql19-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql19-2.key -out /home/$Env:adminUsername/mssql19-2.pem -days 365;

openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-0.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql22-0.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql22-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql22-0.key -out /home/$Env:adminUsername/mssql22-0.pem -days 365;
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-1.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql22-1.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql22-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql22-1.key -out /home/$Env:adminUsername/mssql22-1.pem -days 365;
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-2.$($Env:netbiosName.toLower()).$Env:domainSuffix' -addext "subjectAltName = DNS:mssql22-2.$($Env:netbiosName.toLower()).$Env:domainSuffix, DNS:mssql22-agl1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout /home/$Env:adminUsername/mssql22-2.key -out /home/$Env:adminUsername/mssql22-2.pem -days 365;

# Changing ownership on files to $Env:adminUsername
sudo chown $Env:adminUsername:$Env:adminUsername /home/$Env:adminUsername/mssql*.keytab;
sudo chown $Env:adminUsername:$Env:adminUsername /home/$Env:adminUsername/mssql*.key;
sudo chown $Env:adminUsername:$Env:adminUsername /home/$Env:adminUsername/mssql*.pem;

"@

Write-Host "$(Get-Date) - Executing script on $Env:linuxVM"
$linuxFile = "$Env:DeploymentDir\scripts\GenerateLinuxFiles.sh"
$linuxScript | Out-File -FilePath $linuxFile -force    

$linuxResult = Invoke-AzVMRunCommand -ResourceGroupName $Env:resourceGroup -VMName $Env:linuxVM -CommandId "RunShellScript" -ScriptPath $linuxFile
Write-Host "$(Get-Date) - Script returned a result of $($linuxResult.Status)"
$linuxResult | Out-File -FilePath $Env:DeploymentLogsDir\GenerateLinuxFiles.log -force

# Add known host
Write-Host "$(Get-Date) - Adding $Env:linuxVM as known host"
Remove-Item -Path $HOME\.ssh\known_hosts -Force
ssh-keyscan -t ecdsa 10.$Env:vnetIpAddressRangeStr.16.5 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa $Env:linuxVM >> $HOME\.ssh\known_hosts
(Get-Content $HOME\.ssh\known_hosts) | Set-Content -Encoding UTF8 $HOME\.ssh\known_hosts

Write-Host "$(Get-Date) - Downloading keytab files from $Env:linuxVM"
New-Item -Path $Env:DeploymentDir\keytab  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\keytab\SQL2019  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\keytab\SQL2022  -ItemType directory -Force

scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql_mssql19*.keytab $Env:DeploymentDir\keytab\SQL2019\
scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql_mssql22*.keytab $Env:DeploymentDir\keytab\SQL2022\

Write-Host "$(Get-Date) - Downloading certificate and private key files from $Env:linuxVM"
New-Item -Path $Env:DeploymentDir\certificates  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\certificates\SQL2019  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\certificates\SQL2022  -ItemType directory -Force

scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql19*.pem $Env:DeploymentDir\certificates\SQL2019\
scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql19*.key $Env:DeploymentDir\certificates\SQL2019\
scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql22*.pem $Env:DeploymentDir\certificates\SQL2022\
scp -i $HOME\.ssh\$linuxKeyFile $Env:adminUsername@$($Env:linuxVM):/home/$Env:adminUsername/mssql22*.key $Env:DeploymentDir\certificates\SQL2022\

Write-Host "$(Get-Date) - Installing SQL Server certificates on $Env:jumpboxVM"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-0.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-1.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-2.pem" -CertStoreLocation "cert:\LocalMachine\Root"

Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-0.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-1.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-2.pem" -CertStoreLocation "cert:\LocalMachine\Root"

# Install SQL Server 2019 Containers
if ($Env:installSQL2019 -eq "Yes") {
    [System.Environment]::SetEnvironmentVariable('$currentSQLVersion', "19", [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('$vnetIpAddressRangeStr2', "4", [System.EnvironmentVariableTarget]::Machine)
    
    & $DeploymentDir\scripts\InstallSQL.ps1
}

# Install SQL Server 2022 Containers
if ($Env:installSQL2022 -eq "Yes") {
    [System.Environment]::SetEnvironmentVariable('$currentSQLVersion', "22", [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('$vnetIpAddressRangeStr2', "5", [System.EnvironmentVariableTarget]::Machine)
    
    & $DeploymentDir\scripts\InstallSQL.ps1
}

# Cleanup
Write-Header "$(Get-Date) - Cleanup environment"
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
[System.Environment]::SetEnvironmentVariable('installSQL2019', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installSQL2022', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aksCluster', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iLicenseKey', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('$currentSQLVersion', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('$vnetIpAddressRangeStr2', "", [System.EnvironmentVariableTarget]::Machine)
