function VerifyPodRunning
{
  param(
    [string]$podName,
    [string]$namespace,
    [string]$maxAttempts,
    [string]$failedSleepTime,
    [string]$successSleepTime
  )
  $podStatus = ""
  $attempts = 1
  while (($podStatus -ne "Running") -and ($attempts -le $maxAttempts)) {
    $podStatus = kubectl get pods -n $namespace $podName -o jsonpath="{.status.phase}"

    if ($podStatus -ne "Running") {
      Write-Host "$(Get-Date) - Pod $podName is not yet available - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Failed to restart $podName after $maxAttempts attempts"
      }
    }
    else {
      Write-Host "$(Get-Date) - Pod $podName is now available"
      Start-Sleep -Seconds $successSleepTime
    }
    $attempts += 1
  }
}

function VerifyServiceRunning
{
  param(
    [string]$serviceName,
    [string]$namespace,
    [string]$expectedServiceIP,
    [string]$maxAttempts,
    [string]$failedSleepTime,
    [string]$successSleepTime
  )
  $actualServiceIP = ""
  $attempts = 1
  while (($actualServiceIP -ne $expectedServiceIP) -and ($attempts -le $maxAttempts)) {
    $actualServiceIP = kubectl get services -n $namespace $serviceName -o jsonpath="{.spec.loadBalancerIP}"

    if ($actualServiceIP -ne $expectedServiceIP) {
      Write-Host "$(Get-Date) - Service $serviceName is not yet available - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Failed to restart $serviceName after $maxAttempts attempts"
      }
    }
    else {
      Write-Host "$(Get-Date) - Service $serviceName is now available"
      Start-Sleep -Seconds $successSleepTime
    }
    $attempts += 1
  }
}

function LicenseSqlPod
{
  param(
    [string]$podName,
    [string]$namespace,
    [string]$licenseKey,
    [string]$maxAttempts,
    [string]$failedSleepTime
  )
  $licenseStatus = ""
  $attempts = 1
  while (($licenseStatus -ne "Result: License successfully set") -and ($attempts -le $maxAttempts)) {
    $licenseStatus = kubectl exec -n $namespace -c dxe $podName -- dxcli activate-server $licenseKey --accept-eula

    if ($licenseStatus -ne "Result: License successfully set") {
      Write-Host "$(Get-Date) - Failed to obtain license for $podName - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Failed to obtain license for $podName after $maxAttempts attempts"
        Write-Host $licenseStatus
      }
    }
    else {
      Write-Host "$(Get-Date) - Pod $podName is now licensed"
    }
    $attempts += 1
  }
}

function RunSqlCmd
{
  param(
    [string]$sqlInstance,
    [string]$username,
    [string]$password,
    [string]$inputFile,
    [string]$maxAttempts,
    [string]$failedSleepTime
  )
  $success = 0
  $attempts = 1
  while (($success -eq 0) -and ($attempts -le $maxAttempts)) {
    $runOutput = $null
    $runOutput = SQLCMD -S $sqlInstance -U $username -P $password -i $inputFile

    if ($runOutput.GetType().ToString() -eq "System.String") {
      if (!$runOutput.Contains("no named pipe instance matching")) {
        $success = 1
      }
    }
    else {
      if (!$runOutput[$runOutput.Count - 1].Contains("no named pipe instance matching")) {
        $success = 1
      }
    }
          
    if ($success -eq 0) {
      Write-Host "$(Get-Date) - Failed to run script on $sqlInstance - Attempt $attempts out of $maxAttempts"
      if ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds $failedSleepTime
      }
      else {
        Write-Host "$(Get-Date) - Failed to run script on $sqlInstance after $maxAttempts attempts"
      }
    }
    else {
      Write-Host "$(Get-Date) - Script successfully run on $sqlInstance"
    }
    $attempts += 1
  }
}

# Main
Write-Header "$(Get-Date) - Installing SQL Server 20$($currentSqlVersion) Containers"

Write-Host "$(Get-Date) - Creating sql$($currentSqlVersion) namespace"
kubectl create namespace sql$($currentSqlVersion)

if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  Write-Host "$(Get-Date) - Creating Headless Services for SQL Pods"
  kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\headless-services.yaml -n sql$($currentSqlVersion)
}

