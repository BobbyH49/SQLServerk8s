# Lab Setup with AKS or SLES Rancher RKE2 Kubernetes Cluster using privatelink connections

**[Home](../README.md)** - [Next Module >](../modules/sql19.md)

## Prerequisites

* An [Azure account](https://azure.microsoft.com/free/) with owner permissions on an active subscription.

## Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2Fmain%2Fplatform%2Fsetup.json)

**Current Issues :**
AKS Platform: Kerberos Authentication currently fails on SQL Server 2022 and is being investigated.
SUSE Platform: Kerberos Authentication currently fails on both SQL Server 2019 and 2022, and is being investigated.  Also, the firewall is currently disabled on all 3 SLES servers.

The following options are available as a SQL Server Kubernetes build on either Azure Kubernetes Service (AKS) or a Rancher RKE2 cluster built on top of 3 SLES 15 SP4 servers which you can port to an on-premise environment.  **You don't need a managed Kubernetes service to run this, you just need 3 VMs with SLES 15 SP4 installed and a copy of the scripts and templates from this Repository.**

1. Deploy lab environment including domain, kerberos authentication, and TLS certificates. You can then follow instructions on how to install a standalone instance of SQL Server 2019 and \/ or SQL Server 2022.
    1. Select **NO** for the **Install SQL 2019** and **Install SQL 2022** parameters
    2. Leave the **DH2i License Key** parameter blank
2. Deploy lab environment including domain, kerberos authenticion, and TLS certificates.  You can then follow instructions on how to install an Availability Group on SQL Server 2019 and \/ or a Contained Availability Group on SQL Server 2022 using DH2i\'s DxEnterprise Clustering solution (each contains 3 replicas).
    1. Select **NO** for the **Install SQL 2019** and **Install SQL 2022** parameters
    2. Add your **DH2i License Key**
3. Deploy a standalone SQL Server 2019 and \/ or SQL Server 2022 instance on an AKS Cluster.
    1. Select **Yes** for the **Install SQL 2019** and \/ or **Install SQL 2022** parameters
    2. Leave the **DH2i License Key** parameter blank
4. Deploy an Availability Group on SQL Server 2019 and \/ or a Contained Availability Group on SQL Server 2022 using DH2i\'s DxEnterprise Clustering solution (each contains 3 replicas).
    1. Select **Yes** for the **Install SQL 2019** and \/ or **Install SQL 2022** parameters
    2. Add your **DH2i License Key**

**NB: For the Always-on Availability Group solutions, you will be using DxEnterprise which is a licensed product from DH2i.  For more information refer to https://support.dh2i.com/docs/guides/dxenterprise/containers/kubernetes/mssql-ag-k8s-statefulset-qsg/.  The first thing you will need to do is obtain a license to use the DxEnterprise software.  For the purpose of testing / proof of concepts you can register and download a development license from https://dh2i.com/trial/.**

**NB: For SUSE deployment you will need to have a SLES 15 license.  You can obtain a trial license from https://www.suse.com/download/sles/.  This solution also includes Kubernetes mounted storage using Longhorn (https://longhorn.io/) as well as a Kubernetes load balancer using MetalLB (https://metallb.org/).**

The following resources will be deployed if you choose the AKS platform.  It takes around 30-40 minutes to deploy resources followed by between 5 minutes (no sql or monitoring deployed) and 30 minutes (all sql and monitoring deployed) to execute the SqlK8sJumpbox logon script.

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 3 Virtual Machines (Standard D2s v3)
    * SqlK8sDC (Domain Controller with 1 Nic and 1 OS Disk)
    * SqlK8sLinux (Linux server used to join AKS containers to domain with 1 Nic and 1 OS Disk)
    * SqlK8sJumpbox (Client used to run scripts with 1 Nic and 1 OS Disk)
* 4 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)
* Azure Kubernetes Cluster (VM Scale Set with 1 - 4 Standard_D8s_v3 VMs)

**NB: This deployment can be expensive to keep running but you can reduce costs by shutting down the 3 Virtual Machines and AKS Cluster, and starting up when required.  You can also drop the bastion host when shutting down the Virtual Machines and then re-create when required.**

**The Linux server (SqlK8sLinux) is not required once deployment has completed.  It can be permanently deleted.**

The following resources will be deployed if you choose the SLES 15 platform.  It takes around 10-15 minutes to deploy resources followed by between 25 minutes (no sql or monitoring deployed) and 45 minutes (all sql and monitoring deployed) to execute the SqlK8sJumpbox logon script.

* Virtual Network (SqlK8s-vnet)
* 2 subnets (VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 1 Virtual Machine (Standard_D48ls_v5)
    * SqlK8sJumpbox (Client, Domain Controller, and Hyper-V Server used to run scripts with 1 Nic, 1 OS Disk, and 3 Data Disks)
* 3 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)

