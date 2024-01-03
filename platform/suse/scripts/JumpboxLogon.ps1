function Verify-ServerStart
{
  param(
    [string]$serverName,
    [string]$ipAddress,
    [string]$maxAttempts,
    [string]$failedSleepTime
  )
  $success = 0
  $attempts = 1
  while (($success -eq 0) -and ($attempts -le $maxAttempts)) {
    $output = $null
    $output = ssh-keyscan -t ecdsa $ipAddress

    if ($null -ne $output) {
        $success = 1
    }
          
    if ($success -eq 0) {
      Write-Host "$(Get-Date) - Failed to add known host for $serverName on $ipAddress - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Failed to add known host for $serverName on $ipAddress after $maxAttempts attempts"
      }
    }
    else {
      Write-Host "$(Get-Date) - Successfully added known host for $serverName on $ipAddress"
      $output | Set-Content -Encoding UTF8 $HOME\.ssh\known_hosts
    }
    $attempts += 1
  }
}

function Install-SuseServer
{
    param(
        [string]$serverName,
        [string]$ipAddress,
        [string]$adminUsername,
        [string]$adminPassword
    )
    Copy-Item -Path "C:\Deployment\susesrv\osdisk.vhdx" -Destination "C:\Hyper-V\$susesrv\osdisk.vhdx"
    New-VM -Name $susesrv -MemoryStartupBytes 24GB -BootDevice VHD -VHDPath "C:\Hyper-V\$susesrv\osdisk.vhdx" -Path "C:\Hyper-V" -Generation 2 -Switch $switchName
    Set-VMProcessor -VMName $susesrv -Count 12
    Set-VMFirmware -VMName $susesrv -EnableSecureBoot off
    Set-VM -Name $susesrv -AutomaticStartAction Start -AutomaticStopAction ShutDown
    Start-VM -Name $susesrv
    Start-Sleep -Seconds 10

    Verify-ServerStart -serverName "$susesrv" -ipAddress "192.168.0.4" -maxAttempts 60 -failedSleepTime 10

    scp -i $HOME\.ssh\susesrv_id_rsa /../Deployment/susesrv/susesrv_id_rsa* root@192.168.0.4:~/

    Write-Host "$(Get-Date) - Congigure networking and logins for $susesrv"
$script = @"
# Add Hostname
echo "$serverName" >> /etc/hostname

# Update network config
sed 's/192.168.0.4/$($ipAddress)/' /etc/sysconfig/network/ifcfg-eth0 > /etc/sysconfig/network/ifcfg-eth0.updated
mv /etc/sysconfig/network/ifcfg-eth0.updated /etc/sysconfig/network/ifcfg-eth0

# Update hosts file
sed 's/192.168.0.4\tsusesrv/$($ipAddress)\t$($serverName)/' /etc/hosts > /etc/hosts.updated
mv /etc/hosts.updated /etc/hosts

# Add route for default gateway
echo "default 192.168.0.1 - -" >> /etc/sysconfig/network/routes

# Update DNS server
sed 's/NETCONFIG_DNS_STATIC_SERVERS=\"\"/NETCONFIG_DNS_STATIC_SERVERS=\"192.168.0.1\"/' /etc/sysconfig/network/config > /etc/sysconfig/network/config.updated
mv /etc/sysconfig/network/config.updated /etc/sysconfig/network/config

# Alter root password
yes $adminPassword | passwd root

# Create admin user and password
mkdir /home/$($adminUsername)
useradd $adminUsername -d /home/$($adminUsername)
yes $adminPassword | passwd $adminUsername
chown $($adminUsername):users /home/$($adminUsername)

# Update time synchronization server
sed 's/#allow 192.168.0.0\/16/allow 192.168.0.0\/16/' /etc/chrony.conf > /etc/chrony.conf.updated
mv /etc/chrony.conf.updated /etc/chrony.conf
reboot
"@

    ssh -i $HOME\.ssh\susesrv_id_rsa root@192.168.0.4 $($script)
}

