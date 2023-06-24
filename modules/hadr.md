# Create Always-on Availability Group

[< Previous Module](../modules/sql.md) - **[Home](../README.md)** - Next Module \>

## Install and configure Availability Group using DxEnterprise

For this solution, you will be using DxEnterprise which is a licensed product from DH2I.  For more information refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/.

The first thing you will need to do is obtain a license to use the DxEnterprise software.  For the purpose of testing / proof of concepts you can register and download a development license from https://dh2i.com/trial/.

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<azureUser\>.sqlk8s.local)

2. Open Powershell

3. Login to Azure AD with an account that has ownership permissions to your subscription

    ```text
    az login
    ```

4. Activate cluster licensing software (developer in this case) on each pod

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli activate-server <license key> --accept-eula
    ```

    ```text
    kubectl exec -n sql -c dxe mssql-1 -- dxcli activate-server <license key> --accept-eula
    ```

    ```text
    kubectl exec -n sql -c dxe mssql-2 -- dxcli activate-server <license key> --accept-eula
    ```

5. Add a VHost with the name of the listener on the first pod

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli cluster-add-vhost mssql-agl1 *127.0.0.1 mssql-0
    ```


6. Encrypt sa password for cluster software on the first pod (value returned will be \<EncryptedPassword\>)

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli encrypt-text <azurePassword>
    ```

7. Create the Availability Group on the first pod

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags mssql-agl1 mssql-ag1 "mssql-0|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

8. Set the cluster passkey using \<azurePassword\> for consistency

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli cluster-set-secret-ex <azurePassword>
    ```

9. Enable vhost lookup in DxEnterprise's global settings

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli set-globalsetting membername.lookup true
    ```

10. Join second pod to cluster

    ```text
    kubectl exec -n sql -c dxe mssql-1 -- dxcli join-cluster-ex mssql-0 <azurePassword>
    ```

11. Join second pod to Availability Group

    ```text
    kubectl exec -n sql -c dxe mssql-1 -- dxcli add-ags-node mssql-agl1 mssql-ag1 "mssql-1|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

12. Join third pod to cluster

    ```text
    kubectl exec -n sql -c dxe mssql-2 -- dxcli join-cluster-ex mssql-0 <azurePassword>
    ```

13. Join third pod to Availability Group

    ```text
    kubectl exec -n sql -c dxe mssql-2 -- dxcli add-ags-node mssql-agl1 mssql-ag1 "mssql-2|mssqlserver|sa|<EncryptedPassword>|5022|synchronous_commit|0"
    ```

14. Set Availability Group listener port (14033)

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags-listener mssql-agl1 mssql-ag1 14033
    ```

15. Add loadbalancer for listener

    ```text
    kubectl apply -f C:\SQLServerk8s-main\yaml\SQLContainerDeployment\SQL2019\service.yaml -n sql
    ```

16. Use tunnels for faster connections to the listener

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli add-tunnel listener true ".ACTIVE" "127.0.0.1:14033" ".INACTIVE,0.0.0.0:14033" mssql-agl1
    ```

17. Check listenser service is available

    ```text
    kubectl get services -n sql
    ```

18. Copy AdventureWorks2019.bak to first pod

    ```text
    kubectl cp \..\SQLBackups\AdventureWorks2019.bak mssql-0:/var/opt/mssql/backup/AdventureWorks2019.bak -n sql
    ```

19. Open SQL Server Management Studio

20. Connect to mssql-0

21. Restore AdventureWorks2019 using T-SQL

    ```text
    restore database AdventureWorks2019
    from disk = N'/var/opt/mssql/backup/AdventureWorks2019.bak'
    with
    move N'AdventureWorks2017' to N'/var/opt/mssql/userdata/AdventureWorks2019.mdf'
    , move N'AdventureWorks2017_log' to N'/var/opt/mssql/userlog/AdventureWorks2019_log.ldf'
    , recovery, stats = 10
    ```

22. Set the database recovery to full

    ```text
    alter database AdventureWorks2019 set recovery full
    ```

23. Take a fresh full backup

    ```text
    backup database AdventureWorks2019
    to disk = N'/var/opt/mssql/backup/AdventureWorks2019_Full_Recovery.bak'
    with format, init, compression, stats = 10
    ```

24. Switch back to Powershell and add the database to Availability Group

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli add-ags-databases mssql-agl1 mssql-ag1 AdventureWorks2019
    ```

25. Verify Availability Group State

    ```text
    kubectl exec -n sql -c dxe mssql-0 -- dxcli get-ags-detail mssql-agl1 mssql-ag1
    ```

26. Connect to the listener from SQL Server Management Studio (mssql-agl1) and verify that mssql-0 is the primary pod

26. Try failing over the database by deleting mssql-0 and check which pod becomes the new primary by refreshing the listener

    ```text
    kubectl delete service mssql-0 -n sql
    ```

Continue \>
