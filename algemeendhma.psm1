<#d'Hooge Matthijs#>

function Write-Log {
    <#
    .SYNOPSIS
    Writes a timestamped entry to the installation log file.
    
    .DESCRIPTION
    Appends a message with the current date and time to InstallatieLogdhma.txt located in \scripting\logs. Creates the log directory if it does not exist.
    
    .EXAMPLE
    Write-Log "Renamed computer to SERVER01"

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

function Get-RenamePC {
    <# 
    .SYNOPSIS 
    Renames the computer and sets up a task to resume the menu after reboot.
    
    .DESCRIPTION
    Checks for an existing temporary scheduled task to clean up post-reboot. If not present, it registers a new scheduled task to launch the menu upon the next logon, prompts the user for a new computer name, and triggers an immediate system restart.
    
    .EXAMPLE
    Get-RenamePC

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtask
    https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskaction
    https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-computer
    #>
    $taskName = "RenamePC_RelaunchMenu"
    try {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Log "Post-restart: removed scheduled task $taskName"
            & $global:MenuPath
            return
        }
        
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoExit -ExecutionPolicy Bypass -File `"$global:MenuPath`""
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn) -RunLevel Highest -Force -ErrorAction Stop | Out-Null
        $name = Read-Host "The PC will restart. Enter new computer name"
        Write-Log "Renaming computer to: $name"
        Rename-Computer -NewName $name -Restart -Force -ErrorAction Stop
    } catch {
        $msg = "ERROR RenamePC: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-Pcinf {
    <# 
    .SYNOPSIS 
    Retrieves and displays comprehensive operating system and hardware information.
    
    .DESCRIPTION
    Queries the system properties using the Get-ComputerInfo cmdlet with strict error action definitions to capture hardware and system configuration details into the log file.
    
    .EXAMPLE
    Get-Pcinf

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-computerinfo
    #>
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
    <# 
    .SYNOPSIS 
    Manually disables a specified network adapter.
    
    .DESCRIPTION
    Prompts the user for the exact name of a network interface and disables it using the network transition architecture without confirmation prompts.
    
    .EXAMPLE
    Get-Disadap

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/netadapter/disable-netadapter
    #>
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
    <# 
    .SYNOPSIS 
    Automates network interface renaming via XML configuration.
    
    .DESCRIPTION
    Parses 'Computer.Settings.xml' to map physical network interfaces via their unique hardware MAC Addresses and automatically applies standard naming schemas.
    
    .EXAMPLE
    Get-RenameAdapXML

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter
    https://learn.microsoft.com/en-us/powershell/module/netadapter/rename-netadapter
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content
    #>
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
    $A = Read-Host "To return to main menu press Enter";
    if ($A -eq "") { & $global:Menupath }
}

function Get-SetIPXML {
    <# 
    .SYNOPSIS 
    Configures network address parameters automatically from an XML file.
    
    .DESCRIPTION
    Reads 'Computer.Settings.xml'. Based on the configuration, it either enables dynamic IP allocation via DHCP or unbinds current configuration definitions to map specific static IPv4 metrics, gateways, and custom DNS arrays.
    
    .EXAMPLE
    Get-SetIPXML

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/remove-netipaddress
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/remove-netroute
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress
    https://learn.microsoft.com/en-us/powershell/module/netdns/set-dnsclientserveraddress
    #>
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
                    Set-NetIPInterface -InterfaceAlias $physical.Name -Dhcp Disabled -ErrorAction SilentlyContinue
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
    $A = Read-Host "To return to main menu press Enter";
    if ($A -eq "") { & $global:Menupath }
}

