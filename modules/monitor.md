# Monitoring with InfluxDB and Grafana

[< Previous Module](../modules/hadr22.md) - **[Home](../README.md)** - [Next Module >](../modules/logins.md)

## Install and configure InfluxDB and Telegraf Agent

For this solution, you will be using InfluxDB to store the metric data, Telegraf Agent to collect the data, and Grafana to visualise the metrics.

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<azureUser\>.sqlk8s.local)

    ![Supply AD Credentials](media/SupplyADCredentials.jpg)

2. Open Powershell

    ![Open Powershell](media/OpenPowershell.jpg)

3. Login to Azure AD using the System Managed Identity for SqlK8sJumpbox

    ```text
    az login --identity
    ```

    ![Azure CLI SignedIn Powershell](media/AzureCLILogin.jpg)

4. Create sqlmonitor namespace

    ```text
    kubectl create namespace sqlmonitor
    ```

    ![Create sqlmonitor Namespace](media/CreateSQLMonitorNamespace.jpg)

5. Configure storage for InfluxDB

    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\InfluxDB\storage.yaml" -n sqlmonitor
    ```

    ![Configure InfluxDB Storage](media/ConfigureInfluxDBStorage.jpg)

6. Add configuration file for InfluxDB

    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\InfluxDB\config.yaml" -n sqlmonitor
    ```

    ![Configure InfluxDB Storage](media/AddInfluxDBConfig.jpg)

7. Deploy InfluxDB

    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\InfluxDB\deployment.yaml" -n sqlmonitor
    ```

    ![Deploy InfluxDB](media/DeployInfluxDB.jpg)

8. Expose internal IP Address and Port for InfluxDB

    ```text
    kubectl expose deployment influxdb --port=8086 --target-port=8086 --protocol=TCP --type=ClusterIP -n sqlmonitor
    ```

    ![Expose InfluxDB Service](media/ExposeInfluxDBService.jpg)

8=9. Create internal load balancer for InfluxDB

    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\InfluxDB\service.yaml" -n sqlmonitor
    ```

    ![Create InfluxDB Internal Load Balancer](media/CreateInfluxDbIlb.jpg)

10. Verify pod and services are running

    ```text
    kubectl get pods -n sqlmonitor
    ```

    ```text
    kubectl get services -n sqlmonitor
    ```

    ![Verify InfluxDB Pod and Services](media/VerifyInfluxDB.jpg)

