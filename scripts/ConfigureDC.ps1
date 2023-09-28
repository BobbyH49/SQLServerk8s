# Connect to Azure Subscription
# Install Active Directory Domain Services
# Configure Active Directory Domain
# Create a new Active Directory Organization Unit and make it default for computer objects

[CmdletBinding()]
param(
    [string]$adminUser,
    [string]$adminPassword
    [string]$subscriptionId,
    [string]$resourceGroup
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
        Write-Header $message -ForegroundColor Green
    }
    elseif ($type -eq "information") {
        Write-Header $message -ForegroundColor Yellow
    }
    elseif ($type -eq "error") {
        Write-Header $message -ForegroundColor Red
    }
    else {
        Write-Header "You need to pass message type as success/warning/error."
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

# Main Code
[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', $adminPassword, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DCDir', "C:\DC", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('SuppressAzurePowerShellBreakingChangeWarnings', "$true", [System.EnvironmentVariableTarget]::Machine)

# Creating DC path
Write-Output "Creating DC path"
$Env:DCDir = "C:\DC"
$Env:DCLogsDir = "$Env:DCDir\Logs"

New-Item -Path $Env:DCDir -ItemType directory -Force
New-Item -Path $Env:DCLogsDir -ItemType directory -Force

Start-Transcript -Path $Env:DCLogsDir\ConfigureDC.log

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateBaseUrl + "scripts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

Write-Header "Configuration starts: $(Get-Date)"
#Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
#ConnectToAzure -subscriptionId $subscriptionId

# Install Active Directory Domain Services
InstallADDS -resourceGroup $resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

# Configure Active Directory Domain
ConfigureADDS -resourceGroup $resourceGroup -vmName "SqlK8sDC" -adminPassword $adminPassword -ErrorAction SilentlyContinue

# Create a new Active Directory Organization Unit and make it default for computer objects
NewADOU -resourceGroup $resourceGroup -vmName "SqlK8sDC" -ErrorAction SilentlyContinue

# Remove DNS Server from SqlK8sJumpbox-nic
#$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroup -Name "SqlK8sJumpbox-nic"
#$nic.DnsSettings.DnsServers.Clear()
#$nic | Set-AzNetworkInterface

Write-Header "Configuration ends: $(Get-Date)"

# Clean up ConfigureDC.log
Write-Header "Clean up ConfigureDC.log"
Stop-Transcript
$logSuppress = Get-Content $Env:DCLogsDir\ConfigureDC.log | Where { $_ -notmatch "Host Application: powershell.exe" } 
$logSuppress | Set-Content $Env:DCLogsDir\ConfigureDC.log -Force