Write-Host "$(Get-Date) - Setting sa password"
kubectl create secret generic mssql$($currentSqlVersion) --from-literal=MSSQL_SA_PASSWORD=$Env:adminPassword -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Applying kerberos configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\krb5-conf.yaml -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Applying SQL Server configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\mssql-conf.yaml -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Installing SQL Server Pods"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\mssql.yaml -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Installing SQL Server Pod Services"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\pod-service.yaml -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Verifying pods and services started successfully"
VerifyPodRunning -podName "mssql$($currentSqlVersion)-0" -namespace "sql$($currentSqlVersion)" -maxAttempts 120 -failedSleepTime 10 -successSleepTime 0
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  VerifyPodRunning -podName "mssql$($currentSqlVersion)-1" -namespace "sql$($currentSqlVersion)" -maxAttempts 120 -failedSleepTime 10 -successSleepTime 0
  VerifyPodRunning -podName "mssql$($currentSqlVersion)-2" -namespace "sql$($currentSqlVersion)" -maxAttempts 120 -failedSleepTime 10 -successSleepTime 0  
}

VerifyServiceRunning -serviceName "mssql$($currentSqlVersion)-0-lb" -namespace "sql$($currentSqlVersion)" -expectedServiceIP "192.168.$($internalIpAddressRangeStr).0" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  VerifyServiceRunning -serviceName "mssql$($currentSqlVersion)-1-lb" -namespace "sql$($currentSqlVersion)" -expectedServiceIP "192.168.$($internalIpAddressRangeStr).1" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0
  VerifyServiceRunning -serviceName "mssql$($currentSqlVersion)-2-lb" -namespace "sql$($currentSqlVersion)" -expectedServiceIP "192.168.$($internalIpAddressRangeStr).2" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0
}

Write-Host "$(Get-Date) - Uploading keytab files to pods"
$kubectlDeploymentDir = $Env:DeploymentDir -replace 'C:\\', '\..\'
kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSqlVersion)\mssql_mssql$($currentSqlVersion)-0.keytab mssql$($currentSqlVersion)-0:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSqlVersion)
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSqlVersion)\mssql_mssql$($currentSqlVersion)-1.keytab mssql$($currentSqlVersion)-1:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSqlVersion)
  kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSqlVersion)\mssql_mssql$($currentSqlVersion)-2.keytab mssql$($currentSqlVersion)-2:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSqlVersion)
}

Write-Host "$(Get-Date) - Uploading logger.ini files to pods"
kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSqlVersion)\logger.ini" mssql$($currentSqlVersion)-0:/var/opt/mssql/logger.ini -n sql$($currentSqlVersion)
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSqlVersion)\logger.ini" mssql$($currentSqlVersion)-1:/var/opt/mssql/logger.ini -n sql$($currentSqlVersion)
  kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSqlVersion)\logger.ini" mssql$($currentSqlVersion)-2:/var/opt/mssql/logger.ini -n sql$($currentSqlVersion)
}

Write-Host "$(Get-Date) - Uploading TLS certificates to pods"
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-0.pem" mssql$($currentSqlVersion)-0:/var/opt/mssql/certs/mssql.pem -n sql$($currentSqlVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-0.key" mssql$($currentSqlVersion)-0:/var/opt/mssql/private/mssql.key -n sql$($currentSqlVersion)
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-1.pem" mssql$($currentSqlVersion)-1:/var/opt/mssql/certs/mssql.pem -n sql$($currentSqlVersion)
  kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-1.key" mssql$($currentSqlVersion)-1:/var/opt/mssql/private/mssql.key -n sql$($currentSqlVersion)
  kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-2.pem" mssql$($currentSqlVersion)-2:/var/opt/mssql/certs/mssql.pem -n sql$($currentSqlVersion)
  kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSqlVersion)\mssql$($currentSqlVersion)-2.key" mssql$($currentSqlVersion)-2:/var/opt/mssql/private/mssql.key -n sql$($currentSqlVersion)
}

Write-Host "$(Get-Date) - Updating SQL Server Configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\mssql-conf-encryption.yaml -n sql$($currentSqlVersion)