11. Connect to InfluxDB via Edge (http://influxdb.sqlk8s.local:8086) and click **Get Started**

    ![Connect to InfluxDB](media/ConnectToInfluxDB.jpg)

12. Enter the following and click **Continue**

* User = \<adminUsername\>
* Password = \<adminPassword\>
* Initial Organization Name = sqlmon
* Initial Bucket Name = sqlmon

    ![InfluxDB Account Setup](media/InfluxDBAccount.jpg)

13. Click the **Advanced** button on the Complete page

    ![InfluxDB Advanced](media/InfluxDBAdvanced.jpg)

14. On the Load Data page, click the **Add Data** button in the sqlmon panel, then click **Configure Telegraf Agent**

    ![InfluxDB Buckets](media/InfluxDBBuckets.jpg)

15. Ensure the bucket says **sqlmon** and then filter for, and choose the **SQL Server** data source. Click **Continue Configuring**

    ![InfluxDB Config Telegraf for SQL](media/InfluxDBConfigureTelegrafSQL.jpg)

16. Make the following configuration changes

* Configuration Name = sqlmon
    
    Replace line 11 within the servers section and edit the ip address and password

    **NB: To get the ip address info for the sql pods run \"kubectl get services -n sql19\" and\/or \"kubectl get services -n sql22\"**

    ![Verify SQL 2019 Services](media/VerifySQLServices19.jpg)

    ![Verify SQL 2022 Services](media/VerifySQLServices22.jpg)

    For SQL Server 2019

    ```text
        "Server=<mssql19-0-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
        "Server=<mssql19-1-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
        "Server=<mssql19-2-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
    ```

    For SQL Server 2022

    ```text
        "Server=<mssql22-0-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
        "Server=<mssql22-1-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
        "Server=<mssql22-2-lb ClusterIP>;Port=1433;User Id=Telegraf;Password=<azurePassword>;app name=telegraf;log=1;",
    ```

    Copy the server entries because you will need them later (lines 11-13 for one instance or 11-16 for both) and then click **Save and Test**

    ![Edit InfluxDB Config](media/EditInfluxDBConfig.jpg)

17. Edit **C:\Deployment\yaml\Monitor\Telegraf\config.yaml** in notepad

    Replace lines 143-145 with the server configurations created in **Step 15**

    Edit line 89 and update the ip address in the URL with \<influxdb ClusterIP\>

    **NB: To get the ip address info for the influxdb pod run \"kubectl get services -n sqlmonitor\"**

    ![Verify InfluxDB Pod and Services](media/VerifyInfluxDB.jpg)

    Edit line 92 by adding the API Token (this is provided on the \"Test your Configuration\" page, copy everything after \"export INFLUX_TOKEN=\")

    ![Test InfluxDB Config](media/TestInfluxDBConfig.jpg)

    Save and close the file

    ![Telegraf Config Sources](media/TelegrafConfigSources.jpg)

    ![Telegraf Config Destination](media/TelegrafConfigDest.jpg)

18. Go back to the \"Test your Configuration\" page and click **Finish**

    ![Test InfluxDB Config](media/TestInfluxDBConfig.jpg)

19. Deploy the Telegraf configuration file

    ```text
        kubectl apply -f "C:\Deployment\yaml\Monitor\Telegraf\config.yaml" -n sqlmonitor
    ```

    ![Deploy Telegraf Config](media/DeployTelegrafConfig.jpg)

20. Deploy the Telegraf agent

    ```text
        kubectl apply -f "C:\Deployment\yaml\Monitor\Telegraf\deployment.yaml" -n sqlmonitor
    ```

    ![Deploy Telegraf](media/DeployTelegraf.jpg)

21. Explose the Telegraf agent service

    ```text
        kubectl expose deployment telegraf --port=8125 --target-port=8125 --protocol=UDP --type=NodePort -n sqlmonitor
    ```

    ![Expose Telegraf Service](media/ExposeTelegrafService.jpg)

22. Verify pod and service are running

    ```text
    kubectl get pods -n sqlmonitor
    ```

    ```text
    kubectl get services -n sqlmonitor
    ```

    ![Verify Telegraf Pod and Service](media/VerifyTelegraf.jpg)

23. Go back to the InfluxDB web app and select **Buckets** and then **sqlmon**

    ![Query sqlmon bucket](media/QueryBucket.jpg)

24. Verify data is being collected by replacing the contents of the flux script with the script below and then click **Run**

    ```text
    from(bucket: "sqlmon")
    |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
    |> filter(fn: (r) => r["_measurement"] == "sqlserver_performance")
    |> filter(fn: (r) => r["_field"] == "value")
    |> filter(fn: (r) => r["counter"] == "Page life expectancy")
    |> filter(fn: (r) => r["measurement_db_type"] == "SQLServer")
    |> filter(fn: (r) => r["object"] == "SQLServer:Buffer Node")
    |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
    |> yield(name: "mean")
    ```

    If you see data for **_measurement** of **sqlserver_performance** underneath the script then everything is running correctly

    ![Run Flux Query](media/RunFluxQuery.jpg)

25. Go to API Tokens from the left menu blade and click **Generate API Token** followed by **Custom API Token**

    ![API Tokens](media/APITokens.jpg)

    ![Generate API Token](media/GenerateAPIToken.jpg)

26. Click **Buckets** to expand the selection, then tick the **Read** box for **sqlmon** and click **Generate**

    ![Read sqlmon token](media/ReadBucketToken.jpg)

27. Copy the API Token to the clipboard and then paste into a notepad file to be used when configuring Grafana

    **NB: The Copy to Clipboard may not work.  If it doesn't then highlight the token and copy manually.**

    ![Copy sqlmon token](media/CopyToken.jpg)

## Install and configure Grafana

This solution currently creates Grafana as a pod on your AKS cluster but you could also set this up on central server

1. Create the credentials for Grafana as a secret

    ```text
    kubectl create secret generic grafana-creds --from-literal=GF_SECURITY_ADMIN_USER=admin --from-literal=GF_SECURITY_ADMIN_PASSWORD=admin1234 -n sqlmonitor
    ```

    ![Create Grafana Credentials](media/CreateGrafanaCredentials.jpg)

2. Deploy Grafana
    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\Grafana\deployment.yaml" -n sqlmonitor
    ```

    ![Deploy Grafana](media/DeployGrafana.jpg)

3. Deploy Internal Load Balancer for Grafana
    ```text
    kubectl apply -f "C:\Deployment\yaml\Monitor\Grafana\service.yaml" -n sqlmonitor
    ```

    ![Deploy Grafana Service](media/DeployGrafanaService.jpg)

4. Verify pod and service are running

    ```text
    kubectl get pods -n sqlmonitor
    ```

    ```text
    kubectl get services -n sqlmonitor
    ```

    ![Verify Grafana Pod and Service](media/VerifyGrafana.jpg)

5. Connect to Grafana via Edge (http://grafana.sqlk8s.local:3000)

    ![Verify to Grafana](media/ConnectToGrafana.jpg)

6. Login by using the credentials below and clicking **Log in**

* User = \<adminUsername\>
* Password = \<adminPassword\>

    ![Login to Grafana](media/LoginToGrafana.jpg)

7. On the \"Welcome to Grafana\" page click on the **Data Sources** panel where it says \"Add your first data source\"

    ![Grafana New Data Source](media/GrafanaNewDataSource.jpg)

8. Select **InfluxDB** from the list of sources

    ![Grafana InfluxDB Source](media/GrafanaInfluxDBSource.jpg)

9. Edit the data source and click **Save and test**

* Name = InfluxDB
* Query Language = Flux
* HTTP URL = http://\<influxdb ClusterIP\>:8086
* Auth Basic Auth = Disabled
* InfluxDB Details Organization = sqlmon
* InfluxDB Details Token = \<API Token with read permissions to sqlmon\>
* InfluxDB Details Default Bucket = sqlmon

    **NB: You should get a message saying \"datasource is working. 1 buckets found\"**

    ![Grafana Create Source 1](media/GrafanaCreateSource1.jpg)

    ![Grafana Create Source 2](media/GrafanaCreateSource2.jpg)

10. From the left menu blade select **Dashboards**

    ![Grafana Dashboards](media/GrafanaDashboards.jpg)

11. Click **New** followed by **New Dashboard**

    ![Grafana New Dashboard](media/GrafanaNewDashboard.jpg)

12. Underneath \"Start your new dashboard by adding a visualization\" click **Add visualization**

    ![Add Visualization](media/AddVisualization.jpg)

13. From the \"Select data source\" popup select **InfluxDB**

    ![Select InfluxDB Source](media/SelectInfluxDBSource.jpg)

14. Click **Apply** on the panel editor to take you to the empty dashboard and then click the dashboard settings button from the top tool bar

    ![Apply New Dashboard](media/ApplyNewDashboard.jpg)

    ![New Dashboard Settings](media/NewDashboardSettings.jpg)

15. Go to **JSON model** from the left settings blade and around line 25 you should find configurations for the influxdb data source.  Copy the uid and paste in notepad

    ![Copy Data Source Uid](media/CopyDataSourceUid.jpg)

16. Click **Close** at the top of screen and then go back to **Dashboards** from the left menu blade or breadcrumb

    **NB: You will be prompted to save or discard changes to your new dashboard.  Click Discard.**

    ![Discard Dashboard](media/DiscardDashboard.jpg)

17. Click **New** followed by **Import**

    ![Import Dashboard](media/ImportDashboard.jpg)

18. Drag and drop **C:\Deployment\yaml\Monitor\Grafana\Dashboard.json** into the upload panel and then click **Import**

    **NB: When the dashboard loads it will contain failure messages and none of the charts will display.  This is as expected.**

    ![Import Dashboard Form](media/ImportDashboardForm.jpg)

    ![Add Dashboard File](media/AddDashboardFile.jpg)

19. Click the **dashboard settings** button from the top menu bar and select **Variables** from the settings blade

    ![Import Dashboard Error](media/ImportDashboardError.jpg)

    ![Dashboard Variables](media/DashboardVariables.jpg)

20. Click on the **datasource** variable and populate the **Custom options - Values separated by comma** with the uid of the datasource, then click **Save dashboard** followed by **Save**

    ![Update Variable](media/UpdateVariable.jpg)

    ![Save Dashboard](media/SaveDashboardSettings.jpg)

21. Click **Close** to go back to the dashboard

    ![Close Dashboard Settings](media/CloseDashboardSettings.jpg)

22. Click the **Refresh dashboard** button and the dashboard should start working

    ![Refresh Dashboard](media/RefreshDashboard.jpg)

    ![Refreshed Dashboard](media/RefreshedDashboard.jpg)

23. Change between each of the hosts and view the charts for each

    ![Change Host](media/ChangeHost.jpg)

24. Try Running some problematic queries against the primary and monitor the performance

25. Try failing over and verifying performance on each pod

[Continue >](../modules/logins.md)