function Connect-SuseServer
{
    param(
        [string]$serverName,
        [string]$ipAddress,
        [string]$adminPassword,
        [string]$suseLicenseKey
    )
    Verify-ServerStart -serverName "$susesrv" -ipAddress $susesrvip -maxAttempts 60 -failedSleepTime 10

$script = @"
# Register license key
suseconnect -r $suseLicenseKey

# Install and configure sudo
zypper install -y sudo
sed 's/root ALL=(ALL:ALL) ALL/root ALL=(ALL:ALL) ALL\nazureuser ALL=NOPASSWD: ALL/' /etc/sudoers > /etc/sudoers.updated
mv /etc/sudoers.updated /etc/sudoers

# Install and configure sshpass
zypper addrepo https://download.opensuse.org/repositories/network/SLE_15/network.repo
sudo zypper --gpg-auto-import-keys refresh
zypper install -y sshpass
echo $adminPassword > /root/sshpassfile

# Add known host
ssh-keyscan -t ecdsa $ipAddress > /root/.ssh/known_hosts
sshpass -f /root/sshpassfile ssh-copy-id -i /root/susesrv_id_rsa.pub azureuser@$($ipAddress)
"@
    ssh -i $HOME\.ssh\susesrv_id_rsa root@$($ipAddress) $($script)
}

function Setup-K8sCluster
{
    param(
        [string]$serverName,
        [string]$ipAddress,
        [string]$adminUsername,
        [string]$adminPassword,
        [string]$netbiosName,
        [string]$domainSuffix
    )

$script = @"
# Create new disk partition
sudo fdisk /dev/sdb <<EEOF
n
p
1


w
EEOF

# Format disk partition and mount as folder for longhorn
sudo mkfs -t ext4 /dev/sdb1
sudo mkdir -p /var/longhorn-storage
sudo blkid /dev/sdb1 > /home/$($adminUsername)/storage_uuid
storage_uuid=`$(</home/$($adminUsername)/storage_uuid)
storage_uuid=`${storage_uuid:17:36}
cp /etc/fstab /home/$($adminUsername)/fstab
echo -e "UUID=`$storage_uuid\\t/var/longhorn-storage\\text4\\tnoatime,x-systemd.automount,x-systemd.device-timeout=10,x-systemd.idle-timeout=1min 0 2" >> /home/$($adminUsername)/fstab
sudo cp /home/$($adminUsername)/fstab /etc/fstab
sudo mount -a

# Join to the domain
sudo zypper -n install realmd adcli sssd sssd-tools sssd-ad samba-client
echo '$adminPassword' | sudo realm join $($netbiosName.ToLower()).$($domainSuffix) -U '$($adminUsername)@$($netbiosName.ToUpper()).$($domainSuffix.ToUpper())' -v

# Add firewall rules
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=9345 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=6443 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=8472 protocol=udp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=10250 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=2379-2381 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=30000-32767 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=4240 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule protocol value=icmp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=179 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=4789 protocol=udp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=5473 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=9098-9099 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=51820-51821 protocol=udp accept'

sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=3260 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=8000 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=8500-8501 protocol=tcp accept'
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=9500-9503 protocol=tcp accept'

sudo systemctl stop firewalld

"@

if ($serverName -eq "susesrv01")
{
$script += @"
# Configure and startup Rancher RKE2 cluster
sudo mkdir -p /etc/rancher/rke2/
echo token: my-shared-secret > /home/$($Env:adminUsername)/config.yaml
echo tls-san: >> /home/$($Env:adminUsername)/config.yaml
echo "    - my-kubernetes-domain.com" >> /home/$($Env:adminUsername)/config.yaml
echo "    - another-kubernetes-domain.com" >> /home/$($Env:adminUsername)/config.yaml
sudo cp /home/$($Env:adminUsername)/config.yaml /etc/rancher/rke2/config.yaml
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

"@
}
else
{
$script += @"
# Configure and startup Rancher RKE2 cluster
sudo mkdir -p /etc/rancher/rke2/
echo token: my-shared-secret > /home/$($Env:adminUsername)/config.yaml
echo server: https://192.168.0.5:9345 >> /home/$($Env:adminUsername)/config.yaml
echo tls-san: >> /home/$($Env:adminUsername)/config.yaml
echo "    - my-kubernetes-domain.com" >> /home/$($Env:adminUsername)/config.yaml
echo "    - another-kubernetes-domain.com" >> /home/$($Env:adminUsername)/config.yaml
sudo cp /home/$($Env:adminUsername)/config.yaml /etc/rancher/rke2/config.yaml
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

"@
}

$script += @"
# Install vim and nano plus other pre-reqs for Longhorn
sudo zypper install -y open-iscsi
sudo zypper install -y vim
sudo zypper addrepo https://download.opensuse.org/repositories/editors/15.5/editors.repo
sudo zypper --gpg-auto-import-keys refresh
sudo zypper install -y nano
sudo zypper install -y jq

# Configure kubectl for client connection 
curl -LO "https://dl.k8s.io/release/`$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
mkdir /home/$($Env:adminUsername)/.kube
sudo cp -T /etc/rancher/rke2/rke2.yaml /home/$($Env:adminUsername)/.kube/config
sudo chown $($Env:adminUsername):users /home/$($Env:adminUsername)/.kube/config
sed 's/127.0.0.1/$($susesrvip)/' /home/$($Env:adminUsername)/.kube/config > /home/$($adminUsername)/.kube/config.updated;
sudo sshpass -f /root/sshpassfile ssh-copy-id -i /root/susesrv_id_rsa.pub $($adminUsername)@$($susesrv)
"@

    ssh -i $HOME\.ssh\susesrv_id_rsa azureuser@$($ipAddress) $($script)
}

