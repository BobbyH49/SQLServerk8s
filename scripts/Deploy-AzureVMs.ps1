#Last execution of the entire script (7 VMs) below took 30 minutes 

# Connect to Azure Subscription
# Create a new Resource Group
# Create a new Virtual Network with 3 subnets
# Create a new Windows Virtual Machine
# Create a new Network Security Group Rule
# Configure Bastion to connect to Azure Virtual Machine

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$subscriptionId = "9204f233-abf1-4491-ad9a-fffb219edbfa",
    [string]$resourceGroup = "SQLIaaSPoCRG",
    [string]$location = "uksouth"
)
function NewMessage 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $true)]
        [string]$type
    )
    if ($type -eq "success") {
        write-host $message -ForegroundColor Green
    }
    elseif ($type -eq "information") {
        write-host $message -ForegroundColor Yellow
    }
    elseif ($type -eq "error") {
        write-host $message -ForegroundColor Red
    }
    else {
        write-host "You need to pass message type as success/warning/error."
        Exit
    }
}

# Connect to Azure Subscription
function ConnectToAzure 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$subscriptionId
    )

    try {
        $check = Get-AzContext -ErrorAction SilentlyContinue
        if ($null -eq $check) {
            Connect-AzAccount -SubscriptionId $subscriptionId | out-null
        }
        else {
            Set-AzContext -SubscriptionId $subscriptionId | out-null
        }
    }
    catch {
        Write-Warning "Error occured = " $Error[0]
        Exit
    }
}

# Create a new Resource Group
function NewResourceGroup 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$location,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup
    )
    try {
            $message = ""
            $check = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $check) {
                New-AzResourceGroup -Name $resourceGroup -Location $location -ErrorAction SilentlyContinue  | out-null
                
                $message = $resourceGroup + " resource group has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = $resourceGroup + " resource group already exists." 
                NewMessage -message $message -type "information"    
            }
    }
    catch {
        Write-Warning "Error occured = " $Error[0]
    }
}

# Create a new Virtual Network
function NewVirtualNetwork 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$location,
        [Parameter(Mandatory = $true)]
        [string]$subnet0_name,
        [Parameter(Mandatory = $true)]
        [string]$subnet0_addressRange,
        [Parameter()]
        [string]$subnet1_name,
        [Parameter()]
        [string]$subnet1_addressRange,
        [Parameter()]
        [string]$subnetBastion_name,
        [Parameter()]
        [string]$subnetBastion_addressRange,
        [Parameter(Mandatory = $true)]
        [string]$virtualNetworkName,
        [Parameter(Mandatory = $true)]
        [string]$addressSpaces,
        [Parameter(Mandatory = $true)]
        [string]$dnsIPAddress
    )

    try {
            $message = ""
            $check = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $check) {
                # Create Frontend Subnet
                $Params = @{
                    Name = $subnet0_name
                    AddressPrefix = $subnet0_addressRange
                }
                $subnet0 = New-AzVirtualNetworkSubnetConfig @Params -ErrorAction SilentlyContinue
                
                # Create Backend Subnet
                $Params = @{
                    Name = $subnet1_name
                    AddressPrefix = $subnet1_addressRange
                }
                $subnet1  = New-AzVirtualNetworkSubnetConfig @Params -ErrorAction SilentlyContinue

                # Create Bastion Subnet
                $Params = @{
                    Name = $subnetBastion_name
                    AddressPrefix = $subnetBastion_addressRange
                }
                $bastionSubnet  = New-AzVirtualNetworkSubnetConfig @Params -ErrorAction SilentlyContinue

                # Create Virtual Network
                $Params = @{
                    Name = $virtualNetworkName
                    ResourceGroupName = $resourceGroup
                    Location = $location
                    AddressPrefix = $addressSpaces
                    DnsServer = $dnsIPAddress
                    Subnet = $subnet0,$subnet1,$bastionSubnet
                }
                New-AzVirtualNetwork @Params -ErrorAction SilentlyContinue | out-null

                $message = $virtualNetworkName + " virtual network has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = $virtualNetworkName + " virtual network already exists." 
                NewMessage -message $message -type "information"    
            }
    }
    catch {
        Write-Warning "Error occured = " $Error[0]
    }
}

