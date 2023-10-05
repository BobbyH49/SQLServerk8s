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

# Install Active Directory Domain Services
function InstallADDS 
{
    param(
        [string]$computerIP,
        [System.Management.Automation.PSCredential]$winCreds
    )
#    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\InstallADDS.ps1"

            $commands = "#Install AD DS feature" + "`r`n"
            $commands = $commands + "Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Restart" + "`r`n"

            $commands | Out-File -FilePath $file -force

            $result = Invoke-Command -ComputerName $computerIP -FilePath $file -Credential $winCreds

            Write-Host "computerIP = $computerIP"
            Write-Host "winCreds = $winCreds"
            Write-Host "file = $file"
            Write-Host "commands = $commands"            
            Write-Host "result = $result"            
            
            if ($result.Success -eq $true) {
                $message = "Active Directory has been enabled on Domain Controller."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory could not be enabled on Domain Controller."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
#    }
#    catch {
#        Remove-Item $file
#        $message = "Error installing Active Directory."
#        NewMessage -message $message -type "error"
#    }
}   

# Configure Active Directory Domain
function ConfigureADDS 
{
    param(
        [string]$computerIP,
        [string]$netbiosName,
        [string]$domainSuffix,
        [string]$adminPassword,
        [System.Management.Automation.PSCredential]$winCreds
    )
    $netbiosNameLower = $netbiosName.toLower()
    $netbiosNameUpper = $netbiosName.toUpper()
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
            $commands = $commands + "-DomainName ""$netbiosNameLower.$domainSuffix"" ``" + "`r`n"
            $commands = $commands + "-DomainNetbiosName ""$netbiosNameUpper"" ``" + "`r`n"
            $commands = $commands + "-ForestMode ""WinThreshold"" ``" + "`r`n"
            $commands = $commands + "-InstallDns:`$true ``" + "`r`n"
            $commands = $commands + "-LogPath ""C:\Windows\NTDS"" ``" + "`r`n"
            $commands = $commands + "-NoRebootOnCompletion:`$false ``" + "`r`n"
            $commands = $commands + "-SafeModeAdministratorPassword `$SecurePassword ``" + "`r`n"
            $commands = $commands + "-SysvolPath ""C:\Windows\SYSVOL"" ``" + "`r`n"
            $commands = $commands + "-Force:`$true"
            $commands | Out-File -FilePath $file -force

            $result = Invoke-Command -ComputerName $computerIP -FilePath $file -Credential $winCreds
            
            if ($result.Status -eq "Success") {
                $message = "Active Directory has been configured."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory could not be configured."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        $message = "Error configuring Active Directory."
        NewMessage -message $message -type "error"
    }
}    

# Create a new Active Directory Organization Unit and make it default for computer objects
function NewADOU 
{
    param(
        [string]$computerIP,
        [string]$netbiosName,
        [string]$domainSuffix,
        [string]$ouName,
        [System.Management.Automation.PSCredential]$winCreds
    )
    $netbiosNameUpper = $netbiosName.toUpper()
    $domainSuffixUpper = $domainSuffix.toUpper()
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\NewADOU.ps1"

            $commands = "#Create an OU and make it default computer objects OU" + "`r`n"
            $commands = $commands + "New-ADOrganizationalUnit -Name ""$ouName"" -Path ""DC=$netbiosNameUpper,DC=$domainSuffixUpper""" + "`r`n"
            $commands = $commands + "redircmp ""OU=$ouName,DC=$netbiosNameUpper,DC=$domainSuffixUpper"""
            $commands | Out-File -FilePath $file -force

            $result = Invoke-Command -ComputerName $computerIP -FilePath $file -Credential $winCreds
            
            while ($result -like '*error*') {
                $result = Invoke-Command -ComputerName $computerIP -FilePath $file -Credential $winCreds
            }

            if ($result -notlike '*successful*') {
                $message = "Active Directory Organization Unit has been created."
                NewMessage -message $message -type "success"
            }
            else {
                $message = "Active Directory Organization Unit could not be created."
                NewMessage -message $message -type "error"
            }

            Remove-Item $file
    }
    catch {
        Remove-Item $file
        $message = "Error creating Organization Unit in Active Directory."
        NewMessage -message $message -type "error"
    }
}

# Create a new Active Directory Organization Unit and make it default for computer objects
function NewDNSForwarder 
{
    
    param(
        [string]$computerIP,
        [string]$dnsForwarderName,
        [string]$masterServers,
        [System.Management.Automation.PSCredential]$winCreds
    )
    try {
            # Create a temporary file in the users TEMP directory
            $file = $env:TEMP + "\NewDNSForwarder.ps1"

            $commands = "# Create a DNSForwarder for the AKS cluster" + "`r`n"
            $commands = $commands + "Add-DnsServerConditionalForwarderZone -Name ""$DnsForwarderName"" -MasterServers ""$MasterServers"""
            $commands | Out-File -FilePath $file -force

            Invoke-Command -ComputerName $computerIP -FilePath $file -Credential $winCreds
            
            Remove-Item $file
    }
    catch {
        Remove-Item $file
        $message = "Error creating DNS Forwarder."
        NewMessage -message $message -type "error"
    }
}    

# Main Code
Write-Host "DC Configuration starts: $(Get-Date)"
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

# Start WinRM service and add IP Address for Domain Controller as a trusted host
Write-Host "Starting WinRM service and addding IP Address for $Env:dcVM as a trusted host"
Start-Service WinRm
Set-Item WSMan:localhost\client\trustedhosts -value $Env:dnsIpAddress -Force

# Getting Windows Credentials
Write-Host "Getting Windows Credentials"
$secWindowsPassword = ConvertTo-SecureString $Env:adminPassword -AsPlainText -Force
$winCreds = New-Object System.Management.Automation.PSCredential ($Env:adminUsername, $secWindowsPassword)

Write-Host "computerIP = $Env:dnsIpAddress"
Write-Host "adminUsername = $Env:adminUsername"
Write-Host "adminPassword = $Env:adminPassword"
Write-Host "secWindowsPassword = $secWindowsPassword"
Write-Host "winCreds = $winCreds"

# Install Active Directory Domain Services
Write-Host "Installing Active Directory"
InstallADDS -computerIP $Env:dnsIpAddress -winCreds $winCreds -ErrorAction SilentlyContinue

# Configure Active Directory Domain
Write-Host "Configuring Active Directory"
ConfigureADDS -computerIP $Env:dnsIpAddress -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -adminPassword $Env:adminPassword -winCreds $winCreds -ErrorAction SilentlyContinue

# Create a new Active Directory Organization Unit and make it default for computer objects
Write-Host "Adding Organization Unit to Active Directory"
$ouName = "SetupOU"
NewADOU -computerIP $Env:dnsIpAddress -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -ouName $ouName -winCreds $winCreds -ErrorAction SilentlyContinue

Write-Host "Add DNS Forwarder for AKS to Domain Controller"
$dnsForwarderName = "privatelink.$Env:azureLocation.azmk8s.io"
$masterServers = "168.63.129.16"
NewDNSForwarder -computerIP $Env:dnsIpAddress -dnsForwarderName $dnsForwarderName -masterServers $masterServers -winCreds $winCreds -ErrorAction SilentlyContinue

Write-Host "Configuration ends: $(Get-Date)"