Write-Host "$(Get-Date) - Deleting pods to apply new configurations"
kubectl delete pod mssql$($currentSqlVersion)-0 -n sql$($currentSqlVersion)
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  Start-Sleep -Seconds 5
  kubectl delete pod mssql$($currentSqlVersion)-1 -n sql$($currentSqlVersion)
  Start-Sleep -Seconds 5
  kubectl delete pod mssql$($currentSqlVersion)-2 -n sql$($currentSqlVersion)
}

Write-Host "$(Get-Date) - Verifying pods restarted successfully"
VerifyPodRunning -podName "mssql$($currentSqlVersion)-0" -namespace "sql$($currentSqlVersion)" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 10
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  VerifyPodRunning -podName "mssql$($currentSqlVersion)-1" -namespace "sql$($currentSqlVersion)" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 10
  VerifyPodRunning -podName "mssql$($currentSqlVersion)-2" -namespace "sql$($currentSqlVersion)" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 10
}

Write-Host "$(Get-Date) - Generating T-SQL scripts"
$sqlLoginScript = @"
USE [master];
GO

CREATE LOGIN [$($Env:netbiosName.toUpper())\$Env:adminUsername] FROM WINDOWS;
ALTER SERVER ROLE [sysadmin] ADD MEMBER [$($Env:netbiosName.toUpper())\$Env:adminUsername];
GO

CREATE LOGIN [Telegraf] WITH PASSWORD = N'$Env:adminPassword', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;
GRANT VIEW SERVER STATE TO [Telegraf];
GRANT VIEW ANY DEFINITION TO [Telegraf];
GO
"@

$sqlLoginFile = "$Env:DeploymentDir\scripts\CreateLogins.sql"
$sqlLoginScript | Out-File -FilePath $sqlLoginFile -force

$sqlRestoreScript = @"
RESTORE DATABASE AdventureWorks2019
FROM DISK = N'/var/opt/mssql/backup/AdventureWorks2019.bak'
WITH
MOVE N'AdventureWorks2017' TO N'/var/opt/mssql/userdata/AdventureWorks2019.mdf'
, MOVE N'AdventureWorks2017_log' TO N'/var/opt/mssql/userlog/AdventureWorks2019_log.ldf'
, RECOVERY, STATS = 10;
GO

ALTER DATABASE AdventureWorks2019 SET RECOVERY FULL;
GO

BACKUP DATABASE AdventureWorks2019
TO DISK = N'/var/opt/mssql/backup/AdventureWorks2019_Full_Recovery.bak'
WITH FORMAT, INIT, COMPRESSION, STATS = 10;
GO
"@

$sqlRestoreFile = "$Env:DeploymentDir\scripts\RestoreDatabase.sql"
$sqlRestoreScript | Out-File -FilePath $sqlRestoreFile -force

Write-Host "$(Get-Date) - Creating Windows sysadmin login and Telegraf monitoring login"
RunSqlCmd -sqlInstance "mssql$($currentSqlVersion)-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -username "sa" -password $Env:adminPassword -inputFile $sqlLoginFile -maxAttempts 60 -failedSleepTime 10
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
  RunSqlCmd -sqlInstance "mssql$($currentSqlVersion)-1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -username "sa" -password $Env:adminPassword -inputFile $sqlLoginFile -maxAttempts 60 -failedSleepTime 10
  RunSqlCmd -sqlInstance "mssql$($currentSqlVersion)-2.$($Env:netbiosName.toLower()).$Env:domainSuffix" -username "sa" -password $Env:adminPassword -inputFile $sqlLoginFile -maxAttempts 60 -failedSleepTime 10
}
else {
  Write-Host "$(Get-Date) - Copying backup file to mssql$($currentSqlVersion)-0"
  kubectl cp $kubectlDeploymentDir\backups\AdventureWorks2019.bak mssql$($currentSqlVersion)-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql$($currentSqlVersion)

  Write-Host "$(Get-Date) - Restoring database backup"
  RunSqlCmd -sqlInstance "mssql$($currentSqlVersion)-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -username "sa" -password $Env:adminPassword -inputFile $sqlRestoreFile -maxAttempts 60 -failedSleepTime 10
}