function VerifyNodeRunning
{
  param(
    [string]$serverName,
    [string]$maxAttempts,
    [string]$failedSleepTime
  )
  $nodeReady = ""
  $attempts = 1
  while (($nodeReady -ne "True") -and ($attempts -le $maxAttempts)) {
    $nodeReady = kubectl get node $serverName -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"

    if ($nodeReady -ne "True") {
      Write-Host "$(Get-Date) - Node $serverName is not yet available - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Node $serverName not Ready after $maxAttempts attempts"
      }
    }
    else {
      Write-Host "$(Get-Date) - Node $serverName is now Ready"
    }
    $attempts += 1
  }
}

Start-Transcript -Path $Env:DeploymentLogsDir\JumpboxLogon.log -Append

Write-Header "$(Get-Date) - Configuring Domain and DNS on $Env:jumpboxVM"

$securePassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force

# Creating new SQL Service Accounts
Write-Host "$(Get-Date) - Creating SQL Server Service Accounts"
New-ADUser "$($Env:netbiosName.toLower())svc19" -AccountPassword $securePassword -PasswordNeverExpires $true -Enabled $true -KerberosEncryptionType AES256
New-ADUser "$($Env:netbiosName.toLower())svc22" -AccountPassword $securePassword -PasswordNeverExpires $true -Enabled $true -KerberosEncryptionType AES256

# Generating all of the SPNs
Write-Host "$(Get-Date) - Generating SPNs"
setspn -S "MSSQLSvc/mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-0.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-2.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-0:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-1:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-2:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-0" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-1" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-2" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-agl1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):14033" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"
setspn -S "MSSQLSvc/mssql19-agl1:14033" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"

setspn -S "MSSQLSvc/mssql22-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-1.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-2.$($Env:netbiosName.toLower()).$Env:domainSuffix" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-0.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-2.$($Env:netbiosName.toLower()).$($Env:domainSuffix):1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-0:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-1:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-2:1433" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-0" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-1" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-2" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-agl1.$($Env:netbiosName.toLower()).$($Env:domainSuffix):14033" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc22"
setspn -S "MSSQLSvc/mssql22-agl1:14033" "$($Env:netbiosName.toUpper())\$($Env:netbiosName.toLower())svc19"

# Add all of the DNS entry records
Write-Host "$(Get-Date) - Adding DNS records"
Add-DnsServerResourceRecordA -Name "susesrv01" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.0.5" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "susesrv02" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.0.6" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "susesrv03" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.0.7" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "mssql19-0" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.192.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.192.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-2" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.192.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql19-agl1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.192.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "mssql22-0" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.193.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.193.1" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-2" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.193.2" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "mssql22-agl1" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.193.3" -TimeToLive "00:20:00"

Add-DnsServerResourceRecordA -Name "influxdb" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.194.0" -TimeToLive "00:20:00"
Add-DnsServerResourceRecordA -Name "grafana" -ZoneName "$($Env:netbiosName.toLower()).$Env:domainSuffix" -IPv4Address "192.168.194.1" -TimeToLive "00:20:00"

# Create the NAT network
Write-Header "$(Get-Date) - Creating Hyper-V Network"
Write-Host "$(Get-Date) - Creating Internal NAT"
$natName = "InternalNat"
New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 192.168.0.0/16

