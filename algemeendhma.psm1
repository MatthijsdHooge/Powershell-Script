function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped entry to the installation log file.
    .DESCRIPTION
        Appends a message with the current date and time to InstallatieLogdhma.txt
        located in \scripting\logs. Creates the log directory if it does not exist.
    .PARAMETER Message
        The message to write to the log file.
    .EXAMPLE
        Write-Log "Renamed computer to SERVER01"
    #>
    param([string]$Message)
    $logDir  = "$PSScriptRoot\..\logs"
    $logFile = "$logDir\InstallatieLogdhma.txt"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $logFile -Value $entry
}

function Get-RenamePC {
    $taskName = "RenamePC_RelaunchMenu"
    try {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Log "Post-restart: removed scheduled task $taskName"
            Get-Menudhma
            return
        }

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoExit -ExecutionPolicy Bypass -File `"$global:MenuPath`""
        
        Register-ScheduledTask -TaskName $taskName -Action $action `
                  -Trigger (New-ScheduledTaskTrigger -AtLogOn) -RunLevel Highest -Force -ErrorAction Stop | Out-Null

        $name = Read-Host "The pc will be restarted after this action!`nEnter the name"
        Write-Log "Renaming computer to: $name"
        
        Rename-Computer -NewName $name -Restart -Force -ErrorAction Stop
    } catch {
        Write-Log "ERROR RenamePC: $($_.Exception.Message)"
        Write-Warning "Failed to initiate PC renaming sequence."
    }
}

function Get-Pcinf {
    Write-Log "User requested computer information"
    try {
        # Force Stop to ensure errors like WMI/CIM service failures are caught
        Get-ComputerInfo -ErrorAction Stop
        Write-Log "Computer information displayed successfully"
    } catch {
        Write-Log "ERROR Pcinf: $($_.Exception.Message)"
        Write-Warning "Could not retrieve system information properties."
    }
    $A = Read-Host -Prompt "To return to main menu press Enter"
    if ($A -eq "") { & $global:Menupath }
}

function Get-Disadap {
    Write-Log "Disable adapter sequence initiated"
    $A = Read-Host -Prompt "Name the adapter you want to disable"
    try {
        Disable-NetAdapter -Name $A -Confirm:$false -ErrorAction Stop
        Write-Log "Network adapter disabled successfully: $A"
    } catch {
        Write-Log "ERROR Disadap: $($_.Exception.Message)"
        Write-Warning "Could not disable adapter '$A'. Verify the name is accurate."
    }
    $B = Read-Host -Prompt "To return to main menu press Enter"
    if ($B -eq "") { & $global:Menupath }
}

function Get-RenameAdapXML {
    Write-Log "XML Automated Rename started"
    try {
        $xml = [xml](Get-Content (Join-Path $PSScriptRoot "..\settings\Computer.Settings.xml") -ErrorAction Stop)
        foreach ($adapter in $xml.Settings.networksettings.networkadapter) {
            try {
                $physical = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.MacAddress -eq $adapter.macaddress }
                if ($null -eq $physical) { Write-Log "Adapter MAC $($adapter.macaddress) not found - skipped"; continue }
                Rename-NetAdapter -Name $physical.Name -NewName $adapter.name -ErrorAction Stop
                Write-Log "Adapter renamed to: $($adapter.name)"
            } catch { Write-Log "ERROR RenameAdapXML Item ($($adapter.name)): $($_.Exception.Message)" }
        }
    } catch { Write-Log "CRITICAL ERROR RenameAdapXML: $($_.Exception.Message)" }
    $A = Read-Host "To return to main menu press Enter"; if ($A -eq "") { & $global:Menupath }
}

function Get-SetIPXML {
    Write-Log "XML Automated IP configuration started"
    try {
        $xml = [xml](Get-Content (Join-Path $PSScriptRoot "..\settings\Computer.Settings.xml") -ErrorAction Stop)
        foreach ($adapter in $xml.Settings.networksettings.networkadapter) {
            try {
                $physical = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.MacAddress -eq $adapter.macaddress }
                if ($null -eq $physical) { Write-Log "Adapter MAC $($adapter.macaddress) not found - skipped"; continue }
                
                if ($adapter.dhcpenabled -eq "false") {
                    Remove-NetIPAddress -InterfaceAlias $physical.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    Remove-NetRoute -InterfaceAlias $physical.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    New-NetIPAddress -InterfaceAlias $physical.Name -IPAddress $adapter.ip -PrefixLength $adapter.prefixlength -DefaultGateway $adapter.gateway -ErrorAction Stop | Out-Null
                    Set-DnsClientServerAddress -InterfaceAlias $physical.Name -ServerAddresses $adapter.dns -ErrorAction Stop
                    Write-Log "Static IP set on $($physical.Name): IP=$($adapter.ip)"
                } else {
                    Set-NetIPInterface -InterfaceAlias $physical.Name -Dhcp Enabled -ErrorAction Stop
                    Set-DnsClientServerAddress -InterfaceAlias $physical.Name -ResetServerAddresses -ErrorAction Stop
                    Write-Log "Adapter $($physical.Name) set to DHCP"
                }
            } catch { Write-Log "ERROR SetIPXML Item ($($physical.Name)): $($_.Exception.Message)" }
        }
    } catch { Write-Log "CRITICAL ERROR SetIPXML Pipeline: $($_.Exception.Message)" }
    $A = Read-Host "To return to main menu press Enter"; if ($A -eq "") { & $global:Menupath }
}


