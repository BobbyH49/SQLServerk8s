# Connect to Azure Subscription
# Install Active Directory Domain Services
# Configure Active Directory Domain
# Create a new Active Directory Organization Unit and make it default for computer objects

function NewMessage 
{
    param(
        [string]$message,
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
    param(
        [string]$subscriptionId,
        [string]$spnAppId,
        [string]$spnPassword,
        [string]$tenant
    )

    $securePassword = ConvertTo-SecureString -String $spnPassword -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $spnAppId, $securePassword
    Connect-AzAccount -ServicePrincipal -TenantId $tenant -Credential $credential
    
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

# Install Active Directory Domain Services
function InstallADDS 
{
    param(
        [string]$vmName,
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
    param(
        [string]$vmName,
        [string]$resourceGroup,
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
    param(
        [string]$vmName,
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

# Main Code
Write-Header "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
ConnectToAzure -subscriptionId $Env:subscriptionId -spnAppId $Env:spnAppId -spnPassword $Env:spnPassword -tenant $Env:tenant

# Install Active Directory Domain Services
InstallADDS -resourceGroup $Env:resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

# Configure Active Directory Domain
ConfigureADDS -resourceGroup $Env:resourceGroup -vmName "SqlK8sDC" -adminPassword $Env:adminPassword -ErrorAction SilentlyContinue

# Create a new Active Directory Organization Unit and make it default for computer objects
NewADOU -resourceGroup $Env:resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

Write-Header "Configuration ends: $(Get-Date)"