**NB: This deployment can be expensive to keep running but you can reduce costs by shutting down the Virtual Machine, and starting up when required.  You can also drop the bastion host when shutting down the Virtual Machine and then re-create when required.**

## Deploy Azure Resources

1. Right-click or **Ctrl + click** the deploy button under [Deployment](#deployment).  This will open the Azure Portal in a new window.

2. Complete the form and then click **Review + create**

    * Subscription - Your Subscription
    * Resource group - New or existing Resource Group
    * Region - Region where you want all resources to be deployed
    * Admin Username - This will become the domain admin of the **SqlK8s** domain
    * Admin Password - This will become the password for your domain admin username
    * Github Branch - This should be left as **main** which will use the main branch from the Github repository
    * Ip Address Range_10.X.0.0 - A number between 0 and 255 to set the IP Address range of your network (default is 0 for 10.0.0.0, max is 255 for 10.255.0.0)
    * Install SQL2019 - Select **Yes** if you want SQL Server 2019 to be automatically installed
    * Install SQL2022 - Select **Yes** if you want SQL Server 2022 to be automatically installed
    * Install Monitoring - Select **Yes** if you want the Grafana monitoring solution to be installed
    * DH2i Availability Group - Select **Yes** to create a 3 node Availability Group (SQL Server 2019) and \/ or Contained Availability Group (SQL Server 2022), or select **No** to create standalone instance(s)
    * DH2i License Key - If you have selected **Yes** for **DH2i Availability Group**, then provide the DxEnterprise License Key, otherwise you can leave blank
    * Platform - Select **AKS** to create an Azure Kubernetes Service Cluster, or **SUSE** to create a Rancher RKE2 Kubernetes cluster on SLES 15 Servers
    * Suse License Key - If you have selected **SUSE** for **Platform**, then provide the SLES 15 License Key, otherwise you can leave blank

    ![Deploy Resources](media/DeployResources.jpg)

3. Click **Create**

    ![Deployment Complete](media/DeploymentComplete.jpg)

4. Go to **Outputs** and copy the **domainAdminUsername**

    ![Copy Domain Admin Username](media/CopyDomainAdminUsername.jpg)

5. Go to your new Resource group

    ![New Resource Group](media/NewResourceGroup.jpg)

6. Find and select your SqlK8sJumpbox Virtual Machine

    ![Connect to Jumpbox](media/ConnectToJumpbox.jpg)

7. Connect to SqlK8sJumpbox using Bastion

    ![Connect via Bastion](media/ConnectViaBastion.jpg)

8. Enter the credentials you supplied on the Azure resource deployment template (the user was copied in **Step 4**)

    ![Supply AD Credentials](media/SupplyADCredentials.jpg)

9. A Powershell window will open and setup the lab.  This can take between 5 minutes and 45 minutes depending on the options selected when deploying.  Once the script has completed, your lab environment should be ready.

    ![Jumbbox Logon Script](media/JumpboxLogonScript.jpg)

10. Should an error occur during the setup process you should be able to refer to the logs in **C:\Deployment\Logs**.  Collect the logs and raise a bug in the Github project.

The full lab setup consists of:

* SQL Server 2019 (login with windows \<adminUsername\> and \<adminPassword\> or sql sa and \<adminPassword\>)
    * mssql19-0.sqlk8s.local
    * mssql19-1.sqlk8s.local
    * mssql19-2.sqlk8s.local
    * mssql19-agl1.sqlk8s.local,14033
* SQL Server 2022 (login with windows \<adminUsername\> and \<adminPassword\> or sql sa and \<adminPassword\>)
    * mssql22-0.sqlk8s.local
    * mssql22-1.sqlk8s.local
    * mssql22-2.sqlk8s.local
    * mssql22-agl1.sqlk8s.local,14033
* SQL Server Monitoring
    * InfluxDB (URL http://influxdb.sqlk8s.local:8086 User \<adminUsername\> and Password \<adminPassword\>)
    * Telegraf Agent connected to InfluxDB
    * Grafana Dashboard (URL http://grafana.sqlk8s.local:3000 User \<adminUsername\> and Password \<adminPassword\>)
        
To access the Grafana dashboard, login and go to the home menu in the top left corner and select **Dashboards**.  From the dashboards window select **SQL Container Metrics**

If you have opted to automatically setup your SQL Server instances then go to the page on "[How to configure logins and users on SQL Server Availability Groups](../modules/logins.md)".  Otherwise hit **Continue** at the bottom of the page to move to the SQL Server 2019 installation tutorial or "[Create SQL Server 2022 Container Instances](./modules/sql22.md)" to install SQL Server 2022.

[Continue >](../modules/sql19.md)
