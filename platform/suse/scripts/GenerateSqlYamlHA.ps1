Write-Host "$(Get-Date) - Generating headless-services.yaml"
$mssqlHeadlessScript = @"
#Headless services for local connections/resolution
apiVersion: v1
kind: Service
metadata:
  name: mssql$($currentSqlVersion)-0
spec:
  clusterIP: None
  selector:
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-0
  ports:
  - name: dxl
    protocol: TCP
    port: 7979
  - name: dxc-tcp
    protocol: TCP
    port: 7980
  - name: dxc-udp
    protocol: UDP
    port: 7981
  - name: sql
    protocol: TCP
    port: 1433
  - name: listener
    protocol: TCP
    port: 14033
---
apiVersion: v1
kind: Service
metadata:
  name: mssql$($currentSqlVersion)-1
spec:
  clusterIP: None
  selector:
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-1
  ports:
  - name: dxl
    protocol: TCP
    port: 7979
  - name: dxc-tcp
    protocol: TCP
    port: 7980
  - name: dxc-udp
    protocol: UDP
    port: 7981
  - name: sql
    protocol: TCP
    port: 1433
  - name: listener
    protocol: TCP
    port: 14033
---
apiVersion: v1
kind: Service
metadata:
  name: mssql$($currentSqlVersion)-2
spec:
  clusterIP: None
  selector:
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-2
  ports:
  - name: dxl
    protocol: TCP
    port: 7979
  - name: dxc-tcp
    protocol: TCP
    port: 7980
  - name: dxc-udp
    protocol: UDP
    port: 7981
  - name: sql
    protocol: TCP
    port: 1433
  - name: listener
    protocol: TCP
    port: 14033
"@

$mssqlHeadlessFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\headless-services.yaml"
$mssqlHeadlessScript | Out-File -FilePath $mssqlHeadlessFile -force

Write-Host "$(Get-Date) - Generating mssql.yaml"
$mssqlPodScript = @"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mssql$($currentSqlVersion)
  labels:
    app: mssql$($currentSqlVersion)
spec:
  serviceName: mssql$($currentSqlVersion)
  replicas: 3
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: mssql$($currentSqlVersion)
  template:
    metadata:
      labels:
        app: mssql$($currentSqlVersion)
    spec:
      securityContext:
        fsGroup: 10001
      containers:
        - name: mssql$($currentSqlVersion)
          command:
            - /bin/bash
            - -c
            - cp /var/opt/config/mssql.conf /var/opt/mssql/mssql.conf && /opt/mssql/bin/sqlservr
          image: 'mcr.microsoft.com/mssql/server:20$($currentSqlVersion)-latest'
          resources:
            limits:
              memory: 12Gi
              cpu: '4'
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
                  name: mssql$($currentSqlVersion)
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
                name: mssql$($currentSqlVersion)
                key: MSSQL_SA_PASSWORD
          volumeMounts:
          - name: dxe
            mountPath: /etc/dh2i
      hostAliases:
        - ip: "192.168.0.1"
          hostnames:
            - "sqlk8sdc.sqlk8s.local"
            - "sqlk8s.local"
            - "sqlk8s"
      volumes:
        - name: mssql-config-volume
          configMap:
            name: mssql$($currentSqlVersion)
        - name: krb5-config-volume
          configMap:
            name: krb5
  volumeClaimTemplates:
    - metadata:
        name: mssql
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 8Gi
    - metadata:
        name: userdata
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 8Gi
    - metadata:
        name: userlog
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 8Gi
    - metadata:
        name: backup
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 8Gi
    - metadata:
        name: tempdb
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 8Gi
    - metadata:
        name: tls-certs
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 1Gi
    - metadata:
        name: tls-keys
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 1Gi
    - metadata:
        name: dxe
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: longhorn
        resources:
          requests:
            storage: 1Gi
"@

$mssqlPodFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\mssql.yaml"
$mssqlPodScript | Out-File -FilePath $mssqlPodFile -force

Write-Host "$(Get-Date) - Generating pod-service.yaml"
$mssqlPodServiceScript = @"
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  #Unique name
  name: mssql$($currentSqlVersion)-0-lb
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.$($internalIpAddressRangeStr).0
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-0
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
  name: mssql$($currentSqlVersion)-1-lb
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.$($internalIpAddressRangeStr).1
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-1
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
  name: mssql$($currentSqlVersion)-2-lb
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.$($internalIpAddressRangeStr).2
  selector:
    #Assign load balancer to a specific pod
    statefulset.kubernetes.io/pod-name: mssql$($currentSqlVersion)-2
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

$mssqlPodServiceFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\pod-service.yaml"
$mssqlPodServiceScript | Out-File -FilePath $mssqlPodServiceFile -force    

    Write-Host "$(Get-Date) - Generating service.yaml"
$mssqlListenerServiceScript = @"
#Example load balancer service
#Access for SQL server, AG listener, and DxE management
apiVersion: v1
kind: Service
metadata:
  name: mssql$($currentSqlVersion)-cluster-lb
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.$($internalIpAddressRangeStr).3
  selector:
    app: mssql$($currentSqlVersion)
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

    $mssqlListenerServiceFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\service.yaml"
    $mssqlListenerServiceScript | Out-File -FilePath $mssqlListenerServiceFile -force
