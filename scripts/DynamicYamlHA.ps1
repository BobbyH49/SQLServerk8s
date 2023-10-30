Write-Host "$(Get-Date) - Generating dxemssql.yaml"
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
  name: mssql$($Env:currentSqlVersion)
  labels:
    app: mssql$($Env:currentSqlVersion)
spec:
  serviceName: mssql$($Env:currentSqlVersion)
  replicas: 3
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: mssql$($Env:currentSqlVersion)
  template:
    metadata:
      labels:
        app: mssql$($Env:currentSqlVersion)
    spec:
      securityContext:
        fsGroup: 10001
      containers:
        - name: mssql$($Env:currentSqlVersion)
          command:
            - /bin/bash
            - -c
            - cp /var/opt/config/mssql.conf /var/opt/mssql/mssql.conf && /opt/mssql/bin/sqlservr
          image: 'mcr.microsoft.com/mssql/server:20$($Env:currentSqlVersion)-latest'
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
                  name: mssql$($Env:currentSqlVersion)
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
                name: mssql$($Env:currentSqlVersion)
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
            name: mssql$($Env:currentSqlVersion)
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

$mssqlPodFile = "$Env:DeploymentDir\yaml\SQL20$($Env:currentSqlVersion)\dxemssql.yaml"
$mssqlPodScript | Out-File -FilePath $mssqlPodFile -force

Write-Host "$(Get-Date) - Generating pod-service.yaml"
$mssqlPodServiceScript = @"
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  #Unique name
  name: mssql$($Env:currentSqlVersion)-0-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($Env:vnetIpAddressRangeStr2).0
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($Env:currentSqlVersion)-0
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
  name: mssql$($Env:currentSqlVersion)-1-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($Env:vnetIpAddressRangeStr2).1
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($Env:currentSqlVersion)-1
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
  name: mssql$($Env:currentSqlVersion)-2-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($Env:vnetIpAddressRangeStr2).2
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($Env:currentSqlVersion)-2
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

$mssqlPodServiceFile = "$Env:DeploymentDir\yaml\SQL20$($Env:currentSqlVersion)\pod-service.yaml"
$mssqlPodServiceScript | Out-File -FilePath $mssqlPodServiceFile -force    

    Write-Host "$(Get-Date) - Generating service.yaml"
$mssqlListenerServiceScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  name: mssql$($Env:currentSqlVersion)-cluster-lb
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.$Env:vnetIpAddressRangeStr.$($Env:vnetIpAddressRangeStr2).3
  selector:
    app: mssql$($Env:currentSqlVersion)
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

    $mssqlListenerServiceFile = "$Env:DeploymentDir\yaml\SQL20$($Env:currentSqlVersion)\service.yaml"
    $mssqlListenerServiceScript | Out-File -FilePath $mssqlListenerServiceFile -force