# Create a new Windows Virtual Machine
function NewWindowsVM
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$location,
        [Parameter(Mandatory = $true)]
        [string]$networkInterfaceIpConfigName,
        [Parameter(Mandatory = $true)]
        [string]$privateIpAddressVersion,
        [Parameter(Mandatory = $true)]
        [string]$privateIPAddress,
        [Parameter(Mandatory = $true)]
        [string]$subnetName,
        [Parameter(Mandatory = $true)]
        [string]$networkInterfaceName,
        [Parameter(Mandatory = $true)]
        [string]$networkSecurityGroupName,
        [Parameter(Mandatory = $true)]
        [string]$virtualNetworkName,
        [Parameter(Mandatory = $true)]
        [string]$adminUsername,
        [Parameter(Mandatory = $true)]
        [string]$adminPassword,
        [Parameter(Mandatory = $true)]
        [string]$virtualMachineName,
        [Parameter(Mandatory = $true)]
        [string]$virtualMachineSize,
        [Parameter(Mandatory = $true)]
        [string]$vmPublisher,
        [Parameter(Mandatory = $true)]
        [string]$vmOfferName,
        [Parameter(Mandatory = $true)]
        [string]$vmSKUName
    )

    try {
            # Create a new network security group
            $message = ""
            $nsg = Get-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $nsg) {
                $Params = @{
                    ResourceGroupName = $resourceGroup
                    Location = $location
                    Name = $networkSecurityGroupName
                }
                $nsg = New-AzNetworkSecurityGroup @Params -ErrorAction SilentlyContinue

                $message = $networkSecurityGroupName + " network security group has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = $networkSecurityGroupName + " network security group already exists." 
                NewMessage -message $message -type "information"    
            }
            
            # Create a new network interface
            $message = ""
            $vNet = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            $Params = @{
                Name = $networkInterfaceIpConfigName
                PrivateIpAddressVersion = $privateIpAddressVersion
                PrivateIpAddress = $privateIPAddress
                SubnetId = ($vnet.Subnets | Where-Object {$_.Name -eq $subnetName}).Id
            }
            $IPconfig = New-AzNetworkInterfaceIpConfig @Params -ErrorAction SilentlyContinue

            $nic = Get-AzNetworkInterface -Name $networkInterfaceName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $nic) {
                $Params = @{
                    Name = $networkInterfaceName
                    ResourceGroupName = $resourceGroup
                    Location = $location
                    NetworkSecurityGroupId = $nsg.Id
                    IpConfiguration = $IPconfig
                }
                $nic = New-AzNetworkInterface @Params -ErrorAction SilentlyContinue
        
                $message = $networkInterfaceName + " network interface has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = $networkInterfaceName + " network interface already exists." 
                NewMessage -message $message -type "information"    
            }

            # Create a new windows virtual machine
            $message = ""
            $SecurePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $SecurePassword); 
            $check = Get-AzVM -Name $virtualMachineName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $check) {
                $newVM = New-AzVMConfig -VMName $virtualMachineName -VMSize $virtualMachineSize
                $newVM = Set-AzVMOperatingSystem -VM $newVM -Windows -ComputerName $virtualMachineName -Credential $credential -ProvisionVMAgent -EnableAutoUpdate
                $newVM = Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id
                $newVM = Set-AzVMSourceImage -VM $newVM -PublisherName $vmPublisher -Offer $vmOfferName -Skus $vmSKUName -Version "latest"
                
                New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $newVM -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | out-null

                $message = $virtualMachineName + " virtual machine has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = $virtualMachineName + " virtual machine already exists." 
                NewMessage -message $message -type "information"    
            }
    }
    catch {
        Write-Warning "Error occured = " $Error[0]
    }
}

