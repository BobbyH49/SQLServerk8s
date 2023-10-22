# Connect to Azure Subscription
# Install SQL

Start-Transcript -Path $Env:DeploymentLogsDir\DeploySQL.log -Append

Write-Header "Automated Setup"

Write-Host "Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Connect to Azure Subscription
Write-Host "Connecting to Azure"
Connect-AzAccount -Identity | out-null

# Deploy Linux Server with public key authentication
Write-Header "Deploying Linux Server with public key authentication"

# Generate ssh keys
Write-Host "Generating ssh keys"
$linuxKeyFile = $Env:linuxVM.ToLower() + "_id_rsa"
$netbiosNameUpper = $Env:netbiosName.toUpper()
New-Item -Path C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh  -ItemType directory -Force
ssh-keygen -q -t rsa -b 4096 -N '""' -f C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\$linuxKeyFile
$publicKey = Get-Content C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\$linuxKeyFile.pub

# Generate parameters for template deployment
Write-Host "Generating parameters for template deployment"
$templateParameters = @{}
$templateParameters.add("adminUsername", $Env:adminUsername)
$templateParameters.add("sshRSAPublicKey", $publicKey)
$templateParameters.add("vnetName", $Env:vnetName)
$templateParameters.add("linuxVM", $Env:linuxVM)

# Deploy Linux server
Write-Host "Deploying $Env:linuxVM"
New-AzResourceGroupDeployment -ResourceGroupName $Env:resourceGroup -Mode Incremental -Force -TemplateFile "C:\Deployment\templates\linux.json" -TemplateParameterObject $templateParameters

# Add known host
Write-Host "Adding $Env:linuxVM as known host"
ssh-keyscan -t ecdsa 10.$Env:vnetIpAddressRangeStr.16.5 >> C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\known_hosts
(Get-Content C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\known_hosts) | Set-Content -Encoding UTF8 C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\known_hosts
ssh -i C:\Users\$Env:adminUsername.$netbiosNameUpper\.ssh\$linuxKeyFile $Env:adminUsername@10.192.16.5

#ssh -i C:\Users\azureuser.SQLK8s\.ssh\sqlk8slinux_id_rsa azureuser@10.192.16.5

Write-Host "Configuration ends: $(Get-Date)"

# Cleanup
Write-Header "Cleanup environment"
Get-ScheduledTask -TaskName DeploySQL | Unregister-ScheduledTask -Confirm:$false

Stop-Transcript
$logSuppress = Get-Content $Env:DeploymentLogsDir\DCJoinJumpbox.log | Where { $_ -notmatch "Host Application: powershell.exe" }
$logSuppress | Set-Content $Env:DeploymentLogsDir\DCJoinJumpbox.log -Force

[System.Environment]::SetEnvironmentVariable('adminUsername', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('adminPassword', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('netbiosName', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainSuffix', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetName', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('vnetIpAddressRangeStr', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('dcVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('linuxVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxVM', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('jumpboxNic', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentDir', "", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DeploymentLogsDir', "", [System.EnvironmentVariableTarget]::Machine)
