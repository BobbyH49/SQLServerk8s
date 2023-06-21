# Connect to Azure Subscription
# Join Azure VM to domain

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$azureUser,
    [Parameter(Mandatory = $true)]
    [string]$azurePassword
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
        [string]$adminPassword
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\JoinDomain.ps1"

            $commands = "`$domainUsername=""$domain\$adminUsername""" + "`r`n"
            $commands = $commands + "`$domainPassword=""$adminPassword""" + "`r`n"
            $commands = $commands + "`$SecurePassword = ConvertTo-SecureString `$domainPassword -AsPlainText -Force" + "`r`n"
            $commands = $commands + "`$credential = New-Object System.Management.Automation.PSCredential (`$domainUsername, `$SecurePassword)" + "`r`n"
            $commands = $commands + "Add-Computer -DomainName ""$domain.local"" -Credential `$credential -Restart -Force -PassThru -ErrorAction Stop"
            
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

# Connect to Azure Subscription
ConnectToAzure -subscriptionId $subscriptionId

# Join Azure VM to domain
JoinDomain -resourceGroup $resourceGroup -vmName "SqlK8sJumpbox" -domain "sqlk8s" -adminUsername $azureUser -adminPassword $azurePassword -ErrorAction SilentlyContinue

Write-Host "Configuration ends: $(Get-Date)"