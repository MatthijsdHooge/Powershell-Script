<#d'Hooge Matthijs#>

function Write-Log {
    <# 
    .SYNOPSIS 
    Schrijft logberichten naar een centraal bestand voor tracking.
    
    .DESCRIPTION
    Controleert of de logmap bestaat (en maakt deze indien nodig aan) en voegt een tijdgestempeld bericht toe aan een tekstbestand om de voortgang van het script bij te houden.
    
    .EXAMPLE
    Write-Log "Active Directory installatie succesvol afgerond."

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-content
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-path
    #>
    param([string]$Message)
    $logDir  = "$PSScriptRoot\..\logs"
    $logFile = "$logDir\InstallatieLogdhma.txt"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $logFile -Value $entry
}

function Get-InstalldomAD {
    <# 
    .SYNOPSIS 
    Installeert AD DS en promoveert de server tot Domain Controller.
    
    .DESCRIPTION
    Configureert de netwerkadapter met statische IP-gegevens op basis van MacAddress, instelt de DNS-server in op de localhost-lus (127.0.0.1), installeert de benodigde Windows Features en voert de ADDS-Forest installatie uit.
    
    .EXAMPLE
    Get-InstalldomAD

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/servermanager/install-windowsfeature
    https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress
    https://learn.microsoft.com/en-us/powershell/module/netdns/set-dnsclientserveraddress
    #>
    Write-Log "AD DS installation started"
    try {
        # Check if AD is already installed
        $adFeature = Get-WindowsFeature -Name AD-Domain-Services
        if ($adFeature.Installed) {
            try {
                $existingDomain = Get-ADDomain -ErrorAction Stop
                Write-Host "AD DS already installed and domain '$($existingDomain.DNSRoot)' exists - skipping." -ForegroundColor Yellow
                & $global:MenuPath
                return
            } catch {
                Write-Log "AD DS role present but domain not configured - continuing promotion"
            }
        }

        # Load XML files
        $domXml = [xml](Get-Content (Join-Path $PSScriptRoot "..\settings\Domain.Settings.xml") -ErrorAction Stop)
        $compXml = [xml](Get-Content (Join-Path $PSScriptRoot "..\settings\Computer.Settings.xml") -ErrorAction Stop)
        
        $domainName  = $domXml.Settings.Domain.domainname
        $netbiosName = $domXml.Settings.Domain.domainNetbiosName
        $installDns  = $domXml.Settings.Domain.IsDnsIncluded -eq "True"

        # Network Configuration
        foreach ($adapter in $compXml.Settings.networksettings.networkadapter) {
            $target = Get-NetAdapter | Where-Object { $_.MacAddress -eq $adapter.macaddress }
            
            if ($null -ne $target) {
                Write-Log "Configuring Static IP on $($target.Name) (MAC: $($adapter.macaddress))"
                
                # Clean existing config
                Remove-NetIPAddress -InterfaceAlias $target.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Remove-NetRoute -InterfaceAlias $target.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                
                # Apply new IP configuration
                New-NetIPAddress -InterfaceAlias $target.Name -IPAddress $adapter.ip -PrefixLength $adapter.prefixlength -DefaultGateway $adapter.gateway -ErrorAction Stop | Out-Null
                
                # Set DNS to 127.0.0.1 for the Domain Controller
                Set-DnsClientServerAddress -InterfaceAlias $target.Name -ServerAddresses "127.0.0.1" -ErrorAction Stop
                Write-Log "Static IP configured successfully"
            }
        }

        # Install AD DS
        Write-Host "Installing AD DS role..." -ForegroundColor Cyan
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
        
        Import-Module ADDSDeployment -ErrorAction Stop
        $SecurePassword = ConvertTo-SecureString "ApAdmin2026!" -AsPlainText -Force

        # Promote to Forest
        Write-Host "Promoting server to Domain Controller for: $domainName" -ForegroundColor Cyan
        Install-ADDSForest -DomainName $domainName `
                           -DomainNetbiosName $netbiosName `
                           -SafeModeAdministratorPassword $SecurePassword `
                           -InstallDns:$installDns `
                           -Force:$true `
                           -ErrorAction Stop

    } catch {
        $errMessage = "AD Installation failed: $($_.Exception.Message)"
        Write-Log "ERROR: $errMessage"
        Write-Host "`n[!] CRITICAL ERROR [!]" -ForegroundColor Red
        Write-Host $errMessage -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CreateOUs {
    <# 
    .SYNOPSIS 
    Genereert organisatorische eenheden (OU's) in Active Directory.
    
    .DESCRIPTION
    Leest een CSV-bestand ('ous.csv') in, bepaalt het juiste hiërarchische LDAP-pad binnen het huidige domein netjes en maakt ontbrekende Organisational Units aan.
    
    .EXAMPLE
    Get-CreateOUs

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adorganizationalunit
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adorganizationalunit
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv
    #>
    Write-Log "OU creation started"
    try {
        $dom = (Get-ADDomain).DistinguishedName
        Import-Csv (Join-Path $PSScriptRoot "..\settings\ous.csv") -Delimiter ";" | ForEach-Object {
            $path = if ($_.Path) { "OU=$($_.Path.Replace(',',',OU=')),$dom" } else { $dom }
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($_.Name)'" -SearchBase $path -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $_.Name -Path $path -ErrorAction Stop | Out-Null
                Write-Log "Created OU: $($_.Name)"
            }
        }
        Write-Host "OU creation sequence completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR OUs: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CreateUsers {
    <# 
    .SYNOPSIS 
    Importeert AD-gebruikers en configureert profiel- en home-mappen.
    
    .DESCRIPTION
    Haalt server- en mapinstellingen op uit de XML en converteert een JSON-bestand ('users.json') met gebruikersgegevens. Maakt accounts aan met een standaard wachtwoord, plaatst ze in de doeltarget-OU und wijst de UNC-paden voor home directories en user profiles toe.
    
    .EXAMPLE
    Get-CreateUsers

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json
    #>
    Write-Log "User import started"
    try {
        $dom = (Get-ADDomain -ErrorAction Stop).DistinguishedName
        $xml = [xml](Get-Content (Join-Path $PSScriptRoot "..\settings\Domain.Settings.xml") -ErrorAction Stop)
        
        $serverName = $xml.Settings.FileServer.name
        $homeDrive = $xml.Settings.UserSettings.homeFolder.homeDrive
        $homeShare = $xml.Settings.UserSettings.homeFolder.sharename
        $profileShare = $xml.Settings.UserSettings.profileFolder.sharename
        $defaultPass = $xml.Settings.UserSettings.defaultPassword

        $jsonPath = Join-Path $PSScriptRoot "..\settings\users.json"
        $jsonData = Get-Content $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json

        $jsonData.users | ForEach-Object {
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($_.login)'" -ErrorAction SilentlyContinue)) {
                $pass = ConvertTo-SecureString $defaultPass -AsPlainText -Force
                $ouObject = Get-ADOrganizationalUnit -Filter "Name -eq '$($_.ou)'" -ErrorAction SilentlyContinue
                $ouPath = if ($ouObject) { $ouObject.DistinguishedName } else { $dom }
       
                $userHome = "\\$serverName\$homeShare\$($_.login)"
                $userProfile = "\\$serverName\$profileShare\$($_.login)"

                New-ADUser -SamAccountName $_.login -Name "$($_.firstName) $($_.lastName)" -AccountPassword $pass -Path $ouPath -Enabled $true -ChangePasswordAtLogon $true -HomeDrive $homeDrive -HomeDirectory $userHome -ProfilePath $userProfile -ErrorAction Stop | Out-Null
                Write-Log "Created User: $($_.login)"
            }
        }
        Write-Host "User creation sequence completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR Users: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CreateGroups {
    <# 
    .SYNOPSIS 
    Genereert beveiligingsgroepen op basis van CSV-input.
    
    .DESCRIPTION
    Leest 'securitygroups.csv' uit. Controleert of de doeltarget-OU bestaat en maakt de groep aan als 'DomainLocal' (indien startend met DL_) of standaard als 'Global' Security Group.
    
    .EXAMPLE
    Get-CreateGroups

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adgroup
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroup
    #>
    Write-Log "Group generation started"
    try {
        $csvPath = Join-Path $PSScriptRoot "..\settings\securitygroups.csv"
        $groups = Import-Csv $csvPath -Delimiter ";" 
        $domainDN = (Get-ADDomain).DistinguishedName
        
        foreach ($row in $groups) {
            $groupName = $row.GroepNaam
            $ouName    = $row.ou
            
            # Find the target OU
            $targetOU = Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $domainDN -ErrorAction SilentlyContinue
            
            if ($null -eq $targetOU) {
                Write-Host "CRITICAL: OU '$ouName' not found for group '$groupName'" -ForegroundColor Red
                continue
            }

            # Existence Check: Only create if missing
            if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
                $scope = if ($groupName -like "DL_*") { "DomainLocal" } else { "Global" }
                
                New-ADGroup -Name $groupName `
                            -GroupScope $scope `
                            -GroupCategory Security `
                            -Path $targetOU.DistinguishedName `
                            -ErrorAction Stop | Out-Null
                            
                Write-Host "Success: Created '$groupName'" -ForegroundColor Green
            } else {
                Write-Host "Group '$groupName' already exists." -ForegroundColor Gray
            }
        }
        Write-Host "Group creation sequence completed." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host "Press Enter to return to menu"
    & $global:MenuPath
}

function Get-AddGroupMembers {
    <# 
    .SYNOPSIS 
    Voegt gebruikers toe aan groepen en maakt ontbrekende groepen dynamisch aan.
    
    .DESCRIPTION
    Verwerkt de gedefinieerde security groups per user uit 'users.json'. Indien een groep ontbreekt, wordt deze automatisch 'on-the-fly' gegenereerd in de bijbehorende GL_Groups of DL_Groups OU alvorens het lidmaatschap toe te passen.
    
    .EXAMPLE
    Get-AddGroupMembers

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroup
    #>
    Write-Log "Group membership started"
    try {
        $domainDN = (Get-ADDomain).DistinguishedName
        
        (Get-Content (Join-Path $PSScriptRoot "..\settings\users.json") -Raw | ConvertFrom-Json).users | ForEach-Object {
            $u = $_.login
            
            $_.securityGroups | ForEach-Object {
                $groupName = $_
                
                $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                
                if ($null -eq $group) {
                    Write-Host "Group '$groupName' is missing! Creating it automatically..." -ForegroundColor Yellow
                    
                    $scope = if ($groupName -like "DL_*") { "DomainLocal" } else { "Global" }
                    $ouTargetName = if ($groupName -like "DL_*") { "DL_Groups" } else { "GL_Groups" }
                    $targetOU = Get-ADOrganizationalUnit -Filter "Name -eq '$ouTargetName'" -SearchBase $domainDN -ErrorAction SilentlyContinue
                    
                    if ($null -ne $targetOU) {
                        New-ADGroup -Name $groupName `
                                    -GroupScope $scope `
                                    -GroupCategory Security `
                                    -Path $targetOU.DistinguishedName `
                                    -ErrorAction Stop | Out-Null
                                    
                        Write-Host "-> Successfully created missing group: $groupName" -ForegroundColor Cyan
                        Write-Log "Auto-created missing group: $groupName"
                    } else {
                        Write-Host "-> CRITICAL ERROR: Could not locate OU '$ouTargetName' to build '$groupName'!" -ForegroundColor Red
                        return 
                    }
                }
                
                try {
                    Add-ADGroupMember -Identity $groupName -Members $u -ErrorAction Stop
                    Write-Host "Success: Added user '$u' to group '$groupName'" -ForegroundColor Green
                    Write-Log "Added $u to $groupName"
                } catch {
                    Write-Host "Info: Skipping '$u' for '$groupName' (Likely already a member)" -ForegroundColor Gray
                }
            }
        }
        Write-Host "Group membership updates completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR Memberships: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
    }
    Read-Host "Press Enter to return to menu"
    & $global:MenuPath
}

function Get-SetPermissions {
    <# 
    .SYNOPSIS 
    Configureert NTFS Access Control Lists (ACL) op lokale mappen.
    
    .DESCRIPTION
    Leest 'rechten.csv' in. Haalt de huidige ACL op van een gespecificeerde map, definieert een nieuwe FileSystemAccessRule op basis van groepsnaam en machtigingstype (Modify of ReadAndExecute), en past overerving (ContainerInherit, ObjectInherit) toe.
    
    .EXAMPLE
    Get-SetPermissions

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-acl
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-acl
    https://learn.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemaccessrule
    #>
    Write-Log "NTFS Permissions started"
    try {
        Import-Csv (Join-Path $PSScriptRoot "..\settings\rechten.csv") -Delimiter ";" -ErrorAction Stop | ForEach-Object {
            if (Test-Path $_.map) {
                $acl = Get-Acl $_.map -ErrorAction Stop
                $rights = if ($_.NTFS_permission -eq "modify") { "Modify" } else { "ReadAndExecute" }
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($_.Groep, $rights, "ContainerInherit,ObjectInherit", "None", "Allow")))
           
                Set-Acl $_.map $acl -ErrorAction Stop
                Write-Log "Set permissions on $($_.map)"
            }
        }
        Write-Host "Permissions assignment completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR Permissions: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CreateShares {
    <# 
    .SYNOPSIS 
    Genereert SMB Netwerkshares op de lokale fileserver.
    
    .DESCRIPTION
    Verwerkt 'shares.csv'. Controleert of de fysieke map aanwezig is (maakt deze zonodig aan) und publiceert de map op het Windows SMB-netwerk met volledige NTFS-rechten ('Everyone' FullAccess op share-niveau).
    
    .EXAMPLE
    Get-CreateShares

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare
    https://learn.microsoft.com/en-us/powershell/module/smbshare/get-smbshare
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item
    #>
    Write-Log "SMB Share deployment started"
    try {
        Import-Csv (Join-Path $PSScriptRoot "..\settings\shares.csv") -Delimiter ";" | ForEach-Object {
            if (-not (Test-Path $_.map)) {
                New-Item -ItemType Directory -Path $_.map -Force -ErrorAction Stop | Out-Null
                Write-Log "Created missing directory: $($_.map)"
            }
            if (-not (Get-SmbShare -Name $_.share -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $_.share -Path $_.map -FullAccess "Everyone" -ErrorAction Stop | Out-Null
                Write-Log "Created Share: $($_.share)"
            }
        }
        Write-Host "Share creation completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR Shares: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

Export-ModuleMember -Function Write-Log, Get-InstalldomAD, Get-CreateOUs, Get-CreateUsers, Get-CreateGroups, Get-AddGroupMembers, Get-SetPermissions, Get-CreateShares