# Create SQL Server 2019 Container Instances

[< Previous Module](../modules/kerberos.md) - **[Home](../README.md)** - [Next Module >](../modules/hadr19.md)

## Install and configure SQL Server 2019 on Containers

**NB: This page is all about installing and configuring the SQL Server Container Instances.  However, there are some prerequisites for the clustering technology which will also be configured.**

**DH2I is the clustering technology of choice.  For more information refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/.**

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<azureUser\>.sqlk8s.local)

    ![Supply AD Credentials](media/SupplyADCredentials.jpg)

2. Open Powershell

    ![Open Powershell](media/OpenPowershell.jpg)

3. Login to Azure AD with an account that has ownership permissions to your subscription

    ```text
    az login
    ```

    ![Azure CLI Signin](media/AzureCLISignin.jpg)

    ![Azure CLI SignedIn](media/AzureCLISignedIn.jpg)

    ![Azure CLI SignedIn Powershell](media/AzureCLISignedInPowershell.jpg)

4.	Configure your account to be in the scope of your subscription (get the \<subscriptionId\> from your Resource Group page)

    ```text
    az account set --subscription <subscriptionId>
    ```

    ![Azure CLI Set Subscription](media/AzureCLISetSubscription.jpg)

5. Connect to your AKS Cluster in the scope of your \<resourceGroup\> and store the profile

    ```text
    az aks get-credentials -n sqlk8saks -g <resourceGroup>
    ```

    ![Connect to AKS Cluster](media/ConnectAKSCluster.jpg)

6. Create SQL Namespace

    ```text
    kubectl create namespace sql19
    ```

    ![Create SQL Namespace](media/CreateSQLNamespace19.jpg)

7. Create headless services which will allow your SQL Server pods to connect to one another using hostnames

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\headless-services.yaml -n sql19
    ```

    ![Create SQL Headless Services](media/CreateSQLHeadlessServices19.jpg)

8. Create secret for SQL Server sa password using \<azurePassword\> for consistency

    ```text
    kubectl create secret generic mssql19 --from-literal=MSSQL_SA_PASSWORD=<azurePassword> -n sql19
    ```

    ![Create sa password secret](media/CreateSAPassword19.jpg)

9. Apply the Kerberos configuration file

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\krb5-conf.yaml -n sql19
    ```

    ![Apply Kerberos Config](media/ApplyKerberosConfig19.jpg)

10. Apply the SQL Server Configuration

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\mssql-conf.yaml -n sql19
    ```

    ![Apply SQL Config](media/ApplySQLConfig19.jpg)

11. Apply StatefulSet configuration of SQL Server and install cluster software (dxe)

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\dxemssql.yaml -n sql19
    ```

    ![Create Stateful SQL Pods](media/CreateStatefulSQLPods19.jpg)

12. Add internal load balancers for each node

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\pod-service.yaml -n sql19
    ```

    ![Create Internal Load Balancer Services](media/CreateILBServices19.jpg)

13. Verify pods and services are up and running

    ```text
    kubectl get pods -n sql19
    ```

    ![Verify SQL Pods](media/VerifySQLPods19.jpg)

    ```text
    kubectl get services -n sql19
    ```

    ![Verify SQL Services](media/VerifySQLServices19.jpg)

14. Check pods by nodes (there will be 2 nodes if you are only running one instance e.g. SQL 2019 or SQL 2022, but this could increase up to 4 nodes if running both)

    ```text
    kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName -n sql19
    ```

    ![Verify AKS Nodes](media/VerifyAKSNodes19.jpg)

15. Copy the keytab files (created in the kerberos module) to all 3 SQL Pods

    ```text
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql19-0.keytab mssql19-0:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql19-1.keytab mssql19-1:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql19-2.keytab mssql19-2:/var/opt/mssql/secrets/mssql.keytab -n sql19
    ```

    ![Upload Keytab Files](media/UploadKeytabFiles19.jpg)

16. Copy logger.ini files to all 3 SQL Pods

    ```text
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql19-0:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql19-1:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql19-2:/var/opt/mssql/logger.ini -n sql19
    ```

    ![Upload Logger Files](media/UploadLoggerFiles19.jpg)

17. Delete all 3 pods so they are re-created with Kerberos correctly configured

    **NB: This also tests the High Availability of each SQL Server Instance before the availability group is implemented**

    ```text
    kubectl delete pod mssql19-0 -n sql19
    kubectl delete pod mssql19-1 -n sql19
    kubectl delete pod mssql19-2 -n sql19
    ```

    ![Delete SQL Pods](media/DeleteSQLPods19.jpg)

18. Verify pods are back up and running

    ```text
    kubectl get pods -n sql19
    ```

    ![Verify SQL Pods](media/VerifySQLPods19.jpg)

19. Open SQL Server Management Studio and connect to each of the SQL Containers (i.e. mssql19-0, mssql19-1, mssql19-2) using SQL authentication (sa account and \<azurePassword\>)

    ![Open SQL Server Management Studio](media/OpenSSMS.jpg)

    ![Connect to SQL Pods](media/ConnectSQLPods19.jpg)

    ![SQL Pods Connected](media/SQLPodsConnected19.jpg)

20. Open a T-SQL session on each pod (container) and create a Windows login for \<azureUser\> with sysadmin permissions

    **NB: On the same sessions, create a SQL login for Telegraf which will be used later in the monitor section (using \<azurePassword\> for consistency)**

    ```text
    USE [master];
    GO

    CREATE LOGIN [SQLK8S\<azureUser>] FROM WINDOWS;
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [SQLK8S\<azureUser>];
    GO

    CREATE LOGIN [Telegraf] WITH PASSWORD = N'<azurePassword>';
    GRANT VIEW SERVER STATE TO [Telegraf];
    GRANT VIEW ANY DEFINITION TO [Telegraf];
    GO
    ```

    ![Create SQL Logins](media/CreateSQLLogins19.jpg)

21. You should now be able to login to all 3 instances using Windows Authentication (SQLK8S\\\<azureUser\>)

    ![Connect to SQL Pods via Kerberos](media/ConnectSQLKerberos19.jpg)

    ![SQL Pods Connected via Kerberos](media/SQLKerberosConnected19.jpg)

[Continue >](../modules/hadr19.md)
