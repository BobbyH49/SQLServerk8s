# Connect to Azure Subscription
# Join Azure VM to domain

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

    try {
        $check = Get-AzContext -ErrorAction SilentlyContinue
        if ($null -eq $check) {
            $securePassword = ConvertTo-SecureString -String $spnPassword -AsPlainText -Force
            $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $spnAppId, $securePassword
            Connect-AzAccount -ServicePrincipal -TenantId $tenant -Credential $credential | out-null
        }
        else {
            Set-AzContext -SubscriptionId $subscriptionId | out-null
        }
        $message = "Connected to Azure."
        NewMessage -message $message -type "success"
    }
    catch {
        $message = "Failed to connect to Azure."
        NewMessage -message $message -type "error"
        Exit
    }
}

# Join Azure VM to domain
function JoinDomain 
{
    param(
        [string]$vmName,
        [string]$resourceGroup,
        [string]$netbiosName,
        [string]$domainSuffix,
        [string]$adminUsername,
        [string]$adminPassword
    )
    $netbiosNameLower = $netbiosName.toLower()
    $netbiosNameUpper = $netbiosName.toUpper()
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\JoinDomain.ps1"

            $commands = "`$domainUsername=""$netbiosNameUpper\$adminUsername""" + "`r`n"
            $commands = $commands + "`$domainPassword=""$adminPassword""" + "`r`n"
            $commands = $commands + "`$SecurePassword = ConvertTo-SecureString `$domainPassword -AsPlainText -Force" + "`r`n"
            $commands = $commands + "`$credential = New-Object System.Management.Automation.PSCredential (`$domainUsername, `$SecurePassword)" + "`r`n"
            $commands = $commands + "Add-Computer -DomainName ""$netbiosNameLower.$domainSuffix"" -Credential `$credential -Force -PassThru -ErrorAction Stop"
            
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
        $message = "Failed to join $vmName to the domain."
        NewMessage -message $message -type "error"
    }
}

# Main Code
Start-Transcript -Path $Env:DeploymentLogsDir\EnvironmentSetup.log -Append

Write-Header "Joining $Env:jumpboxVM to the domain"

Write-Host "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
Write-Host "Connecting to Azure"
ConnectToAzure -subscriptionId $Env:subscriptionId -spnAppId $Env:spnAppId -spnPassword $Env:spnPassword -tenant $Env:tenant -ErrorAction SilentlyContinue

# Join Azure VM to domain
Write-Host "Joining $Env:jumpboxVM to domain"
JoinDomain -resourceGroup $Env:resourceGroup -vmName $Env:jumpboxVM -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword -ErrorAction SilentlyContinue

Write-Host "Configuration ends: $(Get-Date)"

# Cleanup
Write-Header "Cleanup environment"
Get-ScheduledTask -TaskName DCJoinJumpbox | Unregister-ScheduledTask -Force

Stop-Transcript

# Reboot SqlK8sJumpbox
Write-Host "`r`n";
Write-Host '$Env:jumpboxVM has been joined to the domain and will now reboot';
Write-Host "`r`n";
Write-Host 'Close Bastion session and reconnect using $Env:netbiosName.toUpper()\$Env:adminUsername with the same password';
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Restart-Computer -Force
