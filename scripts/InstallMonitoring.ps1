function VerifyPodRunning
{
  param(
    [string]$podApp,
    [string]$namespace,
    [string]$maxAttempts,
    [string]$failedSleepTime,
    [string]$successSleepTime
  )
  $podStatus = ""
  $attempts = 1
  while (($podStatus -ne "Running") -and ($attempts -le $maxAttempts)) {
    $podStatus = kubectl get pods -n $namespace -o jsonpath="{.items[?(@.metadata.labels.app=='$podApp')].status.phase}"

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

# Main
Write-Header "$(Get-Date) - Installing SQL Server Monitoring Containers"

Write-Host "$(Get-Date) - Login to Azure"
az login --identity

Write-Host "$(Get-Date) - Connecting to $Env:aksCluster"
az aks get-credentials -n $Env:aksCluster -g $Env:resourceGroup

Write-Host "$(Get-Date) - Creating sql$($Env:currentSqlVersion) namespace"
kubectl create namespace sqlmonitor

Write-Host "$(Get-Date) - Configure Storage for InfluxDB"
kubectl apply -f "$Env:DeploymentDir\yaml\Monitor\InfluxDB\storage.yaml" -n sqlmonitor

Write-Host "$(Get-Date) - Deploy InfluxDB"
kubectl apply -f "$Env:DeploymentDir\yaml\Monitor\InfluxDB\deployment.yaml" -n sqlmonitor

Write-Host "$(Get-Date) - Expose internal IP Address and Port for InfluxDB"
kubectl expose deployment influxdb --port=8086 --target-port=8086 --protocol=TCP --type=ClusterIP -n sqlmonitor

Write-Host "$(Get-Date) - Create internal load balancer for InfluxDB"
kubectl apply -f "$Env:DeploymentDir\yaml\Monitor\InfluxDB\service.yaml" -n sqlmonitor

Write-Host "$(Get-Date) - Verify pod and service started successfully"
VerifyPodRunning -podApp "influxdb" -namespace "sqlmonitor" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0
VerifyServiceRunning -serviceName "influxdb-lb" -namespace "sqlmonitor" -expectedServiceIP "10.$Env:vnetIpAddressRangeStr.$($Env:vnetIpAddressRangeStr2).0" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0

Write-Host "$(Get-Date) - Get the InfluxDB Pod Name"
$podName = kubectl get pods -n sqlmonitor -o jsonpath="{.items[?(@.metadata.labels.app=='influxdb')].metadata.name}"

Write-Host "$(Get-Date) - Create InfluxDB user, org and bucket with retention of 1 week"
kubectl exec -n sqlmonitor -c influxdb $podName -- influx setup -u $Env:adminUsername -p $Env:adminPassword -o sqlmon -b sqlmon -r 1w -f

Write-Host "$(Get-Date) - Generate Telegraf Configuration Files"
& $Env:DeploymentDir\scripts\DynamicTelegrafConfig.ps1

Write-Host "$(Get-Date) - "Copy telegraf_config.conf"
$kubectlDeploymentDir = $Env:DeploymentDir -replace 'C:\\', '\..\'
kubectl cp "$kubectlDeploymentDir\yaml\Monitor\InfluxDB\telegraf.conf" "$($podName):/home/influxdb" -n sqlmonitor

Write-Host "$(Get-Date) - Create Telegraf Agent Configuration in InfluxDB"
kubectl exec -n sqlmonitor -c influxdb $podName -- influx telegrafs create -n "sqlmon" -f /home/influxdb/telegraf.conf

Write-Host "$(Get-Date) - Apply Telegraf Configuration"
kubectl apply -f "$Env:DeploymentDir\yaml\Monitor\Telegraf\config.yaml" -n sqlmonitor

Write-Host "$(Get-Date) - Deploy Telegraf Agent"
kubectl apply -f "$Env:DeploymentDir\yaml\Monitor\Telegraf\deployment.yaml" -n sqlmonitor

Write-Host "$(Get-Date) - Configure Telegraf Agent Service"
kubectl expose deployment telegraf --port=8125 --target-port=8125 --protocol=UDP --type=NodePort -n sqlmonitor

Write-Host "$(Get-Date) - Verify pod started successfully"
VerifyPodRunning -podApp "telegraf" -namespace "sqlmonitor" -maxAttempts 60 -failedSleepTime 10 -successSleepTime 0
