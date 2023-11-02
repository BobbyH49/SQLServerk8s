Write-Host "$(Get-Date) - Generating service.yaml for InfluxDB"
$influxPodScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  name: influxdb-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$Env:vnetIpAddressRangeStr2.0
  selector:
    app: influxdb
  ports:
  - name: web
    protocol: TCP
    port: 8086
    targetPort: 8086
"@

$influxPodFile = "$Env:DeploymentDir\yaml\Monitor\InfluxDB\service.yaml"
$influxPodScript | Out-File -FilePath $influxPodFile -force

Write-Host "$(Get-Date) - Generating service.yaml for Grafana"
$grafanaServiceScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  name: grafana-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$Env:vnetIpAddressRangeStr2.1
  selector:
    app: grafana
  ports:
  - name: web
    protocol: TCP
    port: 3000
    targetPort: 3000
"@

$grafanaServiceFile = "$Env:DeploymentDir\yaml\Monitor\Grafana\service.yaml"
$grafanaServiceScript | Out-File -FilePath $grafanaServiceFile -force    
