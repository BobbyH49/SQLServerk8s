# SQL Server 2019 and 2022 on Azure Kubernetes Service (AKS) or SLES Rancher RKE2 Kubernetes Cluster

The following topics are covered

* [Lab Setup](./modules/setup.md)
* SQL Server 2019 with Always-On Availability Groups (Manual Deployment)
    * [Create SQL Server 2019 Container Instances](./modules/sql19.md)
    * [Create Always-on Availability Group](./modules/hadr19.md)
* SQL Server 2022 with Always-on Contained Availability Groups (Manual Deployment)
    * [Create SQL Server 2022 Container Instances](./modules/sql22.md)
    * [Create Always-on Contained Availability Group](./modules/hadr22.md)
* [Monitoring with InfluxDB and Grafana](./modules/monitor.md) (Manual Deployment)
* [How to configure logins and users on SQL Server Availability Groups](./modules/logins.md)

Please view the following recordings for more info

* [SQLServerk8s Project Review](https://www.youtube.com/watch?v=kmFJfY_0ces)
* [Migration of SQL Server 2022 Instances from Windows to Kubernetes using Contained Availability Group](https://www.youtube.com/watch?v=B_zUgvAsDlo)
