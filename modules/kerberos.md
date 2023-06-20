# Setup Windows Authentication (Kerberos) via Linux Server

[< Previous Module](../modules/setup.md) - **[Home](../README.md)** - [Next Module >]()

## Configure Network and DNS Settings on SqlK8sLinux

1. Connect to SqlK8sJumpbox via Bastion (using domain account i.e. <azureUser>.sqlk8s.local)

2. Open Putty

3. Connect to 10.192.4.5 (sqlK8sLinux) using preconfigured credentials

    **NB: You can accept the alert message that will popup.**

4. Get the latest updates

    ```text
    sudo apt-get update -y
    ```

5. Install resolvconf

    ```text
    sudo apt-get install resolvconf
    ```

6. Add dns nameserver to resolvconf configuration file

    ```text
    sudo nano /etc/resolvconf/resolv.conf.d/head
    ```

    Add **nameserver 10.192.4.4** (SqlK8sDC) to the bottom of the file and then press `Ctrl + X` followed by `Y` to save the file

7. Enable the resolvconf service

    ```text
    sudo systemctl enable --now resolvconf.service
    ```

8. Install dependencies for joining SqlK8sLinux to the domain (realm)

    ```text
    sudo apt-get install -y realmd krb5-user software-properties-common packagekit sssd sssd-tools
    ```

    When prompted for the realm enter **SQLK8S.LOCAL**

    When promted for the hostname(s) for the realm enter **SQLK8SDC**

    When prompted for the hostname(s) for the password changing server enter **SQLK8SDC**

9. Update krb5.conf file to disable rdns under default realm

    ```text
    sudo nano /etc/krb5.conf
    ```

    Add **rdns = false** on a new line under default_realm in the \[libdefaults\] section and then press `Ctrl + X` followed by `Y` to save the file

10. Join SqlK8SLinux to the domain (realm) using your azureUser username

    ```text
    sudo realm join sqlk8s.local -U '<azureUser>@SQLK8S.LOCAL' -v
    ```


--Add DNS entry for azlinuxuks01

--Import the public repository GPG keys and then register the Microsoft Ubuntu repository
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list

--If you had a previous preview version of adutil installed, remove any older adutil packages using the below command
sudo apt-get remove adutil-preview

--Run the following command to install adutil. ACCEPT_EULA=Y accepts the EULA for adutil. The EULA is placed at the path /usr/share/adutil/
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y adutil

--Obtain or renew the Kerberos TGT (ticket-granting ticket) using the kinit command. Use a privileged account for the kinit command. The account needs to have permission to connect to the domain, and also should be able to create accounts and SPNs in the domain.
kinit azureuser@SQLLAB.LOCAL

--Using the adutil tool to create the new user that will be used as the privileged Active Directory account by SQL Server.  Then create the SPNs for this user.
--If this step fails due to error connecting to LDAP then move to next step
adutil user create --name azakssqluser --distname CN=azakssqluser,CN=Users,DC=SQLLAB,DC=LOCAL --password 'L@bAdm1n1234'
adutil spn addauto -n azakssqluser -s MSSQLSvc -H mssql-0.sqllab.local -p 1433

--If adutil failed then go to the DC server and create the azakssqluser user.  Then open a command prompt with admin rights and run the following to create all of the SPNs
setspn -S MSSQLSvc/mssql-0.sqllab.local SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-1.sqllab.local SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-2.sqllab.local SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-0.sqllab.local:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-1.sqllab.local:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-2.sqllab.local:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-0:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-1:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-2:1433 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-0 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-1 SQLLAB\azakssqluser
setspn -S MSSQLSvc/mssql-2 SQLLAB\azakssqluser
setspn -S MSSQLSvc/agl1.sqllab.local SQLLAB\azakssqluser
setspn -S MSSQLSvc/agl1.sqllab.local:14033 SQLLAB\azakssqluser
setspn -S MSSQLSvc/agl1:14033 SQLLAB\azakssqluser
setspn -S MSSQLSvc/agl1 SQLLAB\azakssqluser
setspn -l SQLLAB\azakssqluser

--Go to the properties of your new azakssqluser and under Account tick the box for AES256

--Create a new subnet on your vnet with a 22 mask e.g. 10.0.4.0 - 10.0.7.255
--Create AKS Cluster resource using ARM template and parameters files.  Ensure the cluster is create on your new subnet with internal ip address range of 10.254.4.0/22 and dns server of 10.254.4.10
--Add DNS entry on DC for all 3 sql instances.  You will use the same values on your load balancer k8s services.
10.0.5.11 mssql-0
10.0.5.12 mssql-1
10.0.5.13 mssql-2
10.0.5.14 agl1

--Authenticate using kinit on putty
kinit azureuser@SQLLAB.LOCAL

--Run the following on putty with "y" and choice "1" for each to create files encrypted using AES256
adutil keytab createauto -k mssql_mssql-0.keytab -p 1433 -H mssql-0.sqllab.local --password 'L@bAdm1n1234' -s MSSQLSvc
adutil keytab createauto -k mssql_mssql-1.keytab -p 1433 -H mssql-1.sqllab.local --password 'L@bAdm1n1234' -s MSSQLSvc
adutil keytab createauto -k mssql_mssql-2.keytab -p 1433 -H mssql-2.sqllab.local --password 'L@bAdm1n1234' -s MSSQLSvc

--Run the following on putty with choice "1" for each to append the previously created files in AES256
adutil keytab create -k mssql_mssql-0.keytab -p azakssqluser --password 'L@bAdm1n1234'
adutil keytab create -k mssql_mssql-1.keytab -p azakssqluser --password 'L@bAdm1n1234'
adutil keytab create -k mssql_mssql-2.keytab -p azakssqluser --password 'L@bAdm1n1234'

--Run from command prompt to download the 3 keytab files
scp linuxuser@azlinuxuks01:/home/linuxuser/* C:\SQLContainerDeployment\SQL2019AGDomain\

--Go through DeploymentStepsAG.txt

[Continue >](../modules/kerberos.md)