# Create an internal switch with NAT
Write-Host "$(Get-Date) - Creating Internal vSwitch"
$switchName = 'InternalNATSwitch'
New-VMSwitch -Name $switchName -SwitchType Internal
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*" + $switchName + "*" }
Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6

# Create an internal network (gateway first)
Write-Host "$(Get-Date) - Creating Gateway"
New-NetIPAddress -IPAddress 192.168.0.1 -PrefixLength 16 -InterfaceIndex $adapter.ifIndex

# Setup volumes and folders for SUSE server disks
Write-Header "$(Get-Date) - Setting up SUSE Server Storage"

Initialize-Disk -Number 1 -PartitionStyle GPT
Initialize-Disk -Number 2 -PartitionStyle GPT
Initialize-Disk -Number 3 -PartitionStyle GPT

New-Partition -disknumber 1 -usemaximumsize | Format-Volume -filesystem NTFS -newfilesystemlabel DataDisk0
New-Partition -disknumber 2 -usemaximumsize | Format-Volume -filesystem NTFS -newfilesystemlabel DataDisk1
New-Partition -disknumber 3 -usemaximumsize | Format-Volume -filesystem NTFS -newfilesystemlabel DataDisk2

Get-Partition -disknumber 1 | Set-Partition -newdriveletter F
Get-Partition -disknumber 2 | Set-Partition -newdriveletter G
Get-Partition -disknumber 3 | Set-Partition -newdriveletter H

New-Item -Path "C:\Hyper-V" -ItemType directory -Force
New-Item -Path "C:\Hyper-V\susesrv01" -ItemType directory -Force
New-Item -Path "C:\Hyper-V\susesrv02" -ItemType directory -Force
New-Item -Path "C:\Hyper-V\susesrv03" -ItemType directory -Force
New-Item -Path "F:\susesrv01" -ItemType directory -Force
New-Item -Path "G:\susesrv02" -ItemType directory -Force
New-Item -Path "H:\susesrv03" -ItemType directory -Force

# Create and configure SUSE Servers
Write-Header "$(Get-Date) - Spinning up SUSE Servers"

New-Item -Path "$HOME\.ssh" -ItemType directory -Force
Copy-Item -Path "C:\Deployment\susesrv\susesrv_id_rsa*" -Destination "$HOME\.ssh\"

$susesrv = "susesrv01"
$susesrvip = "192.168.0.5"
Write-Header "$(Get-Date) - Spinning up $susesrv"
Write-Host "$(Get-Date) - Creating $susesrv"
Install-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword
Write-Host "$(Get-Date) - Adding data disk to $susesrv"
New-VHD -Path F:\$susesrv\datadisk.vhdx -SizeBytes 256GB -Dynamic
Add-VMHardDiskDrive -VMName $susesrv -Path F:\$susesrv\datadisk.vhdx
Write-Host "$(Get-Date) - Installing dependencies on $susesrv"
Connect-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminPassword $Env:adminPassword -suseLicenseKey $Env:suseLicenseKey
Write-Host "$(Get-Date) - Configuring K8s cluster on $susesrv"
Setup-K8sCluster -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix

$susesrv = "susesrv02"
$susesrvip = "192.168.0.6"
Write-Header "$(Get-Date) - Spinning up $susesrv"
Write-Host "$(Get-Date) - Creating $susesrv"
Install-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword
Write-Host "$(Get-Date) - Adding data disk to $susesrv"
New-VHD -Path F:\$susesrv\datadisk.vhdx -SizeBytes 256GB -Dynamic
Add-VMHardDiskDrive -VMName $susesrv -Path F:\$susesrv\datadisk.vhdx
Write-Host "$(Get-Date) - Installing dependencies on $susesrv"
Connect-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminPassword $Env:adminPassword -suseLicenseKey $Env:suseLicenseKey
Write-Host "$(Get-Date) - Configuring K8s cluster on $susesrv"
Setup-K8sCluster -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix

