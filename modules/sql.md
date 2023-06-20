# Create SQL Server Container Instances

[< Previous Module](../modules/kerberos.md) - **[Home](../README.md)** - Next Module \>

## Install and configure SQL Server on Containers

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<azureUser\>.sqlk8s.local)

2. Open Powershell

3. Login to Azure AD with an account that has ownership permissions to your subscription

    ```text
    az login
    ```

4.	Configure your account to be in the scope of the subscription you will be using

    ```text
    az account set --subscription <Your Subscription Id>
    ```

5. Connect to your AKS Cluster and store the profile

    ```text
    az aks get-credentials -n sqlk8saks -g SqlServerK8sRG
    ```

6. Create SQL Namespace

    ```text
    kubectl create namespace sql
    ```

7. Copy the contents of [yaml/SQLContainerDeployment/SQL2019](https://github.com/BobbyH49/SQLServerk8s/blob/Version1.0/yaml/SQLContainerDeployment/SQL2019) to C:\SQLContainerDeployment\SQL2019 on SqlK8sJumpbox

8. Create headless services which will allow your SQL Server pods to connect to one another using hostnames

    **NB: This page is all about installing and configuring the SQL Server Container Instances.  However, there are some prerequisites for the clustering technology which will also be configured.**

    **All of the cluster commands come from dh2i which will be used as the clustering technology - refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/ for more information.**

    ```text
    kubectl apply -f C:\SQLContainerDeployment\SQL2019\headless-services.yaml -n sql
    ```


--Create secret for SQL Server sa password
kubectl create secret generic mssql --from-literal=MSSQL_SA_PASSWORD="L@bAdm1n1234" -n sql

--SQL Server Configuration
kubectl apply -f C:\SQLContainerDeployment\SQL2019AGDomain\krb5-conf.yaml -n sql
kubectl apply -f C:\SQLContainerDeployment\SQL2019AGDomain\mssql-conf.yaml -n sql

--Apply StatefulSet configuration of SQL Server and install cluster software (dxe)
kubectl apply -f C:\SQLContainerDeployment\SQL2019AGDomain\dxemssql.yaml -n sql

--Add load balancers for each node
kubectl apply -f C:\SQLContainerDeployment\SQL2019AGDomain\pod-service.yaml -n sql

--Check pods and services
kubectl get pods -n sql
kubectl get services -n sql

--Check pods by nodes
kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName -n sql

--Copy keytab files to 3 SQL Pods
kubectl cp \..\SQLContainerDeployment\SQL2019AGDomain\mssql_mssql-0.keytab mssql-0:/var/opt/mssql/secrets/mssql.keytab -n sql
kubectl cp \..\SQLContainerDeployment\SQL2019AGDomain\mssql_mssql-1.keytab mssql-1:/var/opt/mssql/secrets/mssql.keytab -n sql
kubectl cp \..\SQLContainerDeployment\SQL2019AGDomain\mssql_mssql-2.keytab mssql-2:/var/opt/mssql/secrets/mssql.keytab -n sql

--Copy logger.ini files to 3 SQL Pods
kubectl cp "\..\SQLContainerDeployment\SQL2019AGDomain\logger.ini" mssql-0:/var/opt/mssql/logger.ini -n sql
kubectl cp "\..\SQLContainerDeployment\SQL2019AGDomain\logger.ini" mssql-1:/var/opt/mssql/logger.ini -n sql
kubectl cp "\..\SQLContainerDeployment\SQL2019AGDomain\logger.ini" mssql-2:/var/opt/mssql/logger.ini -n sql

--If SSPI error still occurs then delete all 3 SQL Pods so they are re-created
kubectl delete pod mssql-0 -n sql
kubectl delete pod mssql-1 -n sql
kubectl delete pod mssql-2 -n sql

--Connect to SQL using SSMS and run the following under the sa account on all 3 nodes
create login [SQLLAB\azureuser] from windows
alter server role sysadmin add member [SQLLAB\azureuser]

--Activate cluster licensing software (developer in this case)
kubectl exec -n sql -c dxe mssql-0 -- dxcli activate-server DC16-ESUF-76VG-31GP --accept-eula

--Add a VHost
kubectl exec -n sql -c dxe mssql-0 -- dxcli cluster-add-vhost agl1 *127.0.0.1 mssql-0

--Encrypt sa password for cluster software
kubectl exec -n sql -c dxe mssql-0 -- dxcli encrypt-text L@bAdm1n1234

--Create AG
kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags agl1 ag1 "mssql-0|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"

--Set cluster passkey
kubectl exec -n sql -c dxe mssql-0 -- dxcli cluster-set-secret-ex L@bAdm1n1234

--Enable vhost lookup in DxEnterprise's global settings
kubectl exec -n sql -c dxe mssql-0 -- dxcli set-globalsetting membername.lookup true

--Activate license on second pod
kubectl exec -n sql -c dxe mssql-1 -- dxcli activate-server DC16-ESUF-76VG-31GP --accept-eula

--Join second pod to cluster
kubectl exec -n sql -c dxe mssql-1 -- dxcli join-cluster-ex mssql-0 L@bAdm1n1234

--Join second pod to AG
kubectl exec -n sql -c dxe mssql-1 -- dxcli add-ags-node agl1 ag1 "mssql-1|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"

--Activate license on third pod
kubectl exec -n sql -c dxe mssql-2 -- dxcli activate-server DC16-ESUF-76VG-31GP --accept-eula

--Join third pod to cluster
kubectl exec -n sql -c dxe mssql-2 -- dxcli join-cluster-ex mssql-0 L@bAdm1n1234

--Join third pod to AG
kubectl exec -n sql -c dxe mssql-2 -- dxcli add-ags-node agl1 ag1 "mssql-2|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"

--Set AG listener port
kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags-listener agl1 ag1 14033

--Add loadbalancer for listener
kubectl apply -f C:\SQLContainerDeployment\SQL2019AGDomain\service.yaml -n sql

--Use Tunnels for Faster Connections to the Listener
kubectl exec -n sql -c dxe mssql-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" agl1

--Vew services
kubectl get services -n sql

--Copy database to pod 1
kubectl cp \..\SQLBackups\AdventureWorks2019.bak mssql-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql

--Restore database
restore database AdventureWorks2019
from disk = N'/var/opt/mssql/backup/AdventureWorks2019.bak'
with
move N'AdventureWorks2017' to N'/var/opt/mssql/userdata/AdventureWorks2019.mdf'
, move N'AdventureWorks2017_log' to N'/var/opt/mssql/userlog/AdventureWorks2019_log.ldf'
, recovery, stats = 10

--Set recovery to full
alter database AdventureWorks2019 set recovery full

--Take a fresh full backup
backup database AdventureWorks2019
to disk = N'/var/opt/mssql/backup/AdventureWorks2019_v2.bak'
with format, init, stats = 10

--Add database to AG
kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags-databases agl1 ag1 AdventureWorks2019

--Verify AG State
kubectl exec -n sql -c dxe mssql-0 -- dxcli get-ags-detail agl1 ag1

Continue \>