function Get-RenameAdapter {
    <#
    .SYNOPSIS
        Manually renames a network adapter.
    #>
    Write-Log "Manual Rename Adapter started"
    <#show adapters#>
    Get-NetAdapter | Select-Object Name, Status, LinkSpeed | Out-Host
    
    $old = Read-Host "Enter the current name of the adapter (e.g., Ethernet)"
    $new = Read-Host "Enter the new name (e.g., LAN_Internal)"
    
    try {
        Rename-NetAdapter -Name $old -NewName $new -ErrorAction Stop
        Write-Log "Success: Renamed $old to $new"
        Write-Host "Adapter renamed successfully." -ForegroundColor Green
    } catch {
        Write-Log "Error: Could not rename $old. Check if name exists."
        Write-Warning "Failed to rename. Ensure the name is correct."
    }
    
    $A = Read-Host "Press Enter to return to menu"
    if ($A -eq "") { & $global:Menupath }
}

function Get-CreateFolders {
    Write-Log "Folder creation sequence started"
    try {
        $path = Join-Path $PSScriptRoot "..\settings\mappen.txt"
        if (Test-Path $path) {
            Get-Content $path -ErrorAction Stop | ForEach-Object {
                try {
                    if (-not (Test-Path $_)) {
                        New-Item -ItemType Directory -Path $_ -Force -ErrorAction Stop | Out-Null
                        Write-Log "Created folder: $_"
                        Write-Host "Folders have been created."
                    } else { 
                        Write-Log "Skipped: $_ already exists"
                        Write-Host "Folders already existed."
                    }
                } catch { Write-Log "ERROR CreateFolders Item ($_): $($_.Exception.Message)" }
            }
        }
    } catch { Write-Log "CRITICAL ERROR CreateFolders Pipeline: $($_.Exception.Message)" }
    & $global:Menupath
}

