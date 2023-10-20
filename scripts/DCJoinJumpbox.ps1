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
Start-Transcript -Path $Env:DeploymentLogsDir\DCJoinJumpbox.log -Append

Write-Header "Joining $Env:jumpboxVM to the domain"

Write-Host "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
Write-Host "Connecting to Azure"
Connect-AzAccount -Identity | out-null

# Join Azure VM to domain
Write-Host "Joining $Env:jumpboxVM to domain"
JoinDomain -resourceGroup $Env:resourceGroup -vmName $Env:jumpboxVM -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -adminUsername $Env:adminUsername -adminPassword $Env:adminPassword -ErrorAction SilentlyContinue

Write-Host "Configuration ends: $(Get-Date)"

# Configure SQL Install Script
Write-Header "Configuring SQL Install Script"
Get-ScheduledTask -TaskName DCJoinJumpbox | Unregister-ScheduledTask -Confirm:$false
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\DeploySQL.ps1
Register-ScheduledTask -TaskName "DeploySQL" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force | out-null

Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\DCJoinJumpbox.log | Where { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\DCJoinJumpbox.log -Force

# Reboot SqlK8sJumpbox
$netbiosNameLower = $Env:netbiosName.toLower()
Write-Host "`r`n";
Write-Host "$Env:jumpboxVM has been joined to the domain and will now reboot";
Write-Host "`r`n";
Write-Host "Close Bastion session and reconnect using $Env:adminUsername@$netbiosNameLower.$Env:domainSuffix with the same password";

Write-Host -NoNewLine "Press any key to continue...";
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
Restart-Computer -Force
