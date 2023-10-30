Write-Header "$(Get-Date) - Installing SQL Server 20$($currentSQLVersion) Containers"

Write-Host "$(Get-Date) - Login to Azure"
az login --identity

Write-Host "$(Get-Date) - Connecting to $Env:aksCluster"
az aks get-credentials -n $Env:aksCluster -g $Env:resourceGroup

Write-Host "$(Get-Date) - Creating sql$($currentSQLVersion) namespace"
kubectl create namespace sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Creating Headless Services for SQL Pods"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\headless-services.yaml -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Setting sa password"
kubectl create secret generic mssql$($currentSQLVersion) --from-literal=MSSQL_SA_PASSWORD=$Env:adminPassword -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Applying kerberos configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\krb5-conf.yaml -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Applying SQL Server configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\mssql-conf.yaml -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Installing SQL Server Pods"
$mssqlPodScript = @"
#DxEnterprise + MSSQL StatefulSet
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
name: azure-disk
provisioner: kubernetes.io/azure-disk
parameters:
storageaccounttype: Standard_LRS
kind: Managed
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
name: mssql$($currentSQLVersion)
labels:
app: mssql$($currentSQLVersion)
spec:
serviceName: mssql$($currentSQLVersion)
replicas: 3
podManagementPolicy: Parallel
selector:
matchLabels:
  app: mssql$($currentSQLVersion)
template:
metadata:
  labels:
    app: mssql$($currentSQLVersion)
spec:
  securityContext:
    fsGroup: 10001
  containers:
    - name: mssql$($currentSQLVersion)
      command:
        - /bin/bash
        - -c
        - cp /var/opt/config/mssql.conf /var/opt/mssql/mssql.conf && /opt/mssql/bin/sqlservr
      image: 'mcr.microsoft.com/mssql/server:20$($currentSQLVersion)-latest'
      resources:
        limits:
          memory: 8Gi
          cpu: '2'
      ports:
        - containerPort: 1433
      env:
        - name: ACCEPT_EULA
          value: 'Y'
        - name: MSSQL_ENABLE_HADR
          value: '1'
        - name: MSSQL_SA_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mssql$($currentSQLVersion)
              key: MSSQL_SA_PASSWORD
      volumeMounts:
        - name: mssql
          mountPath: /var/opt/mssql
        - name: userdata
          mountPath: /var/opt/mssql/userdata
        - name: userlog
          mountPath: /var/opt/mssql/userlog
        - name: backup
          mountPath: /var/opt/mssql/backup
        - name: tempdb
          mountPath: /var/opt/mssql/tempdb
        - name: mssql-config-volume
          mountPath: /var/opt/config
        - name: krb5-config-volume
          mountPath: /etc/krb5.conf
          subPath: krb5.conf
        - name: tls-certs
          mountPath: /var/opt/mssql/certs
        - name: tls-keys
          mountPath: /var/opt/mssql/private
    - name: dxe
      image: dh2i/dxe
      env:
      - name: MSSQL_SA_PASSWORD
        valueFrom:
          secretKeyRef:
            name: mssql$($currentSQLVersion)
            key: MSSQL_SA_PASSWORD
      volumeMounts:
      - name: dxe
        mountPath: /etc/dh2i
  hostAliases:
    - ip: "10.$Env:vnetIpAddressRangeStr.16.4"
      hostnames:
        - "sqlk8sdc.sqlk8s.local"
        - "sqlk8s.local"
        - "sqlk8s"
  volumes:
    - name: mssql-config-volume
      configMap:
        name: mssql$($currentSQLVersion)
    - name: krb5-config-volume
      configMap:
        name: krb5
volumeClaimTemplates:
- metadata:
    name: mssql
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
- metadata:
    name: userdata
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
- metadata:
    name: userlog
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
- metadata:
    name: backup
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
- metadata:
    name: tempdb
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 8Gi
- metadata:
    name: tls-certs
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
- metadata:
    name: tls-keys
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
- metadata:
    name: dxe
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
"@

$mssqlPodFile = "$Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\dxemssql.yaml"
$mssqlPodScript | Out-File -FilePath $mssqlPodFile -force    
kubectl apply -f $mssqlPodFile -n sql$($currentSQLVersion)    

