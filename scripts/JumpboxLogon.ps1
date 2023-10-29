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

# Install SQL Server 2019 Container
if ($Env:installSQL2019 -eq "Yes") {
    Write-Header "$(Get-Date) - Installing SQL Server 2019 Container"

    Write-Host "$(Get-Date) - Login to Azure"
    az login --identity

    Write-Host "$(Get-Date) - Connecting to $Env:aksCluster"
    az aks get-credentials -n $Env:aksCluster -g $Env:resourceGroup

    Write-Host "$(Get-Date) - Creating sql19 namespace"
    kubectl create namespace sql19

    Write-Host "$(Get-Date) - Creating Headless Services for SQL Pods"
    kubectl apply -f $Env:DeploymentDir\yaml\SQL2019\headless-services.yaml -n sql19

    Write-Host "$(Get-Date) - Setting sa password"
    kubectl create secret generic mssql19 --from-literal=MSSQL_SA_PASSWORD=$Env:adminPassword -n sql19

    Write-Host "$(Get-Date) - Applying kerberos configurations"
    kubectl apply -f $Env:DeploymentDir\yaml\SQL2019\krb5-conf.yaml -n sql19

    Write-Host "$(Get-Date) - Applying SQL Server configurations"
    kubectl apply -f $Env:DeploymentDir\yaml\SQL2019\mssql-conf.yaml -n sql19

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
  name: mssql19
  labels:
    app: mssql19
spec:
  serviceName: mssql19
  replicas: 3
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: mssql19
  template:
    metadata:
      labels:
        app: mssql19
    spec:
      securityContext:
        fsGroup: 10001
      containers:
        - name: mssql19
          command:
            - /bin/bash
            - -c
            - cp /var/opt/config/mssql.conf /var/opt/mssql/mssql.conf && /opt/mssql/bin/sqlservr
          image: 'mcr.microsoft.com/mssql/server:2019-latest'
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
                  name: mssql19
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
                name: mssql19
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
            name: mssql19
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

    $mssqlPodFile = "$Env:DeploymentDir\yaml\SQL2019\dxemssql.yaml"
    $mssqlPodScript | Out-File -FilePath $mssqlPodFile -force    
    kubectl apply -f $mssqlPodFile -n sql19    
    
    Write-Host "$(Get-Date) - Installing SQL Server Pod Services"
$mssqlPodServiceScript = @"
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  #Unique name
  name: mssql19-0-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.4.0
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql19-0
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
  name: mssql19-1-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.4.1
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql19-1
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
  name: mssql19-2-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.4.2
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql19-2
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

    $mssqlPodServiceFile = "$Env:DeploymentDir\yaml\SQL2019\pod-service.yaml"
    $mssqlPodServiceScript | Out-File -FilePath $mssqlPodServiceFile -force    
    kubectl apply -f $mssqlPodServiceFile -n sql19

    Write-Host "$(Get-Date) - Verifying pods and services started successfully"
    $podsDeployed = 0
    $servicesDeployed = 0
    $attempts = 1
    $maxAttempts = 60
    while ((($podsDeployed -eq 0) -or ($servicesDeployed -eq 0)) -and ($attempts -le $maxAttempts)) {
        $pod_mssql19_0 = kubectl get pods -n sql19 mssql19-0 -o jsonpath="{.status.phase}"
        $pod_mssql19_1 = kubectl get pods -n sql19 mssql19-1 -o jsonpath="{.status.phase}"
        $pod_mssql19_2 = kubectl get pods -n sql19 mssql19-2 -o jsonpath="{.status.phase}"
        if (($pod_mssql19_0 -eq "Running") -and ($pod_mssql19_1 -eq "Running") -and ($pod_mssql19_2 -eq "Running")) {
            $podsDeployed = 1
        }
    
        $service_mssql19_0 = kubectl get services -n sql19 mssql19-0-lb -o jsonpath="{.spec.loadBalancerIP}"
        $service_mssql19_1 = kubectl get services -n sql19 mssql19-1-lb -o jsonpath="{.spec.loadBalancerIP}"
        $service_mssql19_2 = kubectl get services -n sql19 mssql19-2-lb -o jsonpath="{.spec.loadBalancerIP}"
        if (($service_mssql19_0 -eq "10.$Env:vnetIpAddressRangeStr.4.0") -and ($service_mssql19_1 -eq "10.$Env:vnetIpAddressRangeStr.4.1") -and ($service_mssql19_2 -eq "10.$Env:vnetIpAddressRangeStr.4.2")) {
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
    kubectl cp $kubectlDeploymentDir\keytab\SQL2019\mssql_mssql19-0.keytab mssql19-0:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp $kubectlDeploymentDir\keytab\SQL2019\mssql_mssql19-1.keytab mssql19-1:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp $kubectlDeploymentDir\keytab\SQL2019\mssql_mssql19-2.keytab mssql19-2:/var/opt/mssql/secrets/mssql.keytab -n sql19

    Write-Host "$(Get-Date) - Uploading logger.ini files to pods"
    kubectl cp "$kubectlDeploymentDir\yaml\SQL2019\logger.ini" mssql19-0:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "$kubectlDeploymentDir\yaml\SQL2019\logger.ini" mssql19-1:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "$kubectlDeploymentDir\yaml\SQL2019\logger.ini" mssql19-2:/var/opt/mssql/logger.ini -n sql19

    Write-Host "$(Get-Date) - Uploading TLS certificates to pods"
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-0.pem" mssql19-0:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-0.key" mssql19-0:/var/opt/mssql/private/mssql.key -n sql19
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-1.pem" mssql19-1:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-1.key" mssql19-1:/var/opt/mssql/private/mssql.key -n sql19
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-2.pem" mssql19-2:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "$kubectlDeploymentDir\certificates\SQL2019\mssql19-2.key" mssql19-2:/var/opt/mssql/private/mssql.key -n sql19

    Write-Host "$(Get-Date) - Updating SQL Server Configurations"
    kubectl apply -f $Env:DeploymentDir\yaml\SQL2019\mssql-conf-encryption.yaml -n sql19

    Write-Host "$(Get-Date) - Deleting pods to apply new configurations"
    kubectl delete pod mssql19-0 -n sql19
    Start-Sleep -Seconds 5
    kubectl delete pod mssql19-1 -n sql19
    Start-Sleep -Seconds 5
    kubectl delete pod mssql19-2 -n sql19

    Write-Host "$(Get-Date) - Verifying pods restarted successfully"
    $podsDeployed = 0
    $attempts = 1
    $pod_mssql19_0 = ""
    $pod_mssql19_1 = ""
    $pod_mssql19_2 = ""
    while (($podsDeployed -eq 0) -and ($attempts -le $maxAttempts)) {
        $pod_mssql19_0 = kubectl get pods -n sql19 mssql19-0 -o jsonpath="{.status.phase}"
        $pod_mssql19_1 = kubectl get pods -n sql19 mssql19-1 -o jsonpath="{.status.phase}"
        $pod_mssql19_2 = kubectl get pods -n sql19 mssql19-2 -o jsonpath="{.status.phase}"
        if (($pod_mssql19_0 -eq "Running") -and ($pod_mssql19_1 -eq "Running") -and ($pod_mssql19_2 -eq "Running")) {
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
    SQLCMD -S "mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile
    SQLCMD -S "mssql19-1.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile
    SQLCMD -S "mssql19-2.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlLoginFile

    # Configure High Availability
    if ($Env:dH2iLicenseKey.length -eq 19) {
        Write-Header "$(Get-Date) - Configuring High Availability"

        Write-Host "$(Get-Date) - Licensing pods"
        $licenseSuccess = 0
        $attempts = 1
        while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
          try {
            Write-Host "$(Get-Date) - Obtaining license for mssql19-0 - Attempt $attempts"
            $ErrorActionPreference = "Stop"
            kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
            $licenseSuccess = 1
          }
          catch {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql19-0 - Attempt $attempts out of $maxAttempts"
            if ($attempts -lt $maxAttempts) {
              Start-Sleep -Seconds 10
            }
            else {
              Write-Host $Error[0]
            }
            $attempts += 1
          }
        }

        $licenseSuccess = 0
        $attempts = 1
        while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
          try {
            Write-Host "$(Get-Date) - Obtaining license for mssql19-1 - Attempt $attempts"
            $ErrorActionPreference = "Stop"
            kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
            $licenseSuccess = 1
          }
          catch {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql19-1 - Attempt $attempts out of $maxAttempts"
            if ($attempts -lt $maxAttempts) {
              Start-Sleep -Seconds 10
            }
            else {
              Write-Host $Error[0]
            }
            $attempts += 1
          }
        }

        $licenseSuccess = 0
        $attempts = 1
        while (($licenseSuccess -eq 0) -and ($attempts -le $maxAttempts)) {
          try {
            Write-Host "$(Get-Date) - Obtaining license for mssql19-2 - Attempt $attempts"
            $ErrorActionPreference = "Stop"
            kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli activate-server $Env:dH2iLicenseKey --accept-eula
            $licenseSuccess = 1
          }
          catch {
            Write-Host "$(Get-Date) - Failed to obtain license for mssql19-2 - Attempt $attempts out of $maxAttempts"
            if ($attempts -lt $maxAttempts) {
              Start-Sleep -Seconds 10
            }
            else {
              Write-Host $Error[0]
            }
            $attempts += 1
          }
        }
        $ErrorActionPreference = "Continue"

        Write-Host "$(Get-Date) - Creating HA Cluster on mssql19-0"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli cluster-add-vhost mssql19-agl1 *127.0.0.1 mssql19-0

        Write-Host "$(Get-Date) - Getting encrypted password for sa"
        $saSecurePassword = kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli encrypt-text $Env:adminPassword

        Write-Host "$(Get-Date) - Creating Availability Group on mssql19-0"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags mssql19-agl1 mssql19-ag1 "mssql19-0|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"

        Write-Host "$(Get-Date) - Setting the cluster passkey using admin password"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli cluster-set-secret-ex $Env:adminPassword

        Write-Host "$(Get-Date) - Enabling vhost lookup in DxEnterprise's global settings"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli set-globalsetting membername.lookup true

        Write-Host "$(Get-Date) - Joining mssql19-1 to cluster"
        kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli join-cluster-ex mssql19-0 $Env:adminPassword

        Write-Host "$(Get-Date) - Joining mssql19-1 to the Availability Group"
        kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli add-ags-node mssql19-agl1 mssql19-ag1 "mssql19-1|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"

        Write-Host "$(Get-Date) - Joining mssql19-2 to cluster"
        kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli join-cluster-ex mssql19-0 $Env:adminPassword

        Write-Host "$(Get-Date) - Joining mssql19-2 to the Availability Group"
        kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli add-ags-node mssql19-agl1 mssql19-ag1 "mssql19-2|mssqlserver|sa|$saSecurePassword|5022|synchronous_commit|0"

        Write-Host "$(Get-Date) - Creating Tunnel for Listener"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" mssql19-agl1

        Write-Host "$(Get-Date) - Setting the Listener Port to 14033"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags-listener mssql19-agl1 mssql19-ag1 14033

        Write-Host "$(Get-Date) - Creating Load Balancer Service"
$mssqlListenerServiceScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  name: mssql19-cluster-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.4.3
  selector:
    app: mssql19
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

        $mssqlListenerServiceFile = "$Env:DeploymentDir\yaml\SQL2019\service.yaml"
        $mssqlListenerServiceScript | Out-File -FilePath $mssqlListenerServiceFile -force
        kubectl apply -f $mssqlListenerServiceFile -n sql19

        Write-Host "$(Get-Date) - Verifying listener service started successfully"
        $listenerDeployed = 0
        $attempts = 1
        $maxAttempts = 60
        while (($listenerDeployed -eq 0) -and ($attempts -le $maxAttempts)) {
            $service_mssql19_agl1 = kubectl get services -n sql19 mssql19-cluster-lb -o jsonpath="{.spec.loadBalancerIP}"
            if ($service_mssql19_agl1 -eq "10.$Env:vnetIpAddressRangeStr.4.3") {
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

        Write-Host "$(Get-Date) - Copying backup file to mssql19-0"
        kubectl cp $kubectlDeploymentDir\backups\AdventureWorks2019.bak mssql19-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql19

        Write-Host "$(Get-Date) - Restoring database backup to mssql19-0 and configuring for High Availability"
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
        SQLCMD -S "mssql19-0.$($Env:netbiosName.toLower()).$Env:domainSuffix" -U sa -P $Env:adminPassword -i $sqlRestoreFile

        Write-Host "$(Get-Date) - Adding database to Availability Group"
        kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags-databases mssql19-agl1 mssql19-ag1 AdventureWorks2019
    }
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
