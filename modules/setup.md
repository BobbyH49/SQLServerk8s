# Setup Environment with AKS Cluster using privatelink connections

**[Home](../README.md)** - [Next Module >](../modules/kerberos.md)

## Prerequisites

* An [Azure account](https://azure.microsoft.com/free/) with owner permissions on an active subscription.

## Full Deployment

The following resources will be deployed for full testing (expensive to keep running and takes around 40 minutes to deploy).

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 3 Virtual Machines (Standard D2s v3)
    * SqlK8sDC (Domain Controller with 1 Nic and 1 OS Disk)
    * SqlK8sLinux (Linux server used to join AKS containers to domain with 1 Nic and 1 OS Disk)
    * SqlK8sJumpbox (Client used to run scripts with 1 Nic and 1 OS Disk)
* 4 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)
* Azure Kubernetes Cluster (VM Scale Set with 2 - 3 Standard_D8s_v3 VMs)

    **NB: The Scale set has a minimum of 2 VMs to handle either of the SQL Server 2019 or 2022 deployments.  But it can scale to a maximum of 3 VMs if you wish to deploy both.** 

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2Foptimize_setup%2Ftemplates%2FFullsetup.json)

## Deploy without Domain Controller

The following resources will be deployed for testing without joining a domain.  However, a Linux VM will be created to setup channel encryption (expensive to keep running).

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 2 Virtual Machines (Standard D2s v3)
    * SqlK8sLinux (Linux server used to join AKS containers to domain with 1 Nic and 1 OS Disk)
    * SqlK8sJumpbox (Client used to run scripts with 1 Nic and 1 OS Disk)
* 4 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)
* Azure Kubernetes Cluster (VM Scale Set with 2 - 3 Standard_D8s_v3 VMs)

    **NB: The Scale set has a minimum of 2 VMs to handle either of the SQL Server 2019 or 2022 deployments.  But it can scale to a maximum of 3 VMs if you wish to deploy both.** 

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2Fmain%2Ftemplates%2FNoDCsetup.json)

## Deploy without Domain Controller or Linux Server

The following resources will be deployed for testing without joining a domain or configuring channel encryption (cheapest option).

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 1 Virtual Machine (Standard D2s v3)
    * SqlK8sJumpbox (Client used to run scripts with 1 Nic and 1 OS Disk)
* 4 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)
* Azure Kubernetes Cluster (VM Scale Set with 2 - 3 Standard_D8s_v3 VMs)

    **NB: The Scale set has a minimum of 2 VMs to handle either of the SQL Server 2019 or 2022 deployments.  But it can scale to a maximum of 3 VMs if you wish to deploy both.** 

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2Fmain%2Ftemplates%2FNoLinuxsetup.json)

## Deploy Azure Resources

1. Right-click or `Ctrl + click` the button that relates to your chosen deployment.  This will open the Azure Portal in a new window.

2. Complete the form and then click **Review + create**

    * 

    ![Deploy Resources](media/DeployResources.jpg)

3. Click **Create**

4. Your resources will take around 20-30 minutes to create

    ![Deployment Complete](media/DeploymentComplete.jpg)

5. Go to your new Resource group

    ![New Resource Group](media/NewResourceGroup.jpg)

6. Find and select your SqlK8sJumpbox Virtual Machine

    ![Connect to Jumpbox](media/ConnectToJumpbox.jpg)

7. Connect to SqlK8sJumpbox using Bastion and credentials supplied during deployment

    ![Connect via Bastion](media/ConnectViaBastion.jpg)

8. Enter the credentials you supplied on the Azure resource deployment template

    ![Supply Credentials](media/SupplyCredentials.jpg)

9. Accept the privacy settings

    ![Accept Privacy Settings](media/AcceptPrivacySettings.jpg)

10. Click on the desktop away from the Networks message

    ![Networks Message](media/NetworksMessage.jpg)

11. If you chose to do the Full deployment then a Powershell window will open.  Once the script has completed it will prompt you to press a key to reboot and then logon using the new domain credentials with the same password.  Follow these instructions to complete the setup process.

    ![Open Powershell](media/OpenPowershell.jpg)

[Continue >](../modules/kerberos.md)
