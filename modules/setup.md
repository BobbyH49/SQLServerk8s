# Environment Setup

**[Home](../README.md)** - [Next Module >](../modules/kerberos.md)

## Prerequisites

* An [Azure account](https://azure.microsoft.com/free/) with an active subscription.
* Owner permissions within a Resource Group to create resources and manage role assignments.

## Azure Resources

The following resources will be deployed

* Virtual Network (SqlK8s-vnet)
* 3 subnets (AKS, VMs, AzureBastionSubnet)
* Bastion Host (SqlK8s-bastion)

## Deploy Azure Resources

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Fsetup.json)

## Create Domain Controller and Linux VM

### 1.  Install Client Tools on Jumpbox

**To install the tools you will need to open Powershell as Administrator**

# Install NuGet and Powershell Az Module
#Write-Host "Installing NuGet"
#Install-PackageProvider -Name NuGet -Force
#Write-Host "Installing Az Module"
#Install-Module Az -AllowClobber -Force