# Environment Setup

**[Home](../README.md)** - [Next Module >](../modules/kerberos.md)

## Prerequisites

* An [Azure account](https://azure.microsoft.com/free/) with an active subscription.
* Owner permissions within a Resource Group to create resources and manage role assignments.

## Azure Resources

The following resources will be deployed (expensive to keep running)

### Deployment 1

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)
* 3 Virtual Machines (Standard D2s v3)
    * SqlK8sDC (Domain Controller with 1 Nic and 1 OS Disk)
    * SqlK8sLinux (Linux server used to join AKS containers to domain with 1 Nic and 1 OS Disk)
    * SqlK8sJumpbox (Client used to run scripts with 1 Nic and 1 OS Disk)
* 4 Network Security Groups (1 for each subnet and 1 for Nic on SqlK8sJumpbox)
* 2 Public IP Addresses (1 for Bastion and 1 for Jumpbox)

### Deployment 2

* Azure Kubernetes Cluster (VM Scale Set with 1 Standard_D8s_v3 VM)

## Deploy Azure Resources

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Fsetup.json)

2. Connect to SqlK8sJumpbox using Bastion

3. Open Powershell as Administrator

4. Run the following command to install NuGet

    ```text
    Install-PackageProvider -Name NuGet -Force
    ```


## Create Domain Controller and Linux VM

### 1.  Install Client Tools on Jumpbox

**To install the tools you will need to open Powershell as Administrator**

# Install NuGet and Powershell Az Module
#Write-Host "Installing NuGet"
#Install-PackageProvider -Name NuGet -Force
#Write-Host "Installing Az Module"
#Install-Module Az -AllowClobber -Force

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Faks.json)