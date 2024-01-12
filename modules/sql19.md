# Create SQL Server 2019 Container Instances

[< Previous Module](../modules/setup.md) - **[Home](../README.md)** - [Next Module >](../modules/hadr19.md)

## Install and configure SQL Server 2019 on Containers

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<adminUsername\>@sqlk8s.local)

    ![Supply AD Credentials](media/SupplyADCredentials.jpg)

2. Open Powershell

    ![Open Powershell](media/OpenPowershell.jpg)

3. Login to Azure AD using the System Managed Identity for SqlK8sJumpbox (**AKS** Platform only)

    ```text
    az login --identity
    ```

    ![Azure CLI SignedIn Powershell](media/AzureCLILogin.jpg)

4. Connect to your AKS Cluster in the scope of your \<resourceGroup\> and store the profile (**AKS** Platform only)

    ```text
    az aks get-credentials -n sqlk8saks -g <resourceGroup>
    ```

    ![Connect to AKS Cluster](media/ConnectAKSCluster.jpg)

5. Create SQL Namespace

    ```text
    kubectl create namespace sql19
    ```

    ![Create SQL Namespace](media/CreateSQLNamespace19.jpg)

6. Create headless services which will allow your SQL Server pods to connect to one another using hostnames

    **NB: Only applies to SQL Server Installs with Availabilty Groups**

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\headless-services.yaml -n sql19
    ```

    ![Create SQL Headless Services](media/CreateSQLHeadlessServices19.jpg)

7. Create secret for SQL Server sa password using \<adminPassword\> for consistency

    ```text
    kubectl create secret generic mssql19 --from-literal=MSSQL_SA_PASSWORD=<adminPassword> -n sql19
    ```

    ![Create sa password secret](media/CreateSAPassword19.jpg)

8. Apply the Kerberos configuration file

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\krb5-conf.yaml -n sql19
    ```

    ![Apply Kerberos Config](media/ApplyKerberosConfig19.jpg)

9. Apply the SQL Server Configuration

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\mssql-conf.yaml -n sql19
    ```

    ![Apply SQL Config](media/ApplySQLConfig19.jpg)

10. Apply StatefulSet configuration of SQL Server and install cluster software (dxe)

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\mssql.yaml -n sql19
    ```

    ![Create Stateful SQL Pods](media/CreateStatefulSQLPods19.jpg)