Write-Host "$(Get-Date) - Installing SQL Server Pod Services"
$mssqlPodServiceScript = @"
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
#Unique name
name: mssql$($currentSQLVersion)-0-lb
annotations:
service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
type: LoadBalancer
loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).0
selector:
#Assign load balancer to a specific pod
statefulset.kubernetes.io/pod-name: mssql$($currentSQLVersion)-0
ports:
- name: sql
protocol: TCP
port: 1433
targetPort: 1433
- name: listener
protocol: TCP
port: 14033
targetPort: 14033
- name: dxe
protocol: TCP
port: 7979
targetPort: 7979
---
apiVersion: v1
kind: Service
metadata:
#Unique name
name: mssql$($currentSQLVersion)-1-lb
annotations:
service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
type: LoadBalancer
loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).1
selector:
#Assign load balancer to a specific pod
statefulset.kubernetes.io/pod-name: mssql$($currentSQLVersion)-1
ports:
- name: sql
protocol: TCP
port: 1433
targetPort: 1433
- name: listener
protocol: TCP
port: 14033
targetPort: 14033
- name: dxe
protocol: TCP
port: 7979
targetPort: 7979
---
apiVersion: v1
kind: Service
metadata:
#Unique name
name: mssql$($currentSQLVersion)-2-lb
annotations:
service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
type: LoadBalancer
loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).2
selector:
#Assign load balancer to a specific pod
statefulset.kubernetes.io/pod-name: mssql$($currentSQLVersion)-2
ports:
- name: sql
protocol: TCP
port: 1433
targetPort: 1433
- name: listener
protocol: TCP
port: 14033
targetPort: 14033
- name: dxe
protocol: TCP
port: 7979
targetPort: 7979
"@

$mssqlPodServiceFile = "$Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\pod-service.yaml"
$mssqlPodServiceScript | Out-File -FilePath $mssqlPodServiceFile -force    
kubectl apply -f $mssqlPodServiceFile -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Verifying pods and services started successfully"
$podsDeployed = 0
$servicesDeployed = 0
$attempts = 1
$maxAttempts = 60
while ((($podsDeployed -eq 0) -or ($servicesDeployed -eq 0)) -and ($attempts -le $maxAttempts)) {
    $pod0 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-0 -o jsonpath="{.status.phase}"
    $pod1 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-1 -o jsonpath="{.status.phase}"
    $pod2 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-2 -o jsonpath="{.status.phase}"
    if (($pod0 -eq "Running") -and ($pod1 -eq "Running") -and ($pod2 -eq "Running")) {
        $podsDeployed = 1
    }

    $service0 = kubectl get services -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-0-lb -o jsonpath="{.spec.loadBalancerIP}"
    $service1 = kubectl get services -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-1-lb -o jsonpath="{.spec.loadBalancerIP}"
    $service2 = kubectl get services -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-2-lb -o jsonpath="{.spec.loadBalancerIP}"
    if (($service0 -eq "10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).0") -and ($service1 -eq "10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).1") -and ($service2 -eq "10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).2")) {
        $servicesDeployed = 1
    }

    if ((($podsDeployed -eq 0) -or ($servicesDeployed -eq 0)) -and ($attempts -lt $maxAttempts)) {
        Write-Host "$(Get-Date) - Pods and Services are not yet available - Attempt $attempts out of $maxAttempts"
        Start-Sleep -Seconds 10
    }
    $attempts += 1
}
if ($podsDeployed -eq 0) {
    Write-Host "$(Get-Date) - Failed to start SQL Pods"
}
if ($servicesDeployed -eq 0) {
    Write-Host "$(Get-Date) - Failed to start SQL Services"
}

Write-Host "$(Get-Date) - Uploading keytab files to pods"
$kubectlDeploymentDir = $Env:DeploymentDir -replace 'C:\\', '\..\'
kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSQLVersion)\mssql_mssql$($currentSQLVersion)-0.keytab mssql$($currentSQLVersion)-0:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSQLVersion)
kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSQLVersion)\mssql_mssql$($currentSQLVersion)-1.keytab mssql$($currentSQLVersion)-1:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSQLVersion)
kubectl cp $kubectlDeploymentDir\keytab\SQL20$($currentSQLVersion)\mssql_mssql$($currentSQLVersion)-2.keytab mssql$($currentSQLVersion)-2:/var/opt/mssql/secrets/mssql.keytab -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Uploading logger.ini files to pods"
kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSQLVersion)\logger.ini" mssql$($currentSQLVersion)-0:/var/opt/mssql/logger.ini -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSQLVersion)\logger.ini" mssql$($currentSQLVersion)-1:/var/opt/mssql/logger.ini -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\yaml\SQL20$($currentSQLVersion)\logger.ini" mssql$($currentSQLVersion)-2:/var/opt/mssql/logger.ini -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Uploading TLS certificates to pods"
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-0.pem" mssql$($currentSQLVersion)-0:/var/opt/mssql/certs/mssql.pem -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-0.key" mssql$($currentSQLVersion)-0:/var/opt/mssql/private/mssql.key -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-1.pem" mssql$($currentSQLVersion)-1:/var/opt/mssql/certs/mssql.pem -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-1.key" mssql$($currentSQLVersion)-1:/var/opt/mssql/private/mssql.key -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-2.pem" mssql$($currentSQLVersion)-2:/var/opt/mssql/certs/mssql.pem -n sql$($currentSQLVersion)
kubectl cp "$kubectlDeploymentDir\certificates\SQL20$($currentSQLVersion)\mssql$($currentSQLVersion)-2.key" mssql$($currentSQLVersion)-2:/var/opt/mssql/private/mssql.key -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Updating SQL Server Configurations"
kubectl apply -f $Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\mssql-conf-encryption.yaml -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Deleting pods to apply new configurations"
kubectl delete pod mssql$($currentSQLVersion)-0 -n sql$($currentSQLVersion)
Start-Sleep -Seconds 5
kubectl delete pod mssql$($currentSQLVersion)-1 -n sql$($currentSQLVersion)
Start-Sleep -Seconds 5
kubectl delete pod mssql$($currentSQLVersion)-2 -n sql$($currentSQLVersion)