$susesrv = "susesrv03"
$susesrvip = "192.168.0.7"
Write-Header "$(Get-Date) - Spinning up $susesrv"
Write-Host "$(Get-Date) - Creating $susesrv"
Install-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword
Write-Host "$(Get-Date) - Adding data disk to $susesrv"
New-VHD -Path F:\$susesrv\datadisk.vhdx -SizeBytes 256GB -Dynamic
Add-VMHardDiskDrive -VMName $susesrv -Path F:\$susesrv\datadisk.vhdx
Write-Host "$(Get-Date) - Installing dependencies on $susesrv"
Connect-SuseServer -serverName $susesrv -ipAddress $susesrvip -adminPassword $Env:adminPassword -suseLicenseKey $Env:suseLicenseKey
Write-Host "$(Get-Date) - Configuring K8s cluster on $susesrv"
Setup-K8sCluster -serverName $susesrv -ipAddress $susesrvip -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix

Write-Header "$(Get-Date) - Configuring known_hosts on $Env:jumpboxVM"
ssh-keyscan -t ecdsa 192.168.0.5 > $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa susesrv01 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa 192.168.0.6 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa susesrv02 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa 192.168.0.7 >> $HOME\.ssh\known_hosts
ssh-keyscan -t ecdsa susesrv03 >> $HOME\.ssh\known_hosts
(Get-Content $HOME\.ssh\known_hosts) | Set-Content -Encoding UTF8 $HOME\.ssh\known_hosts

Write-Header "$(Get-Date) - Configuring K8s client on $Env:jumpboxVM"
New-Item -Path "$HOME\.kube" -ItemType directory -Force
scp -i $HOME\.ssh\susesrv_id_rsa $Env:adminUsername@susesrv01:/home/$Env:adminUsername/.kube/config.updated $HOME\.kube\config

Write-Header "$(Get-Date) - Verifying availability of K8s Nodes"
VerifyNodeRunning -serverName "susesrv01" -maxAttempts 60 -failedSleepTime 10
VerifyNodeRunning -serverName "susesrv02" -maxAttempts 60 -failedSleepTime 10
VerifyNodeRunning -serverName "susesrv03" -maxAttempts 60 -failedSleepTime 10

Write-Header "$(Get-Date) - Deploy Longhorn to K8s"
kubectl apply -f $Env:DeploymentDir\longhorn-1.5.3\deploy\longhorn.yaml









ssh -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01

USER=azureuser; PASSWORD=L@bAdm1n1234; echo "${USER}:$(openssl passwd -stdin -apr1 <<< ${PASSWORD})" >> auth
kubectl -n longhorn-system create secret generic basic-auth --from-file=auth
exit

kubectl apply -f C:\Deployment\longhorn-1.5.3\longhorngui.yaml

kubectl apply -f C:\Deployment\metallb-0.13.11\config\manifests\metallb-native.yaml
kubectl apply -f C:\Deployment\metallb-0.13.11\metallb-config.yaml

ssh -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01

sudo zypper addrepo https://packages.microsoft.com/config/sles/15/prod.repo
sudo zypper --gpg-auto-import-keys refresh
sudo ACCEPT_EULA=Y zypper install -y adutil
echo "L@bAdm1n1234" | kinit azureuser@SQLK8S.LOCAL;
adutil keytab createauto -k /home/azureuser/mssql_mssql19-0.keytab -p 1433 -H mssql19-0.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;
adutil keytab createauto -k /home/azureuser/mssql_mssql19-1.keytab -p 1433 -H mssql19-1.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;
adutil keytab createauto -k /home/azureuser/mssql_mssql19-2.keytab -p 1433 -H mssql19-2.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;
adutil keytab createauto -k /home/azureuser/mssql_mssql22-0.keytab -p 1433 -H mssql22-0.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;
adutil keytab createauto -k /home/azureuser/mssql_mssql22-1.keytab -p 1433 -H mssql22-1.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;
adutil keytab createauto -k /home/azureuser/mssql_mssql22-2.keytab -p 1433 -H mssql22-2.sqlk8s.local -y -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234 -s MSSQLSvc;

adutil keytab create -k /home/azureuser/mssql_mssql19-0.keytab -p "sqlk8ssvc19" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;
adutil keytab create -k /home/azureuser/mssql_mssql19-1.keytab -p "sqlk8ssvc19" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;
adutil keytab create -k /home/azureuser/mssql_mssql19-2.keytab -p "sqlk8ssvc19" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;
adutil keytab create -k /home/azureuser/mssql_mssql22-0.keytab -p "sqlk8ssvc22" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;
adutil keytab create -k /home/azureuser/mssql_mssql22-1.keytab -p "sqlk8ssvc22" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;
adutil keytab create -k /home/azureuser/mssql_mssql22-2.keytab -p "sqlk8ssvc22" -e aes256-cts-hmac-sha1-96 --password L@bAdm1n1234;