function Get-RenameAdapter {
    <# 
    .SYNOPSIS 
    Renames a network adapter manually.
    
    .DESCRIPTION
    Outputs an interactive matrix highlighting active interfaces, speeds, and link states. Then prompts the console administrator to target an original interface name and switch it cleanly over to a brand new one.
    
    .EXAMPLE
    Get-RenameAdapter

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter
    https://learn.microsoft.com/en-us/powershell/module/netadapter/rename-netadapter
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/select-object
    #>
    Write-Log "Manual Rename Adapter started"
    try {
        Get-NetAdapter | Select-Object Name, Status, LinkSpeed | Out-Host
        $old = Read-Host "Enter current adapter name"
        $new = Read-Host "Enter new name"
        Rename-NetAdapter -Name $old -NewName $new -ErrorAction Stop
        Write-Log "Success: Renamed $old to $new"
        Write-Host "Adapter renamed successfully." -ForegroundColor Green
    } catch {
        $msg = "ERROR RenameAdapter: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CreateFolders {
    <# 
    .SYNOPSIS 
    Automates bulk file system directory structures generation.
    
    .DESCRIPTION
    Loads raw line-by-line directory metrics mapped from the 'mappen.txt' index file. Validates environmental structure persistence via automated testing passes and securely instances new directory entries.
    
    .EXAMPLE
    Get-CreateFolders

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-path
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content
    #>
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

function Get-SetIP {
    <# 
    .SYNOPSIS 
    Sets static IP, Gateway, and DNS.
    
    .DESCRIPTION
    Interactively displays an internal table detailing physical adapter states. Allows administrators to explicitly define localized static networking variables via shell console interaction steps.
    
    .EXAMPLE
    Get-SetIP

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/remove-netipaddress
    https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress
    https://learn.microsoft.com/en-us/powershell/module/netdns/set-dnsclientserveraddress
    #>
    Write-Log "Manual Static IP started"
    try {
        Get-NetAdapter | Select-Object Name, Status | Out-Host
        $int = Read-Host "Interface Name";
        $ip = Read-Host "Static IP"; $pref = Read-Host "Prefix Length"; $gw = Read-Host "Gateway";
        $dns = Read-Host "DNS"
        Remove-NetIPAddress -InterfaceAlias $int -Confirm:$false -ErrorAction Stop | Out-Null
        New-NetIPAddress -InterfaceAlias $int -IPAddress $ip -PrefixLength $pref -DefaultGateway $gw -ErrorAction Stop | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $int -ServerAddresses $dns -ErrorAction Stop
        Write-Log "Success: Set IP $ip on $int"
        Write-Host "IP configuration applied." -ForegroundColor Green
    } catch {
        $msg = "ERROR SetIP: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-JoinDomain {
    <# 
    .SYNOPSIS 
    Joins the computer to the domain.
    
    .DESCRIPTION
    Prompts the network user for an authentic target Active Directory domain namespace. Explicitly targets domain attachment frameworks and schedules post-configuration system restructuring reboots.
    
    .EXAMPLE
    Get-JoinDomain

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer
    #>
    Write-Log "Domain Join started"
    try {
        $dom = Read-Host "Enter Domain name"
        Add-Computer -DomainName $dom -Restart -Force -ErrorAction Stop
        Write-Log "Success: Joined domain $dom"
    } catch {
        $msg = "ERROR Domain Join: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

function Get-CheckUpdates {
    <# 
    .SYNOPSIS 
    Scans for Windows Updates.
    
    .DESCRIPTION
    Leverages CIM infrastructure models by reaching into the 'root/Microsoft/Windows/WindowsUpdate' environment space to evaluate operating system component patch states.
    
    .EXAMPLE
    Get-CheckUpdates

    .NOTES
    https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/invoke-cimmethod
    #>
    Write-Log "Update scan started"
    try {
        Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName "ScanForUpdates" -ErrorAction Stop | Out-Null
        Write-Log "Update scan success"
        Write-Host "Update scan completed." -ForegroundColor Green
    } catch {
        $msg = "ERROR Updates: $($_.Exception.Message)"
        Write-Log $msg
        Write-Host $msg -ForegroundColor Red
        Read-Host "Press Enter to return to menu"
    }
    & $global:MenuPath
}

Export-ModuleMember -Function Write-Log, Get-RenamePC, Get-Pcinf, Get-Disadap, Get-RenameAdapXML, Get-SetIPXML, Get-RenameAdapter, Get-CreateFolders, Get-SetIP, Get-JoinDomain, Get-CheckUpdates