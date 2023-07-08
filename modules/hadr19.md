# Create Always-on Availability Group

[< Previous Module](../modules/sql19.md) - **[Home](../README.md)** - [Next Module >](../modules/sql22.md)

## Install and configure Availability Group using DxEnterprise

For this solution, you will be using DxEnterprise which is a licensed product from DH2I.  For more information refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/.

The first thing you will need to do is obtain a license to use the DxEnterprise software.  For the purpose of testing / proof of concepts you can register and download a development license from https://dh2i.com/trial/.

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

4. Activate cluster licensing software (developer in this case) on each pod

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli activate-server <license key> --accept-eula
    ```

    ```text
    kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli activate-server <license key> --accept-eula
    ```

    ```text
    kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli activate-server <license key> --accept-eula
    ```

    ![Activate DXE License](media/ActivateDXELicense.jpg)

5. Add a VHost with the name of the listener on the first pod

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli cluster-add-vhost mssql19-agl1 *127.0.0.1 mssql19-0
    ```

    ![Add HA VHost](media/AddHaVHost.jpg)

6. Encrypt sa password for cluster software on the first pod (value returned will be \<EncryptedPassword\>)

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli encrypt-text <azurePassword>
    ```

    ![Encrypt sa Password](media/EncryptSAPassword.jpg)

7. Create the Availability Group on the first pod

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags mssql19-agl1 mssql19-ag1 "mssql19-0|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

    ![Create SQL Availability Group](media/CreateSqlAg.jpg)

8. Set the cluster passkey using \<azurePassword\> for consistency

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli cluster-set-secret-ex <azurePassword>
    ```

    ![Set Cluster Passkey](media/SetClusterPasskey.jpg)

9. Enable vhost lookup in DxEnterprise's global settings

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli set-globalsetting membername.lookup true
    ```

    ![Update DXE Global Settings](media/UpdateDxeGlobalSettings.jpg)

10. Join second pod to cluster

    ```text
    kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli join-cluster-ex mssql19-0 <azurePassword>
    ```

    ![Join Cluster Node 2](media/JoinClusterNode2.jpg)

11. Join second pod to Availability Group

    ```text
    kubectl exec -n sql19 -c dxe mssql19-1 -- dxcli add-ags-node mssql19-agl1 mssql19-ag1 "mssql19-1|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

    ![Join Availability Group Node 2](media/JoinAgNode2.jpg)

12. Join third pod to cluster

    ```text
    kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli join-cluster-ex mssql19-0 <azurePassword>
    ```

    ![Join Cluster Node 3](media/JoinClusterNode3.jpg)

13. Join third pod to Availability Group

    ```text
    kubectl exec -n sql19 -c dxe mssql19-2 -- dxcli add-ags-node mssql19-agl1 mssql19-ag1 "mssql19-2|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

    ![Join Availability Group Node 3](media/JoinAgNode3.jpg)

14. Set Availability Group listener port (14033)

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags-listener mssql19-agl1 mssql19-ag1 14033
    ```

    ![Set Listener Port](media/SetListenerPort.jpg)

15. Add loadbalancer for listener

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\service.yaml -n sql19
    ```

    ![Create Listener Internal Load Balancer](media/CreateListenerILB.jpg)

16. Use tunnels for faster connections to the listener

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" mssql19-agl1
    ```

    ![Create Tunnel for Listener](media/CreateListenerTunnel.jpg)

17. Check listener service is available

    ```text
    kubectl get services -n sql19
    ```

    ![Verify Listener Service](media/VerifyListenerService.jpg)

18. Copy AdventureWorks2019.bak to first pod

    ```text
    kubectl cp \..\SQLBackups\AdventureWorks2019.bak mssql19-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql19
    ```

    ![Upload AdventureWorks2019 Backup](media/UploadSqlBackup.jpg)

19. Open SQL Server Management Studio

    ![Open SQL Server Management Studio](media/OpenSSMS.jpg)

20. Connect to mssql19-0

    ![Connect to SQL Pods via Kerberos](media/ConnectSQLKerberos.jpg)


21. Restore AdventureWorks2019 using T-SQL

    ```text
    restore database AdventureWorks2019
    from disk = N'/var/opt/mssql/backup/AdventureWorks2019.bak'
    with
    move N'AdventureWorks2019' to N'/var/opt/mssql/userdata/AdventureWorks2019.mdf'
    , move N'AdventureWorks2019_log' to N'/var/opt/mssql/userlog/AdventureWorks2019_log.ldf'
    , recovery, stats = 10
    ```

    ![Restore AdventureWorks2019](media/RestoreDatabase.jpg)


22. Set the database recovery to full

    ```text
    alter database AdventureWorks2019 set recovery full
    ```

    ![Set AdventureWorks2019 Recovery Model](media/SetDatabaseRecoveryModel.jpg)

23. Take a fresh full backup

    ```text
    backup database AdventureWorks2019
    to disk = N'/var/opt/mssql/backup/AdventureWorks2019_Full_Recovery.bak'
    with format, init, compression, stats = 10
    ```

    ![Backup AdventureWorks2019](media/BackupDatabase.jpg)

24. Switch back to Powershell and add the database to Availability Group

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli add-ags-databases mssql19-agl1 mssql19-ag1 AdventureWorks2019
    ```

    ![Add AdventureWorks2019 to Availability Group](media/AddDatabaseToAg.jpg)

25. Verify Availability Group State

    ```text
    kubectl exec -n sql19 -c dxe mssql19-0 -- dxcli get-ags-detail mssql19-agl1 mssql19-ag1
    ```

    ![Verify Availability Group](media/VerifyAg.jpg)

26. Connect to the listener from SQL Server Management Studio (mssql19-agl1,14033 or mssql19-agl1.sqlk8s.local,14033) and verify that mssql19-0 is the primary pod

    ![Connect to SQL Listener via Kerberos](media/ConnectSQLListener.jpg)

    ![Connected to SQL Listener](media/ConnectedSQLListener.jpg)

27. Try failing over the database by deleting mssql19-0 and check which pod becomes the new primary by refreshing the listener

    ```text
    kubectl delete pod mssql19-0 -n sql19
    ```

    ![Failover and Verify Availability Group](media/FailoverVerifyAg.jpg)

    ![Listener Post Failover](media/ListenerPostFailover.jpg)

[Continue >](../modules/sql22.md)