Certificates
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-0.sqlk8s.local' -addext "subjectAltName = DNS:mssql19-0.sqlk8s.local, DNS:mssql19-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql19-0.key -out mssql19-0.pem -days 365
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-1.sqlk8s.local' -addext "subjectAltName = DNS:mssql19-1.sqlk8s.local, DNS:mssql19-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql19-1.key -out mssql19-1.pem -days 365
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql19-2.sqlk8s.local' -addext "subjectAltName = DNS:mssql19-2.sqlk8s.local, DNS:mssql19-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql19-2.key -out mssql19-2.pem -days 365
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-0.sqlk8s.local' -addext "subjectAltName = DNS:mssql22-0.sqlk8s.local, DNS:mssql22-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql22-0.key -out mssql22-0.pem -days 365
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-1.sqlk8s.local' -addext "subjectAltName = DNS:mssql22-1.sqlk8s.local, DNS:mssql22-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql22-1.key -out mssql22-1.pem -days 365
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mssql22-2.sqlk8s.local' -addext "subjectAltName = DNS:mssql22-2.sqlk8s.local, DNS:mssql22-agl1.sqlk8s.local" -addext "extendedKeyUsage=1.3.6.1.5.5.7.3.1" -addext "keyUsage=keyEncipherment" -keyout mssql22-2.key -out mssql22-2.pem -days 365

exit

New-Item -Path $Env:DeploymentDir\keytab  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\keytab\SQL2019  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\keytab\SQL2022  -ItemType directory -Force

scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql_mssql19*.keytab $Env:DeploymentDir\keytab\SQL2019\
scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql_mssql22*.keytab $Env:DeploymentDir\keytab\SQL2022\

New-Item -Path $Env:DeploymentDir\certificates  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\certificates\SQL2019  -ItemType directory -Force
New-Item -Path $Env:DeploymentDir\certificates\SQL2022  -ItemType directory -Force

scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql19*.pem $Env:DeploymentDir\certificates\SQL2019\
scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql19*.key $Env:DeploymentDir\certificates\SQL2019\
scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql22*.pem $Env:DeploymentDir\certificates\SQL2022\
scp -i $HOME\.ssh\susesrv_id_rsa azureuser@susesrv01:/home/$Env:adminUsername/mssql22*.key $Env:DeploymentDir\certificates\SQL2022\


Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-0.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-1.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2019\mssql19-2.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-0.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-1.pem" -CertStoreLocation "cert:\LocalMachine\Root"
Import-Certificate -FilePath "C:\Deployment\certificates\SQL2022\mssql22-2.pem" -CertStoreLocation "cert:\LocalMachine\Root"

SQL
kubectl create namespace sql22
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\headless-services.yaml -n sql$($currentSqlVersion)
kubectl create secret generic mssql$($currentSqlVersion) --from-literal=MSSQL_SA_PASSWORD=$adminPassword -n sql$($currentSqlVersion)
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\krb5-conf.yaml -n sql$($currentSqlVersion)
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\mssql-conf.yaml -n sql$($currentSqlVersion)
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\mssql.yaml -n sql$($currentSqlVersion)
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\pod-service.yaml -n sql$($currentSqlVersion)
kubectl get pods -n sql$($currentSqlVersion)
kubectl get services -n sql$($currentSqlVersion)
kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName -n sql22
kubectl apply -f $DeploymentDir\yaml\SQL20$($currentSqlVersion)Rancher\service.yaml -n sql$($currentSqlVersion)

