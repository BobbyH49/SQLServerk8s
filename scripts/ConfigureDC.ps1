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

# Configure Active Directory Domain
function ConfigureADDS 
{
    param(
        [string]$netbiosName,
        [string]$domainSuffix,
        [string]$adminPassword
    )
    try {
        $domainName = $netbiosName.toLower() + "." + $domainSuffix
        $domainNetbiosName = $netbiosName.toUpper()
        $SecurePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force

        #AD DS Deployment
        Import-Module ADDSDeployment
        
        Install-ADDSForest `
            -CreateDnsDelegation:$false `
            -DatabasePath "C:\Windows\NTDS" `
            -DomainMode "WinThreshold" `
            -DomainName $domainName `
            -DomainNetbiosName $domainNetbiosName `
            -ForestMode "WinThreshold" `
            -InstallDns `
            -LogPath "C:\Windows\NTDS" `
            -NoRebootOnCompletion `
            -SafeModeAdministratorPassword $SecurePassword `
            -SysvolPath "C:\Windows\SYSVOL" `
            -Force
    }
    catch {
        $message = "Error configuring Active Directory."
        NewMessage -message $message -type "error"
    }
}    

# Create a new Active Directory Organization Unit and make it default for computer objects
function NewADOU 
{
    param(
        [string]$netbiosName,
        [string]$domainSuffix,
        [string]$ouName
    )
    $netbiosNameUpper = $netbiosName.toUpper()
    $domainSuffixUpper = $domainSuffix.toUpper()
    try {
        #Create an OU and make it default computer objects OU

        New-ADOrganizationalUnit -Name $ouName -Path "DC=$netbiosNameUpper,DC=$domainSuffixUpper"
        redircmp "OU=$ouName,DC=$netbiosNameUpper,DC=$domainSuffixUpper"
    }
    catch {
        $message = "Error creating Organization Unit in Active Directory."
        NewMessage -message $message -type "error"
    }
}

# Create a new Active Directory Organization Unit and make it default for computer objects
function NewDNSForwarder 
{
    
    param(
        [string]$dnsForwarderName,
        [string]$masterServers
    )
    try {
        # Create a DNSForwarder for the AKS cluster
        Add-DnsServerConditionalForwarderZone -Name $DnsForwarderName -MasterServers $MasterServers
    }
    catch {
        $message = "Error creating DNS Forwarder."
        NewMessage -message $message -type "error"
    }
}    

# Main Code
Write-Host "DC Configuration starts: $(Get-Date)"

# Install Active Directory Domain Services
Write-Host "Installing Active Directory"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Configure Active Directory Domain
Write-Host "Configuring Active Directory"
ConfigureADDS -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -adminPassword $Env:adminPassword -ErrorAction SilentlyContinue

# Create a new Active Directory Organization Unit and make it default for computer objects
Write-Host "Adding Organization Unit to Active Directory"
$ouName = "SetupOU"
NewADOU -netbiosName $Env:netbiosName -domainSuffix $Env:domainSuffix -ouName $ouName -ErrorAction SilentlyContinue

Write-Host "Add DNS Forwarder for AKS to Domain Controller"
$dnsForwarderName = "privatelink.$Env:azureLocation.azmk8s.io"
$masterServers = "168.63.129.16"
NewDNSForwarder -dnsForwarderName $dnsForwarderName -masterServers $masterServers -ErrorAction SilentlyContinue

Write-Host "Configuration ends: $(Get-Date)"
