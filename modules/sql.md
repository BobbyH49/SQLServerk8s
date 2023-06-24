# Create SQL Server Container Instances

[< Previous Module](../modules/kerberos.md) - **[Home](../README.md)** - [Next Module >](../modules/hadr.md)

## Install and configure SQL Server on Containers

**NB: This page is all about installing and configuring the SQL Server Container Instances.  However, there are some prerequisites for the clustering technology which will also be configured.**

**DH2I is the clustering technology of choice.  For more information refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/.**

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
    az aks get-credentials -n sqlk8saks -g <Your Resource Group Name>
    ```

6. Create SQL Namespace

    ```text
    kubectl create namespace sql
    ```

7. Create headless services which will allow your SQL Server pods to connect to one another using hostnames

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\headless-services.yaml -n sql
    ```

8. Create secret for SQL Server sa password using \<azurePassword\> for consistency

    ```text
    kubectl create secret generic mssql --from-literal=MSSQL_SA_PASSWORD=<azurePassword> -n sql
    ```

9. Apply the Kerberos configuration file

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\krb5-conf.yaml -n sql
    ```

10. Apply the SQL Server Configuration

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\mssql-conf.yaml -n sql
    ```

11. Apply StatefulSet configuration of SQL Server and install cluster software (dxe)

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\dxemssql.yaml -n sql
    ```

12. Add internal load balancers for each node

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\pod-service.yaml -n sql
    ```

13. Verify pods and services are up and running

    ```text
    kubectl get pods -n sql
    ```

    ```text
    kubectl get services -n sql
    ```

14. Check pods by nodes (in this case there should only be 1 node)

    ```text
    kubectl get pod -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName -n sql
    ```

15. Copy the keytab files (created in the kerberos module) to all 3 SQL Pods

    ```text
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql-0.keytab mssql-0:/var/opt/mssql/secrets/mssql.keytab -n sql
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql-1.keytab mssql-1:/var/opt/mssql/secrets/mssql.keytab -n sql
    kubectl cp \..\SQLContainerDeployment\SQL2019\mssql_mssql-2.keytab mssql-2:/var/opt/mssql/secrets/mssql.keytab -n sql
    ```

16. Copy logger.ini files to all 3 SQL Pods

    ```text
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql-0:/var/opt/mssql/logger.ini -n sql
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql-1:/var/opt/mssql/logger.ini -n sql
    kubectl cp "\..\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\logger.ini" mssql-2:/var/opt/mssql/logger.ini -n sql
    ```

17. Delete all 3 pods so they are re-created with Kerberos correctly configured

    **NB: This also tests the High Availability of each SQL Server Instance before the availability group is implemented**

    ```text
    kubectl delete pod mssql-0 -n sql
    kubectl delete pod mssql-1 -n sql
    kubectl delete pod mssql-2 -n sql
    ```

18. Verify pods are back up and running

    ```text
    kubectl get pods -n sql
    ```

19. Open SQL Server Management Studio and connect to each of the SQL Containers (i.e. mssql-0, mssql-1, mssql-2) using SQL authentication (sa account and \<azurePassword\>)

20. Open a T-SQL session and create a Windows login for your \<azureUser\> on each Container with sysadmin permissions

    ```text
    create login [SQLK8S\<azureUser>] from windows
    alter server role sysadmin add member [SQLK8S\<azureUser>]
    ```

21. You should now be able to login to all 3 instances using Windows Authentication (SQLK8S\\\<azureUser\>)

[Continue >](../modules/hadr.md)