kubectl cp \..\Deployment\keytab\SQL2022\mssql_mssql22-0.keytab mssql22-0:/var/opt/mssql/secrets/mssql.keytab -n sql22
kubectl cp \..\Deployment\keytab\SQL2022\mssql_mssql22-1.keytab mssql22-1:/var/opt/mssql/secrets/mssql.keytab -n sql22
kubectl cp \..\Deployment\keytab\SQL2022\mssql_mssql22-2.keytab mssql22-2:/var/opt/mssql/secrets/mssql.keytab -n sql22
kubectl cp "\..\Deployment\yaml\SQL2022\logger.ini" mssql22-0:/var/opt/mssql/logger.ini -n sql22
kubectl cp "\..\Deployment\yaml\SQL2022\logger.ini" mssql22-1:/var/opt/mssql/logger.ini -n sql22
kubectl cp "\..\Deployment\yaml\SQL2022\logger.ini" mssql22-2:/var/opt/mssql/logger.ini -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-0.pem" mssql22-0:/var/opt/mssql/certs/mssql.pem -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-0.key" mssql22-0:/var/opt/mssql/private/mssql.key -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-1.pem" mssql22-1:/var/opt/mssql/certs/mssql.pem -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-1.key" mssql22-1:/var/opt/mssql/private/mssql.key -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-2.pem" mssql22-2:/var/opt/mssql/certs/mssql.pem -n sql22
kubectl cp "\..\Deployment\certificates\SQL2022\mssql22-2.key" mssql22-2:/var/opt/mssql/private/mssql.key -n sql22
kubectl apply -f C:\Deployment\yaml\SQL2022Rancher\mssql-conf-encryption.yaml -n sql22
kubectl delete pod mssql22-0 -n sql22
kubectl delete pod mssql22-1 -n sql22
kubectl delete pod mssql22-2 -n sql22












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
Start-Sleep -Seconds 20

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
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql19-0.keytab -p 1433 -H mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql19-1.keytab -p 1433 -H mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
adutil keytab createauto -k /home/$Env:adminUsername/mssql_mssql19-2.keytab -p 1433 -H mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix -y -e aes256-cts-hmac-sha1-96 --password $Env:adminPassword -s MSSQLSvc;
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

# Generate yaml files for SQL Server 2019 pod and service creation
[System.Environment]::SetEnvironmentVariable('currentSqlVersion', "19", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr2', "4", [System.EnvironmentVariableTarget]::Machine)
$Env:currentSqlVersion = "19"
$Env:vnetIpAddressRangeStr2 = "4"
if ($Env:dH2iAvailabilityGroup -eq "No") {
    & $Env:DeploymentDir\scripts\GenerateSqlYaml.ps1
}
else {
    & $Env:DeploymentDir\scripts\GenerateSqlYamlHA.ps1
}

# Install SQL Server 2019 Containers
if ($Env:installSQL2019 -eq "Yes") {    
    & $Env:DeploymentDir\scripts\InstallSQL.ps1
}

# Generate yaml files for SQL Server 2022 pod and service creation
[System.Environment]::SetEnvironmentVariable('currentSqlVersion', "22", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr2', "5", [System.EnvironmentVariableTarget]::Machine)
$Env:currentSqlVersion = "22"
$Env:vnetIpAddressRangeStr2 = "5"
if ($Env:dH2iAvailabilityGroup -eq "No") {
    & $Env:DeploymentDir\scripts\GenerateSqlYaml.ps1
}
else {
    & $Env:DeploymentDir\scripts\GenerateSqlYamlHA.ps1
}

# Install SQL Server 2022 Containers
if ($Env:installSQL2022 -eq "Yes") {
    & $Env:DeploymentDir\scripts\InstallSQL.ps1
}

# Generate yaml files for Monitor pod and service creation
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr2', "6", [System.EnvironmentVariableTarget]::Machine)
$Env:vnetIpAddressRangeStr2 = "6"
& $Env:DeploymentDir\scripts\GenerateMonitorServiceYaml.ps1

# Install Monitor Containers
if ($Env:installMonitoring -eq "Yes") {
    & $Env:DeploymentDir\scripts\InstallMonitoring.ps1
}

# Cleanup
Write-Header "$(Get-Date) - Cleanup environment"
Get-ScheduledTask -TaskName JumpboxLogon | Unregister-ScheduledTask -Confirm:$false

Remove-Item -Path "$Env:DeploymentDir\scripts\CreateDC.ps1" -Force
Remove-Item -Path "$Env:DeploymentDir\scripts\ConfigureDC.ps1" -Force
Remove-Item -Path "$Env:DeploymentDir\scripts\GenerateLinuxFiles.sh" -Force

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
[System.Environment]::SetEnvironmentVariable('dH2iAvailabilityGroup', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dH2iLicenseKey', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('installMonitoring', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('currentSqlVersion', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr2', "", [System.EnvironmentVariableTarget]::Machine)
