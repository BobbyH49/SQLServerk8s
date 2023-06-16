#Last execution of the entire script (7 VMs) below took 40 minutes 

# Connect to Azure Subscription
# Enable Firewall Rule
# Install Active Directory Domain Services
# Configure Active Directory Domain
# Create a new Active Directory Organization Unit and make it default for computer objects
# Join Azure VM to domain
# Add Firewall Rule

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$location,
    [Parameter(Mandatory = $true)]
    [string]$azureUser,
    [Parameter(Mandatory = $true)]
    [SecureString]$azurePassword
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

# Enable Firewall Rule
function EnableFirewallRule 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\EnableFirewallRule.ps1"

            $commands = "Enable-NetFirewallRule -DisplayName ""File and Printer Sharing (Echo Request - ICMPv4-In)"""
            $commands | Out-File -FilePath $file -force

            $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file

            if ($result.Status -eq "Succeeded") {
                $message = "Firewall rule has been enabled on $vmName."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Firewall rule couldn't be enabled on $vmName."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        Write-Warning "Error occured = " $Error[0]
    }
}

# Install Active Directory Domain Services
function InstallADDS 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\InstallADDS.ps1"

            $commands = "#Install AD DS feature" + "`r`n"
            $commands = $commands + "Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Restart" + "`r`n"

            $commands | Out-File -FilePath $file -force

            $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file

            if ($result.Status -eq "Succeeded") {
                $message = "Active Directory has been enabled on $vmName."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory couldn't be enabled on $vmName."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        Write-Warning "Error occured = " $Error[0]
    }
}   

# Configure Active Directory Domain
function ConfigureADDS 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$adminPassword
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\ConfigureADDS.ps1"

            $commands = "`$SecurePassword = ConvertTo-SecureString ""$adminPassword"" -AsPlainText -Force" + "`r`n"
            $commands = $commands + "`r`n"
            $commands = $commands + "#AD DS Deployment" + "`r`n"
            $commands = $commands + "Import-Module ADDSDeployment" + "`r`n"
            $commands = $commands + "Install-ADDSForest ``" + "`r`n"
            $commands = $commands + "-CreateDnsDelegation:`$false ``" + "`r`n"
            $commands = $commands + "-DatabasePath ""C:\Windows\NTDS"" ``" + "`r`n"
            $commands = $commands + "-DomainMode ""WinThreshold"" ``" + "`r`n"
            $commands = $commands + "-DomainName ""sqlk8s.local"" ``" + "`r`n"
            $commands = $commands + "-DomainNetbiosName ""SQLK8S"" ``" + "`r`n"
            $commands = $commands + "-ForestMode ""WinThreshold"" ``" + "`r`n"
            $commands = $commands + "-InstallDns:`$true ``" + "`r`n"
            $commands = $commands + "-LogPath ""C:\Windows\NTDS"" ``" + "`r`n"
            $commands = $commands + "-NoRebootOnCompletion:`$false ``" + "`r`n"
            $commands = $commands + "-SafeModeAdministratorPassword `$SecurePassword ``" + "`r`n"
            $commands = $commands + "-SysvolPath ""C:\Windows\SYSVOL"" ``" + "`r`n"
            $commands = $commands + "-Force:`$true"
            $commands | Out-File -FilePath $file -force

            $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file

            if ($result.Status -eq "Succeeded") {
                $message = "Active Directory has been configured on $vmName."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory couldn't be configured on $vmName."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        Write-Warning "Error occured = " $Error[0]
    }
}    

# Create a new Active Directory Organization Unit and make it default for computer objects
function NewADOU 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\NewADOU.ps1"

            $commands = "#Create an OU and make it default computer objects OU" + "`r`n"
            $commands = $commands + "New-ADOrganizationalUnit -Name ""ComputersOU"" -Path ""DC=SQLK8S,DC=LOCAL""" + "`r`n"
            $commands = $commands + "redircmp ""OU=ComputersOU,DC=SQLK8S,DC=LOCAL"""
            $commands | Out-File -FilePath $file -force

            $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file

            while ($result.value.Message -like '*error*') {
                $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file
            }

            if ($result.Status -eq "Succeeded") {
                $message = "Active Directory Organization Unit has been created on $vmName."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory Organization Unit couldn't be created on $vmName."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        Write-Warning "Error occured = " $Error[0]
    }
}    

# Join Azure VM to domain
function JoinDomain 
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName,
        [Parameter(Mandatory = $true)]
        [string]$resourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$domain,
        [Parameter(Mandatory = $true)]
        [string]$adminUsername,
        [Parameter(Mandatory = $true)]
        [SecureString]$adminPassword
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\JoinDomain.ps1"

            $commands = "`$domainUsername=""$domain\$adminUsername""" + "`r`n"
            $commands = $commands + "`$domainPassword=""$adminPassword""" + "`r`n"
            $commands = $commands + "`$SecurePassword = ConvertTo-SecureString `$domainPassword -AsPlainText -Force" + "`r`n"
            $commands = $commands + "`$credential = New-Object System.Management.Automation.PSCredential (`$domainUsername, `$SecurePassword)" + "`r`n"
            $commands = $commands + "Add-Computer -DomainName ""$domain.com"" -Credential `$credential -Restart -Force -PassThru -ErrorAction Stop"
            
            $commands | Out-File -FilePath $file -force

            $result = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroup -VMName $vmName -CommandId "RunPowerShellScript" -ScriptPath $file

            if ($result.Status -eq "Succeeded") {
                $message = "$vmName has been joined to domain."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "$vmName couldn't be joined to domain."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        Write-Warning "Error occured = " $Error[0]
    }
}

# Main Code
Write-Host "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Install NuGet and Powershell Az Module
#Write-Host "Installing NuGet"
#Install-PackageProvider -Name NuGet -Force
#Write-Host "Installing Az Module"
#Install-Module Az -AllowClobber -Force

# Connect to Azure Subscription
ConnectToAzure -subscriptionId $subscriptionId

# Install Active Directory Domain Services
InstallADDS -resourceGroup $resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

# Configure Active Directory Domain
ConfigureADDS -resourceGroup $resourceGroup -vmName "SqlK8sDC" -adminPassword $azurePassword -ErrorAction SilentlyContinue

# Create a new Active Directory Organization Unit and make it default for computer objects
NewADOU -resourceGroup $resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

#################################################################################################
# Join Azure VM to domain
JoinDomain -resourceGroup $resourceGroup -vmName "SqlK8sJumpbox" -domain "sqlk8s" -adminUsername $azureUser -adminPassword $azurePassword -ErrorAction SilentlyContinue

#################################################################################################

Write-Host "Configuration ends: $(Get-Date)"