# Create a new Network Security Group Rule
function NewNetworkSecurityGroupRule 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$networkSecurityGroupName,
        [Parameter(Mandatory = $true)]
        [string]$networkSecurityGroupRuleName,
        [Parameter(Mandatory = $true)]
        [string]$protocol,
        [Parameter(Mandatory = $true)]
        [string]$sourcePortRange,
        [Parameter(Mandatory = $true)]
        [string]$destinationPortRange,
        [Parameter(Mandatory = $true)]
        [string]$sourceAddressPrefix,
        [Parameter(Mandatory = $true)]
        [string]$destinationAddressPrefix,
        [Parameter(Mandatory = $true)]
        [string]$direction
    )

    try {

        $message = ""
        $check = Get-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroup | Get-AzNetworkSecurityRuleConfig -Name $networkSecurityGroupRuleName -ErrorAction SilentlyContinue
        if ($null -eq $check) {
            # Get the NSG resource
            $nsg = Get-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

            # Add the inbound security rule.
            $Params = @{
                Name = $networkSecurityGroupRuleName
                Access = "Allow"
                Protocol = $protocol
                Direction = $direction
                Priority = "100"
                SourceAddressPrefix = $sourceAddressPrefix
                SourcePortRange = $sourcePortRange
                DestinationAddressPrefix = $destinationAddressPrefix
                DestinationPortRange = $destinationPortRange
            }            
            $nsg | Add-AzNetworkSecurityRuleConfig @Params -ErrorAction SilentlyContinue | out-null

            # Update the NSG
            $nsg | Set-AzNetworkSecurityGroup | out-null

            $message = $networkSecurityGroupRuleName + " network security group rule has been created."
            NewMessage -message $message -type "success"
        }
        else {
            $message = $networkSecurityGroupRuleName + " network security group rule already exists." 
            NewMessage -message $message -type "information"    
        }

    }
    catch {
        #Write-Host "Error occured" -ForegroundColor Red
        $message = "Error occured."
        NewMessage -message $message -type "error" 
        Write-Warning "Error occured = " $Error[0]
    }
}

# Configure Bastion to connect to Azure Virtual Machine
function NewConnectionBastion 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$location,
        [Parameter(Mandatory = $true)]
        [string]$publicIPName,
        [Parameter(Mandatory = $true)]
        [string]$publicIPAllocationMethod,
        [Parameter(Mandatory = $true)]
        [string]$publicIPIdleTimeoutInMinutes,
        [Parameter(Mandatory = $true)]
        [string]$publicIPSKU,
        [Parameter(Mandatory = $true)]
        [string]$virtualNetworkName
    )

    try {
            # Create a public IP address
            $message = ""
            $publicIP = Get-AzPublicIpAddress -Name $publicIPName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $publicIP) {
                $Params = @{
                    ResourceGroupName = $resourceGroup
                    Location = $location
                    AllocationMethod = $publicIPAllocationMethod
                    IdleTimeoutInMinutes = $publicIPIdleTimeoutInMinutes
                    Name = $publicIPName
                    Sku = $publicIPSKU
                }   
                $publicIP = New-AzPublicIpAddress @Params -ErrorAction SilentlyContinue

                $message = $publicIPName + " public ip has been created."
                NewMessage -message $message -type "success"
            }

            # Create Bastion
            $message = ""
            $bastionHostsName = $virtualNetworkName + "_Bastion"
            $vNet = Get-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            $check = Get-AzBastion -Name $bastionHostsName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $check) {
                if (!($null -eq $vNet)) {
                    New-AzBastion -ResourceGroupName $resourceGroup -Name $bastionHostsName -PublicIpAddress $publicIP -VirtualNetwork $vNet | out-null

                    $message = $bastionHostsName + " resource has been created."
                    NewMessage -message $message -type "success"
                }
                else {
                    $message = $bastionHostsName + " resource has not been created because virtual network couldn't be found in the resource group." 
                    NewMessage -message $message -type "error"  
                    Exit
                }

            }
            else {
                $message = $bastionHostsName + " resource already exists." 
                NewMessage -message $message -type "information"    
            }
    }
    catch {
        Write-Warning "Error occured = " $Error[0]
    }
}

# Main Code
Write-Host "Deployment starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
ConnectToAzure -subscriptionId $subscriptionId

# Create a new Resource Group
$NewResourceGroupParams = @{
    location = $location
    resourceGroup = $resourceGroup
}
NewResourceGroup @NewResourceGroupParams

# Create a new Virtual Network with 3 subnets
$NewVirtualNetworkParams = @{
    resourceGroup = $resourceGroup
    location  = $location
    subnet0_name = "frontend"
    subnet0_addressRange = "10.10.20.0/24"
    subnet1_name = "backend"
    subnet1_addressRange = "10.10.21.0/25"
    subnetBastion_name = "AzureBastionSubnet" # This subnet is required for Bastion connection to Azure VM
    subnetBastion_addressRange = "10.10.21.128/27"
    virtualNetworkName = "VNet"
    addressSpaces = "10.10.20.0/23"
    dnsIPAddress = "10.10.21.10" # Set private IP address (privateIPAddress) of Domain Controller
}
NewVirtualNetwork @NewVirtualNetworkParams

