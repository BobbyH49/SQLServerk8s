# Connect to Azure Subscription
# Join Azure VM to domain

# Main Code
Start-Transcript -Path $Env:DeploymentLogsDir\DCJoinJumpbox.log -Append

Write-Header "Joining $Env:jumpboxVM to the domain"

Write-Host "Configuration starts: $(Get-Date)"

# Join Azure VM to domain
Write-Host "Joining $Env:jumpboxVM to domain"
$netbiosNameLower = $netbiosName.toLower()
$netbiosNameUpper = $netbiosName.toUpper()
$domainUsername="$netbiosNameUpper\$adminUsername"
$securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($domainUsername, $securePassword)
Add-Computer -DomainName "$netbiosNameLower.$domainSuffix" -Credential $credential -Force -PassThru -ErrorAction Stop

Write-Host "Configuration ends: $(Get-Date)"

# Configure SQL Install Script
Write-Header "Configuring SQL Install Script"
Get-ScheduledTask -TaskName DCJoinJumpbox | Unregister-ScheduledTask -Confirm:$false
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $Env:DeploymentDir\scripts\DeploySQL.ps1
Register-ScheduledTask -TaskName "DeploySQL" -Trigger $Trigger -User $Env:netbiosName\$Env:adminUsername -Action $Action -RunLevel "Highest" -Force | out-null

Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\DCJoinJumpbox.log | Where-Object { $_ -notmatch "Host Application: powershell.exe" }
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