Write-Host "$(Get-Date) - Verifying pods restarted successfully"
$podsDeployed = 0
$attempts = 1
while (($podsDeployed -eq 0) -and ($attempts -le $maxAttempts)) {
    $pod0 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-0 -o jsonpath="{.status.phase}"
    $pod1 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-1 -o jsonpath="{.status.phase}"
    $pod2 = kubectl get pods -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-2 -o jsonpath="{.status.phase}"
    if (($pod0 -eq "Running") -and ($pod1 -eq "Running") -and ($pod2 -eq "Running")) {
        $podsDeployed = 1
    }

    if (($podsDeployed -eq 0) -and ($attempts -lt $maxAttempts)) {
        Write-Host "$(Get-Date) - Pods are not yet available - Attempt $attempts out of $maxAttempts"
        Start-Sleep -Seconds 10
    }
    $attempts += 1
}
if ($podsDeployed -eq 0) {
    Write-Host "$(Get-Date) - Failed to restart SQL Pods"
}
Start-Sleep -Seconds 10

Write-Host "$(Get-Date) - Creating Windows sysadmin login and Telegraf monitoring login"
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
SQLCMD -S "mssql$($currentSQLVersion)-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile
SQLCMD -S "mssql$($currentSQLVersion)-1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile
SQLCMD -S "mssql$($currentSQLVersion)-2.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile

# Configure High Availability
if ($Env:dH2iLicenseKey.length -eq 19) {
    Write-Header "$(Get-Date) - Configuring High Availability"

    Write-Host "$(Get-Date) - Licensing pods"
    $licenseSuccess = 0
    $attempts = 1
    while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
        $result = kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
        if ($result -eq "Result: License successfully set")	{
            $licenseSuccess = 1
        }
        
        if (($licenseSuccess -eq 0) -and ($attempts -lt $maxAttempts)) {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-0 - Attempt $attempts out of $maxAttempts"
            Start-Sleep -Seconds 10
        }
        $attempts += 1
    }
    if ($licenseSuccess -eq 0) {
        Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-0 - $result"
    }

    $licenseSuccess = 0
    $attempts = 1
    while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
        $result = kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-1 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
        if ($result -eq "Result: License successfully set")	{
            $licenseSuccess = 1
        }
        
        if (($licenseSuccess -eq 0) -and ($attempts -lt $maxAttempts)) {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-1 - Attempt $attempts out of $maxAttempts"
            Start-Sleep -Seconds 10
        }
        $attempts += 1
    }
    if ($licenseSuccess -eq 0) {
        Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-1 - $result"
    }
    
    $licenseSuccess = 0
    $attempts = 1
    while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
        $result = kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-2 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
        if ($result -eq "Result: License successfully set")	{
            $licenseSuccess = 1
        }
        
        if (($licenseSuccess -eq 0) -and ($attempts -lt $maxAttempts)) {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-2 - Attempt $attempts out of $maxAttempts"
            Start-Sleep -Seconds 10
        }
        $attempts += 1
    }
    if ($licenseSuccess -eq 0) {
        Write-Host "$(Get-Date) - Failed to obtain license for mssql$($currentSQLVersion)-2 - $result"
    }

    Write-Host "$(Get-Date) - Creating HA Cluster on mssql$($currentSQLVersion)-0"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli cluster-add-vhost mssql$($currentSQLVersion)-agl1 *127.0.0.1 mssql$($currentSQLVersion)-0

    Write-Host "$(Get-Date) - Getting encrypted password for sa"
    $saSecurePassword = kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli encrypt-text $Env:adminPassword

    Write-Host "$(Get-Date) - Creating Availability Group on mssql$($currentSQLVersion)-0"
    if ($currentSQLVersion == "19") {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli add-ags mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-0|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli add-ags mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-0|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0" "CONTAINED"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Setting the cluster passkey using admin password"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli cluster-set-secret-ex $Env:adminPassword

    Write-Host "$(Get-Date) - Enabling vhost lookup in DxEnterprise's global settings"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli set-globalsetting membername.lookup true

    Write-Host "$(Get-Date) - Joining mssql$($currentSQLVersion)-1 to cluster"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-1 -- dxcli join-cluster-ex mssql$($currentSQLVersion)-0 $Env:adminPassword

    Write-Host "$(Get-Date) - Joining mssql$($currentSQLVersion)-1 to the Availability Group"
    if ($currentSQLVersion == "19") {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-1 -- dxcli add-ags-node mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-1|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-1 -- dxcli add-ags-node mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-1|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Joining mssql$($currentSQLVersion)-2 to cluster"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-2 -- dxcli join-cluster-ex mssql$($currentSQLVersion)-0 $Env:adminPassword

    Write-Host "$(Get-Date) - Joining mssql$($currentSQLVersion)-2 to the Availability Group"
    if ($currentSQLVersion == "19") {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-2 -- dxcli add-ags-node mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-2|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
    }
    else {
        kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-2 -- dxcli add-ags-node mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 "mssql$($currentSQLVersion)-2|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"
        Start-Sleep -Seconds 30
    }

    Write-Host "$(Get-Date) - Creating Tunnel for Listener"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" mssql$($currentSQLVersion)-agl1

    Write-Host "$(Get-Date) - Setting the Listener Port to 14033"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli add-ags-listener mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 14033

    Write-Host "$(Get-Date) - Creating Load Balancer Service"
$mssqlListenerServiceScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
name: mssql$($currentSQLVersion)-cluster-lb
annotations:
service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
type: LoadBalancer
loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).3
selector:
app: mssql$($currentSQLVersion)
ports:
- name: sql
protocol: TCP
port: 1433
targetPort: 1433
- name: listener
protocol: TCP
port: 14033
targetPort: 14033
- name: dxe
protocol: TCP
port: 7979
targetPort: 7979
"@

    $mssqlListenerServiceFile = "$Env:DeploymentDir\yaml\SQL20$($currentSQLVersion)\service.yaml"
    $mssqlListenerServiceScript | Out-File -FilePath $mssqlListenerServiceFile -force
    kubectl apply -f $mssqlListenerServiceFile -n sql$($currentSQLVersion)

    Write-Host "$(Get-Date) - Verifying listener service started successfully"
    $listenerDeployed = 0
    $attempts = 1
    $maxAttempts = 60
    while (($listenerDeployed -eq 0) -and ($attempts -le $maxAttempts)) {
        $listenerService = kubectl get services -n sql$($currentSQLVersion) mssql$($currentSQLVersion)-cluster-lb -o jsonpath="{.spec.loadBalancerIP}"
        if ($listenerService -eq "10.$Env:vnetIpAddressRangeStr.$($vnetIpAddressRangeStr2).3") {
            $listenerDeployed = 1
        }

        if (($listenerDeployed -eq 0) -and ($attempts -lt $maxAttempts)) {
            Write-Host "$(Get-Date) - Listener Service is not yet available - Attempt $attempts out of $maxAttempts"
            Start-Sleep -Seconds 10
        }
        $attempts += 1
    }
    if ($listenerDeployed -eq 0) {
        Write-Host "$(Get-Date) - Failed to start Listener Service"
    }
    Start-Sleep -Seconds 10

    Write-Host "$(Get-Date) - Copying backup file to mssql$($currentSQLVersion)-0"
    kubectl cp $kubectlDeploymentDir\backups\AdventureWorks2019.bak mssql$($currentSQLVersion)-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql$($currentSQLVersion)

    Write-Host "$(Get-Date) - Restoring database backup to mssql$($currentSQLVersion)-0 and configuring for High Availability"
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
    SQLCMD -S "mssql$($currentSQLVersion)-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlRestoreFile

    Write-Host "$(Get-Date) - Adding database to Availability Group"
    kubectl exec -n sql$($currentSQLVersion) -c dxe mssql$($currentSQLVersion)-0 -- dxcli add-ags-databases mssql$($currentSQLVersion)-agl1 mssql$($currentSQLVersion)-ag1 AdventureWorks2019
}
