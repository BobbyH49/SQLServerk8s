# Environment Setup

**[Home](../README.md)** - [Next Module >](../modules/kerberos.md)

## Prerequisites

* An [Azure account](https://azure.microsoft.com/free/) with an active subscription.
* Owner permissions within a Resource Group to create resources and manage role assignments.

## Deploy Jumpbox

**The Jumpbox will allow you to install all of the client tools away from your client so you can clearly see the dependencies.  It will also sit on the same Virtual Network as your Domain Controller, Linux VM, and Kubernetes Cluster.  This will allow you to connect to each privately over Bastion Host.**

1. Right-click or `Ctrl + click` the button below to open the Azure Portal in a new window.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBobbyH49%2FSQLServerk8s%2FVersion1.0%2Ftemplates%2Fsetup.json)

## Create Domain Controller and Linux VM

### 1.  Install Client Tools on Jumpbox

**To install the tools you will need to open Powershell as Administrator**