# Common Parameters for Windows Virtual Machine
$commonWindowsVMParams = @{
    resourceGroup = $resourceGroup
    location = $location
    networkInterfaceIpConfigName = "IpConfig01"
    privateIpAddressVersion = "IPv4"
    virtualNetworkName = "VNet"
    adminUsername = "azadmin"
    adminPassword = "Microsoft123"
    virtualMachineSize = "Standard_D2s_v3"
    vmPublisher = "MicrosoftWindowsServer"
    vmOfferName = "WindowsServer"
    vmSKUName = "2019-Datacenter"
}

# Common Parameters for Windows Virtual Machine with SQL Server
$commonSQLVMParams = @{
    resourceGroup = $resourceGroup
    location = $location
    networkInterfaceIpConfigName = "IpConfig01"
    privateIpAddressVersion = "IPv4"
    virtualNetworkName = "VNet"
    adminUsername = "azadmin"
    adminPassword = "Microsoft123"
    virtualMachineSize = "Standard_D2s_v3"
    vmPublisher = "MicrosoftSQLServer"
    vmOfferName = "sql2019-ws2019"
    vmSKUName = "sqldev"
}

# Common Parameters for RDP rule in network security group
$commonNsgRdpParams = @{
    resourceGroup = $resourceGroup
    networkSecurityGroupRuleName = "AllowRDP"
    protocol = "TCP"
    sourcePortRange = "*"
    destinationPortRange = "3389"
    sourceAddressPrefix = "10.10.21.128/27" #subnetBastion_addressRange
    destinationAddressPrefix = "*"
    direction = "Inbound"
}

#################################################################################################
# # Create a new Windows Virtual Machine - DCVM01    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.10" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-dcvm01"
    networkSecurityGroupName = "nsg-dcvm01"
    virtualMachineName = "DCVM01"
}
NewWindowsVM @NewWindowsVMParams @commonWindowsVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-dcvm01" @commonNsgRdpParams
#################################################################################################
# Create a new Windows Virtual Machine - AlwaysOnN1    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.11" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-alwaysonn1"
    networkSecurityGroupName = "nsg-alwaysonn1"
    virtualMachineName = "AlwaysOnN1"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonn1" @commonNsgRdpParams
#################################################################################################
# # Create a new Windows Virtual Machine - AlwaysOnN2    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.12" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-alwaysonn2"
    networkSecurityGroupName = "nsg-alwaysonn2"
    virtualMachineName = "AlwaysOnN2"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonn2" @commonNsgRdpParams
#################################################################################################
# # Create a new Windows Virtual Machine - AlwaysOnN3    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.13" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-alwaysonn3"
    networkSecurityGroupName = "nsg-alwaysonn3"
    virtualMachineName = "AlwaysOnN3"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonn3" @commonNsgRdpParams
#################################################################################################
# # Create a new Windows Virtual Machine - AlwaysOnN4    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.14" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-alwaysonn4"
    networkSecurityGroupName = "nsg-alwaysonn4"
    virtualMachineName = "AlwaysOnN4"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonn4" @commonNsgRdpParams
#################################################################################################
# # Create a new Windows Virtual Machine - AlwaysOnN5    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.21.15" #IP address from backend
    subnetName = "backend"
    networkInterfaceName = "nic-alwaysonn5"
    networkSecurityGroupName = "nsg-alwaysonn5"
    virtualMachineName = "AlwaysOnN5"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonn5" @commonNsgRdpParams
#################################################################################################
# # Create a new Windows Virtual Machine - AlwaysOnClient    
$NewWindowsVMParams = @{
    privateIPAddress = "10.10.20.11" #IP address from frontend
    subnetName = "frontend"
    networkInterfaceName = "nic-alwaysonclient"
    networkSecurityGroupName = "nsg-alwaysonclient"
    virtualMachineName = "AlwaysOnClient"
}
NewWindowsVM @NewWindowsVMParams @commonSQLVMParams
# Create a new Network Security Group Rule RDP
NewNetworkSecurityGroupRule -networkSecurityGroupName "nsg-alwaysonclient" @commonNsgRdpParams
#################################################################################################
# Configure Bastion to connect to Azure Virtual Machine
$NewConnectionBastionParams = @{
    resourceGroup = $resourceGroup
    location  = $location
    publicIPName ="PublicIPBastion"
    publicIPAllocationMethod = "Static"
    publicIPIdleTimeoutInMinutes = "4"
    publicIPSKU = "Standard"
    virtualNetworkName = "VNet"
}
NewConnectionBastion @NewConnectionBastionParams

Write-Host "Deployment ends: $(Get-Date)"