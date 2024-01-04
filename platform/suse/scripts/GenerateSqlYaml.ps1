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
  replicas: 1
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
"@

$mssqlPodFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\mssql.yaml"
$mssqlPodScript | Out-File -FilePath $mssqlPodFile -force

Write-Host "$(Get-Date) - Generating pod-service.yaml"
$mssqlPodServiceScript = @"
#Access for SQL server
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
"@

$mssqlPodServiceFile = "$Env:DeploymentDir\yaml\SQL20$($currentSqlVersion)\pod-service.yaml"
$mssqlPodServiceScript | Out-File -FilePath $mssqlPodServiceFile -force    
