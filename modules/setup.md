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

* Azure Kubernetes Cluster (VM Scale Set with 1 Standard_D8s_v3 VM to reduce cost)

## Deploy Azure Resources (Deployment 1)

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Fsetup.json)

2. Complete the form and then click **Review + create**

3. Click **Create**

## Install dependencies

1. Connect to SqlK8sJumpbox using Bastion and credentials supplied during deployment

2. Open Powershell as Administrator

3. Install NuGet

    ```text
    Install-PackageProvider -Name NuGet -Force
    ```

4. Install Azure Powershell module (Az)

    ```text
    Install-Module Az -AllowClobber -Force
    ```

5.  Install Azure CLI

    For latest version go to https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli

    ```text
    $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi
    ```

    **Restart Powershell**

6.  Install Kubectl
    
    For latest version go to https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
    Example download using curl for version 1.24.0 

    ```text
    $ProgressPreference = 'SilentlyContinue'; mkdir C:\Kube; Invoke-WebRequest -Uri https://dl.k8s.io/release/v1.24.0/bin/windows/amd64/kubectl.exe -OutFile "C:\kube\kubectl.exe"
    ```

    Validate by running the following and comparing the two versions in SHA256 format

    ```text
    $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://dl.k8s.io/v1.24.0/bin/windows/amd64/kubectl.exe.sha256 -OutFile "C:\kube\kubectl.exe.sha256"
    CertUtil -hashfile C:\kube\kubectl.exe SHA256
    type C:\kube\kubectl.exe.sha256
    ```

    Ensure you are able to run Kubectl in **Powershell**

    ```text
    $env:Path += "C:\kube;"
    [Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
    ```

    **Restart Powershell**

    ```text
    kubectl version --client
    ```

7. Download and install [Putty](https://putty.org/) on SqlK8sJumpbox

8. Download and install [SQL Server Management Studio](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver16) on SqlK8sJumpbox

## Create Domain Controller

This script will install ADDS on SqlK8sDC and then promote it to a Domain Controller.  It will then create an OU called ComputersOU and make this the default OU for domain joined computers.

1. Open Powershell ISE as Administrator

2. Create a new script

3. Paste the contents of [ConfigureDC.ps1](https://raw.githubusercontent.com/BobbyH49/SQLServerk8s/Version1.0/scripts/ConfigureDC.ps1) into the empty Powershell script window and run script with the following parameters
    1. subscriptionId - Go to your deployed Resource Group to get the Subscription Id
    2. resourceGroup - The name of your new Resource Group
    3. location - The region used to deploy your resources (e.g. uksouth)
    4. azureUser & azurePassword - The credentials supplied during the azure deployment

4. You will be prompted to sign in using an Azure AD account (use one with owner permissions to the subscription)

**NB: The DNS server configured for the Virtual Network (SqlK8s-vnet) is 10.192.4.4 (SqlK8sDC).  However, the DNS server configured for the jumpbox (SqlK8sJumpbox) has been overridden to 168.63.129.16 (Azure DNS).  This was done to allow the dependencies to be downloaded using name resolution of public servers.  This script removes the override to allow the Jumpbox to join to the domain.**

5. Reboot SqlK8sJumpbox and re-open Powershell as Administrator

6. Verify that you can ping the SqlK8s.local domain

    ```text
    ping sqlk8s.local
    ```

## Join Jumpbox to the Domain

The DNS server configured for the Virtual Network (SqlK8s-vnet) is 10.192.4.4 (SqlK8sDC).  However, the DNS server configured for the jumpbox (SqlK8sJumpbox) is 168.63.129.16.  This was done to allow the dependencies to be downloaded using name resolution of public servers.  Before joining to the domain you will need to point DNS back to the Domain Controller and then create a Conditional Forwarder (prerequisite for the AKS cluster).

This script will join SqlK8sJumpbox to the SqlK8s.local domain and then reboot SqlK8sJumpbox.

1. Open Powershell ISE as Administrator

2. Create a new script

3. Paste the contents of [DCJoinJumpbox.ps1](https://raw.githubusercontent.com/BobbyH49/SQLServerk8s/Version1.0/scripts/DCJoinJumpbox.ps1) into the empty Powershell script window and run script with the following parameters
    1. subscriptionId - Go to your deployed Resource Group to get the Subscription Id
    2. resourceGroup - The name of your new Resource Group
    3. azureUser & azurePassword - The credentials supplied during the azure deployment

4. You will be prompted to sign in using an Azure AD account (use one with owner permissions to the subscription)




### 1.  Install Client Tools on Jumpbox

**To install the tools you will need to open Powershell as Administrator**

# Install NuGet and Powershell Az Module
#Write-Host "Installing NuGet"
#Install-PackageProvider -Name NuGet -Force
#Write-Host "Installing Az Module"
#Install-Module Az -AllowClobber -Force

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Faks.json)