function Get-CreateOUs {
    Write-Log "OU creation started"
    try {
        $dom = (Get-ADDomain).DistinguishedName
        Import-Csv (Join-Path $PSScriptRoot "..\settings\ous.csv") -Delimiter ";" | ForEach-Object {
            $path = if ($_.Path) { "OU=$($_.Path.Replace(',',',OU=')),$dom" } else { $dom }
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($_.Name)'" -SearchBase $path -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $_.Name -Path $path -ErrorAction Stop | Out-Null
                Write-Log "Created OU: $($_.Name)"
                Write-Host "OU's have been created."
            }
        }
    } catch { Write-Log "ERROR OUs: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-CreateUsers {
    Write-Log "User import started"
    try {
        $dom = (Get-ADDomain).DistinguishedName
        (Get-Content (Join-Path $PSScriptRoot "..\settings\users.json") -Raw | ConvertFrom-Json).users | ForEach-Object {
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($_.login)'" -ErrorAction SilentlyContinue)) {
                $pass = ConvertTo-SecureString "ApAdmin2026!" -AsPlainText -Force
                $ouObject = Get-ADOrganizationalUnit -Filter "Name -eq '$($_.ou)'" -ErrorAction SilentlyContinue
                $ouPath = if ($ouObject) { $ouObject.DistinguishedName } else { $dom }
                New-ADUser -SamAccountName $_.login `
                           -Name "$($_.firstName) $($_.lastName)" `
                           -AccountPassword $pass `
                           -Path $ouPath `
                           -Enabled $true `
                           -ChangePasswordAtLogon $true `
                           -ErrorAction Stop | Out-Null
                Write-Log "Created User: $($_.login) in $ouPath"
                Write-Host "User $($_.login) created."
            }
        }
    } catch { Write-Log "ERROR Users: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-SetPermissions {
    Write-Log "NTFS Permissions started"
    try {
        Import-Csv (Join-Path $PSScriptRoot "..\settings\rechten.csv") -Delimiter ";" -ErrorAction Stop | ForEach-Object {
            if (Test-Path $_.map) {
                $acl = Get-Acl $_.map -ErrorAction Stop
                $rights = if ($_.NTFS_permission -eq "modify") { "Modify" } else { "ReadAndExecute" }
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($_.Groep, $rights, "ContainerInherit,ObjectInherit", "None", "Allow")))
                Set-Acl $_.map $acl -ErrorAction Stop
                Write-Log "Set permissions on $($_.map)"
                Write-Host "Permissions have been assigned."
            } else {
                Write-Log "WARNING Permissions: Path $($_.map) not found."
            }
        }
    } catch { Write-Log "ERROR Permissions: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-InstalldomAD {
    Write-Host "DNS will be installed alongside AD DS!" -ForegroundColor Cyan
    $A = Read-Host -Prompt "Enter the Domain name (e.g., BelgoCorpxxx.lab)"

    Write-Log "Starting AD DS installation for domain: $A"
    
    try {
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
        Write-Log "AD DS role installed successfully"
        
        Import-Module ADDSDeployment
        
        $SecurePassword = ConvertTo-SecureString "ApAdmin2026!" -AsPlainText -Force
        
        Install-ADDSForest -DomainName $A `
                           -SafeModeAdministratorPassword $SecurePassword `
                           -InstallDns `
                           -Force:$true
    } catch {
        Write-Error "AD Installation failed. Are you running on Windows Server?"
        Write-Log "ERROR: AD Installation failed - $($_.Exception.Message)"
    }
}

function Get-SetIP {
    Write-Log "Manual Static IP started"
    Get-NetAdapter | Select-Object Name, Status | Out-Host
    $int = Read-Host "Interface Name"; $ip = Read-Host "Static IP"; $pref = Read-Host "Prefix Length"; $gw = Read-Host "Gateway"; $dns = Read-Host "DNS"
    try {
        Remove-NetIPAddress -InterfaceAlias $int -Confirm:$false -ErrorAction Stop | Out-Null
        New-NetIPAddress -InterfaceAlias $int -IPAddress $ip -PrefixLength $pref -DefaultGateway $gw -ErrorAction Stop | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $int -ServerAddresses $dns -ErrorAction Stop
        Write-Log "Success: Set IP $ip on $int"
        Write-Host "IP has been set."
    } catch { Write-Log "ERROR SetIP: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-CreateGroups {
    Write-Log "Group generation started"
    try {
        $dom = (Get-ADDomain).DistinguishedName
        Import-Csv (Join-Path $PSScriptRoot "..\settings\securitygroups.csv") -Delimiter ";" | ForEach-Object {
            if (-not (Get-ADGroup -Filter "Name -eq '$($_.GroepNaam)'" -ErrorAction SilentlyContinue)) {
                $scope = if ($_.GroepNaam -like "DL_*") { "DomainLocal" } else { "Global" }
                New-ADGroup -Name $_.GroepNaam -GroupScope $scope -GroupCategory Security -Path "OU=$($_.ou),$dom" -ErrorAction Stop | Out-Null
                Write-Log "Created Group: $($_.GroepNaam)"
                Write-Host "Groups have been created."
            }
        }
    } catch { Write-Log "ERROR Groups: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-AddGroupMembers {
    Write-Log "Group membership started"
    try {
        (Get-Content (Join-Path $PSScriptRoot "..\settings\users.json") -Raw | ConvertFrom-Json).users | ForEach-Object {
            $u = $_.login
            $_.securityGroups | ForEach-Object {
                try { Add-ADGroupMember -Identity $_ -Members $u -ErrorAction Stop | Out-Null; Write-Log "Added $u to $_" 
                Write-Host "Get-AddGroupMembers succesfull."}
                catch { if ($_.Exception.Message -notlike "*already exists*") { Write-Log "ERROR Member bind: $($_.Exception.Message)" } }
            }
        }
    } catch { Write-Log "ERROR Memberships: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-CreateShares {
    Write-Log "SMB Share deployment started"
    try {
        Import-Csv (Join-Path $PSScriptRoot "..\settings\shares.csv") -Delimiter ";" | ForEach-Object {
            if ((Test-Path $_.map) -and -not (Get-SmbShare -Name $_.share -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $_.share -Path $_.map -FullAccess "Everyone" -ErrorAction Stop | Out-Null
                Write-Log "Created Share: $($_.share)"
                Write-Host "Shares have been created."
            }
        }
    } catch { Write-Log "ERROR Shares: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-JoinDomain {
    Write-Log "Domain Join started"
    $dom = Read-Host "Enter Domain name"
    try {
        Add-Computer -DomainName $dom -Restart -Force -ErrorAction Stop
        Write-Log "Success: Joined domain $dom"
    } catch { Write-Log "ERROR Domain Join: $($_.Exception.Message)" }
    & $global:MenuPath
}

function Get-CheckUpdates {
    Write-Log "Update scan started"
    try {   
        Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName "ScanForUpdates" -ErrorAction Stop | Out-Null
        Write-Log "Update scan success"
    } catch { Write-Log "ERROR Updates: $($_.Exception.Message)" }
    & $global:MenuPath
}