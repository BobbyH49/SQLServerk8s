# Configure Monitoring

[< Previous Module](../modules/sql.md) - **[Home](../README.md)** - Next Module \>

## Install and configure InfluxDB

For this solution, you will be using InfluxDB to store the metric data, Telegraf Agent to collect the data, and Grafana to visualise the metrics.

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. \<azureUser\>.sqlk8s.local)

2. Open Powershell

3. Login to Azure AD with an account that has ownership permissions to your subscription

    ```text
    az login
    ```

4. Create sqlmonitor namespace

    ```text
    kubectl create namespace sqlmonitor
    ```

5. Configure storage for InfluxDB

    ```text
    kubectl apply -f "C:\SQLServerk8s-main\yaml\SQLContainerDeployment\Monitor\InfluxDB\storage.yaml" --namespace sqlmonitor
    ```

6. Deploy InfluxDB

    ```text
    kubectl apply -f "C:\SQLServerk8s-main\yaml\SQLContainerDeployment\Monitor\InfluxDB\deployment.yaml" --namespace sqlmonitor
    ```

7. 
kubectl get pods -n sqlmonitor
kubectl expose deployment influxdb --port=8086 --target-port=8086 --protocol=TCP --type=ClusterIP --namespace sqlmonitor
kubectl apply -f "C:\SQLContainerDeployment\Monitoring\InfluxDB\service.yaml" --namespace sqlmonitor
kubectl get pods -n sqlmonitor
kubectl get services -n sqlmonitor

--Connect to InfluxDB using external ip address and port 8086
User = root
Password = root1234
Initial Organization = sqlmon
Initial Bucket = sqlmon

--Login and click Advanced to setup Telegraf
--Under Buckets click Add Data for sqlmon and select Configure Telegraf Agent
--Filter for SQL Server and then Continue Configuring
--Name the configuration sqlmon and then replace the servers connection string with the following for each server and click Save and Test
"Server=<sql-cluster-ip>;Port=1433;User Id=Telegraf;Password=L@bAdm1n1234;app name=telegraf;log=1;",
--Edit C:\SQLContainerDeployment\Monitoring\Telegraf\config.yaml and replace the server connection strings as above.
--Then change the influxdb_v2 url to http://<influxdb-cluster-ip:8086 and add the token provided by the influxdb web app
--Save and close
--Click Finish in the Web App

--Execute the following sql against the sql instances
USE master;
GO
CREATE LOGIN [Telegraf] WITH PASSWORD = N'L@bAdm1n1234';
GO
GRANT VIEW SERVER STATE TO [Telegraf];
GO
GRANT VIEW ANY DEFINITION TO [Telegraf];
GO

kubectl apply -f "C:\SQLContainerDeployment\Monitoring\Telegraf\config.yaml" --namespace sqlmonitor
kubectl apply -f "C:\SQLContainerDeployment\Monitoring\Telegraf\deployment.yaml" --namespace sqlmonitor
kubectl expose deployment telegraf --port=8125 --target-port=8125 --protocol=UDP --type=NodePort --namespace sqlmonitor
kubectl get pods -n sqlmonitor
kubectl get services -n sqlmonitor

--Go back to Buckets in the web app and select sqlmon
--Run this flux script

from(bucket: "sqlmon")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "sqlserver_performance")
  |> filter(fn: (r) => r["_field"] == "value")
  |> filter(fn: (r) => r["counter"] == "Page life expectancy")
  |> filter(fn: (r) => r["measurement_db_type"] == "SQLServer")
  |> filter(fn: (r) => r["object"] == "SQLServer:Buffer Node")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> yield(name: "mean")

--Go to API Tokens and create a new token to read sqlmon bucket

kubectl create secret generic grafana-creds --from-literal=GF_SECURITY_ADMIN_USER=admin --from-literal=GF_SECURITY_ADMIN_PASSWORD=admin1234 --namespace sqlmonitor
kubectl apply -f "C:\SQLContainerDeployment\Monitoring\Grafana\deployment.yaml" --namespace sqlmonitor
kubectl apply -f "C:\SQLContainerDeployment\Monitoring\Grafana\service.yaml" --namespace sqlmonitor
kubectl get pods -n sqlmonitor
kubectl get services -n sqlmonitor

--Connect to Grafana using external ip address and port 3000
User = admin
Password = admin1234

--Create InfluxDB datasource and then click Save & test
Query Language = Flux
Disable Basic Authentication
URL = http://<InfluxDB-cluster-ip>:8086
Organization = sqlmon
Token = <API Token>
Default Bucket = sqlmon

-- Go to explore and run the same flux query as above

kubectl delete service influxdb-lb -n sqlmonitor