# Configure High Availability
if ($Env:dH2iAvailabilityGroup -eq "Yes") {
    Write-Header "$(Get-Date) - Configuring High Availability"

    Write-Host "$(Get-Date) - Licensing pods"
    LicenseSqlPod -podName "mssql$($currentSqlVersion)-0" -namespace "sql$($currentSqlVersion)" -licenseKey $Env:dH2iLicenseKey -maxAttempts 60 -failedSleepTime 10
    LicenseSqlPod -podName "mssql$($currentSqlVersion)-1" -namespace "sql$($currentSqlVersion)" -licenseKey $Env:dH2iLicenseKey -maxAttempts 60 -failedSleepTime 10
    LicenseSqlPod -podName "mssql$($currentSqlVersion)-2" -namespace "sql$($currentSqlVersion)" -licenseKey $Env:dH2iLicenseKey -maxAttempts 60 -failedSleepTime 10

    Write-Host "$(Get-Date) - Creating HA Cluster on mssql$($currentSqlVersion)-0"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli cluster-add-vhost mssql$($currentSqlVersion)-agl1 *127.0.0.1 mssql$($currentSqlVersion)-0

    Write-Host "$(Get-Date) - Getting encrypted password for sa"
    $saSecurePassword = kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli encrypt-text $Env:adminPassword

    Write-Host "$(Get-Date) - Creating Availability Group on mssql$($currentSqlVersion)-0"
    if ($currentSqlVersion -eq "19") {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli add-ags mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-0|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli add-ags mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-0|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0" "CONTAINED"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Setting the cluster passkey using admin password"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli cluster-set-secret-ex $Env:adminPassword

    Write-Host "$(Get-Date) - Enabling vhost lookup in DxEnterprise's global settings"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli set-globalsetting membername.lookup true

    Write-Host "$(Get-Date) - Joining mssql$($currentSqlVersion)-1 to cluster"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-1 -- dxcli join-cluster-ex mssql$($currentSqlVersion)-0 $Env:adminPassword

    Write-Host "$(Get-Date) - Joining mssql$($currentSqlVersion)-1 to the Availability Group"
    if ($currentSqlVersion -eq "19") {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-1 -- dxcli add-ags-node mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-1|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-1 -- dxcli add-ags-node mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-1|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Joining mssql$($currentSqlVersion)-2 to cluster"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-2 -- dxcli join-cluster-ex mssql$($currentSqlVersion)-0 $Env:adminPassword

    Write-Host "$(Get-Date) - Joining mssql$($currentSqlVersion)-2 to the Availability Group"
    if ($currentSqlVersion -eq "19") {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-2 -- dxcli add-ags-node mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-2|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-2 -- dxcli add-ags-node mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 "mssql$($currentSqlVersion)-2|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Creating Tunnel for Listener"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" mssql$($currentSqlVersion)-agl1

    Write-Host "$(Get-Date) - Setting the Listener Port to 14033"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli add-ags-listener mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 14033

    Write-Host "$(Get-Date) - Creating Load Balancer Service"
    kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\service.yaml -n sql$($currentSqlVersion)

    Write-Host "$(Get-Date) - Verifying listener service started successfully"
    VerifyServiceRunning -serviceName "mssql$($currentSqlVersion)-cluster-lb" -namespace "sql$($currentSqlVersion)" -expectedServiceIP "192.168.$($internalIpAddressRangeStr).3" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 10

    Write-Host "$(Get-Date) - Copying backup file to mssql$($currentSqlVersion)-0"
    kubectl cp $kubectlDeploymentDir\backups\AdventureWorks2019.bak mssql$($currentSqlVersion)-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql$($currentSqlVersion)
    
    Write-Host "$(Get-Date) - Restoring database backup"
    RunSqlCmd -sqlInstance "mssql$($currentSqlVersion)-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -username "sa" -password $Env:adminPassword -inputFile $sqlRestoreFile -maxAttempts 60 -failedSleepTime 10

    Write-Host "$(Get-Date) - Adding database to Availability Group"
    kubectl exec -n sql$($currentSqlVersion) -c dxe mssql$($currentSqlVersion)-0 -- dxcli add-ags-databases mssql$($currentSqlVersion)-agl1 mssql$($currentSqlVersion)-ag1 AdventureWorks2019
}