11. Add internal load balancers for each node

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\pod-service.yaml -n sql19
    ```

    ![Create Internal Load Balancer Services](media/CreateILBServices19.jpg)

12. Verify pods and services are up and running

    **NB: You will see one pod \/ service for Standalone instances and three pods \/ services for Availability Group setup**

    ```text
    kubectl get pods -n sql19
    ```

    ![Verify SQL Pods](media/VerifySQLPods19.jpg)

    ```text
    kubectl get services -n sql19
    ```

    ![Verify SQL Services](media/VerifySQLServices19.jpg)

13. Check pods by nodes (there are usually two pods per node)

    ```text
    kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName -n sql19
    ```

    ![Verify AKS Nodes](media/VerifyAKSNodes19.jpg)

14. Copy the keytab files to each pod

    Standalone setup

    ```text
    kubectl cp \..\Deployment\keytab\SQL2019\mssql_mssql19-0.keytab mssql19-0:/var/opt/mssql/secrets/mssql.keytab -n sql19
    ```

    Availability Group setup

    ```text
    kubectl cp \..\Deployment\keytab\SQL2019\mssql_mssql19-0.keytab mssql19-0:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp \..\Deployment\keytab\SQL2019\mssql_mssql19-1.keytab mssql19-1:/var/opt/mssql/secrets/mssql.keytab -n sql19
    kubectl cp \..\Deployment\keytab\SQL2019\mssql_mssql19-2.keytab mssql19-2:/var/opt/mssql/secrets/mssql.keytab -n sql19
    ```

    ![Upload Keytab Files](media/UploadKeytabFiles19.jpg)

15. Copy logger.ini files to each pod

    Standalone setup

    ```text
    kubectl cp "\..\Deployment\yaml\SQL2019\logger.ini" mssql19-0:/var/opt/mssql/logger.ini -n sql19
    ```

    Availability Group setup

    ```text
    kubectl cp "\..\Deployment\yaml\SQL2019\logger.ini" mssql19-0:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "\..\Deployment\yaml\SQL2019\logger.ini" mssql19-1:/var/opt/mssql/logger.ini -n sql19
    kubectl cp "\..\Deployment\yaml\SQL2019\logger.ini" mssql19-2:/var/opt/mssql/logger.ini -n sql19
    ```

    ![Upload Logger Files](media/UploadLoggerFiles19.jpg)

16. Copy TLS Certificate and Key files to each pod

    Standalone setup

    ```text
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-0.pem" mssql19-0:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-0.key" mssql19-0:/var/opt/mssql/private/mssql.key -n sql19
    ```

    Availability Group setup

    ```text
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-0.pem" mssql19-0:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-0.key" mssql19-0:/var/opt/mssql/private/mssql.key -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-1.pem" mssql19-1:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-1.key" mssql19-1:/var/opt/mssql/private/mssql.key -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-2.pem" mssql19-2:/var/opt/mssql/certs/mssql.pem -n sql19
    kubectl cp "\..\Deployment\certificates\SQL2019\mssql19-2.key" mssql19-2:/var/opt/mssql/private/mssql.key -n sql19
    ```

    ![Upload TLS Files](media/UploadTLSFiles19.jpg)

17. Update mssql-conf

    ```text
    kubectl apply -f C:\Deployment\yaml\SQL2019\mssql-conf-encryption.yaml -n sql19
    ```

    ![Update SQL Config](media/UpdateSQLConfig19.jpg)

18. Delete each pod so they are re-created with Kerberos and TLS correctly configured

    **NB: This also tests the High Availability of each SQL Server Instance before the availability group is implemented**

    Standalone setup

    ```text
    kubectl delete pod mssql19-0 -n sql19
    ```

    Availability Group setup

    ```text
    kubectl delete pod mssql19-0 -n sql19
    kubectl delete pod mssql19-1 -n sql19
    kubectl delete pod mssql19-2 -n sql19
    ```

    ![Delete SQL Pods](media/DeleteSQLPods19.jpg)

19. Verify pods are back up and running

    **NB: You will see one pod \/ service for Standalone instances and three pods \/ services for Availability Group setup**

    ```text
    kubectl get pods -n sql19
    ```

    ![Verify SQL Pods](media/VerifySQLPods19.jpg)

20. Open SQL Server Management Studio and connect to each of the SQL Containers using their Fully Qualified Domain Name (i.e. mssql19-0.sqlk8s.local, mssql19-1.sqlk8s.local, mssql19-2.sqlk8s.local) with SQL authentication (sa account and \<adminPassword\>).

    **NB: For Standalone setup you will just connect to mssql19-0.sqlk8s.local**

    ![Open SQL Server Management Studio](media/OpenSSMS.jpg)

    ![Connect to SQL Pods](media/ConnectSQLPods19.jpg)

    ![SQL Pods Connected](media/SQLPodsConnected19.jpg)

21. Open a T-SQL session on each pod (container) and create a Windows login for \<adminUsername\> with sysadmin permissions

    **NB: On the same sessions, create a SQL login for Telegraf which will be used later in the monitor section (using \<adminPassword\> for consistency)**

    ```text
    USE [master];
    GO

    CREATE LOGIN [SQLK8S\<adminUsername>] FROM WINDOWS;
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [SQLK8S\<adminUsername>];
    GO

    CREATE LOGIN [Telegraf] WITH PASSWORD = N'<adminPassword>', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;
    GRANT VIEW SERVER STATE TO [Telegraf];
    GRANT VIEW ANY DEFINITION TO [Telegraf];
    GO
    ```

    ![Create SQL Logins](media/CreateSQLLogins19.jpg)

22. You should now be able to login to each instance using Windows Authentication (SQLK8S\\\<adminUsername\>)

    ![Connect to SQL Pods via Kerberos](media/ConnectSQLKerberos19.jpg)

    ![SQL Pods Connected via Kerberos](media/SQLKerberosConnected19.jpg)

23. Open a T-SQL session on each pod (container) and confirm that Kerberos and TLS are configured correctly

    ```text
    SELECT
        session_id
        , net_transport
        , protocol_type
        , encrypt_option
        , auth_scheme
    FROM
        sys.dm_exec_connections
    WHERE
        session_id = @@SPID;
    GO
    ```

    ![Confirm Security Configurations](media/ConfirmSecurityConfigs19.jpg)

If you have opted for a Standalone SQL Server instance then go to the page on "[Create SQL Server 2022 Container Instances](./modules/sql22.md)" to install SQL Server 2022 or "[How to configure logins and users on SQL Server Availability Groups](./modules/logins.md)".  Otherwise hit **Continue** at the bottom of the page to move to the Availability Group configuration tutorial.

[Continue >](../modules/hadr19.md)
