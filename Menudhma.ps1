<#d'Hooge Matthijs#>

<#making sure script is run as admin#>
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

<#callback for menu#>
$global:MenuPath = $PSCommandPath

<#setting executionpolicy becuase this went wrong once#>
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force


<#importing modules#>
Import-Module "$PSScriptRoot\modules\algemeendhma.psm1" -Force
Import-Module "$PSScriptRoot\modules\domainsettingsdhma.psm1" -Force



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
        Write-Log "Script started"
    #>
    param([string]$Message)
    $logDir  = "$PSScriptRoot\logs"
    $logFile = "$logDir\InstallatieLogdhma.txt"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $logFile -Value $entry
}

function Get-Menudhma {
    <#
    .SYNOPSIS
        Main menu for server and client configuration.
    .DESCRIPTION
        Displays a menu with all available configuration options for Windows Server 2025
        and Windows 11 client. Loads the correct sub-menu based on user input and calls
        the corresponding function from the loaded modules.
    .SOURCES
        - Admin elevation check based on Microsoft PowerShell documentation.
        - Write-Log assisted by Claude AI, adjusted to project requirements.
    .EXAMPLE
        Get-Menudhma
    #>

    Clear-Host
    Write-Log "Script started - main menu loaded"
<#menu uno#>
    Write-Host "
Select the number of the option you want to execute:

1: Basic computer settings
2: Windows Server settings
3: Windows Client settings
"
    $M1choice = Read-Host "Select an option"
    Write-Log "Main menu - user selected: $M1choice"

    while ($M1choice -notin @("1","2","3")) {
        $M1choice = Read-Host "Please select a valid option (1, 2 or 3)"
    }

<#menu dos#>
    if ($M1choice -eq "1") {
        Write-Host "
Basic Computer Configuration

1:  Rename computer (restart needed)
2:  Manually rename network adapter
3:  Automatically rename network adapter(s) (based on xml file)
4:  Disable network adapter
5:  Manually set IP configuration (disables DHCP)
6:  Automatically set IP configuration (based on xml file)
7:  Create folders
8:  Create shares
90: Display computer information
99: Update Windows Server 2025
Q:  Return to main menu
"
        $M2choice = Read-Host "Enter your choice"
        Write-Log "Basic computer menu - user selected: $M2choice"

        if ($M2choice -eq "Q") { Write-Log "User returned to main menu"; Get-Menudhma; return }

       
        switch ($M2choice) {
            "1"  { Get-RenamePC }
            "2"  { Get-RenameAdapter }
            "3"  { Get-RenameAdapXML }
            "4"  { Get-Disadap }
            "5"  { Get-SetIP }
            "6"  { Get-SetIPXML }
            "7"  { Get-CreateFolders }
            "8"  { Get-CreateShares }
            "90" { Get-Pcinf }
            "99" { Get-CheckUpdates }   
            default { Write-Host "Option not yet implemented." }
        }
    }

   <#menu tres#>
    if ($M1choice -eq "2") {
        Write-Host "
Windows Server Configuration

1: Install domain or additional domain controller
2: Create OU's
3: Create users
4: Create security groups
5: Add members to security groups
6: Set NTFS security on folders
7: Setup shares & security on folders
Q: Return to main menu
"
        $M3choice = Read-Host "Enter your choice"
        Write-Log "Windows Server menu - user selected: $M3choice"

        if ($M3choice -eq "Q") { Write-Log "User returned to main menu"; Get-Menudhma; return }

        switch ($M3choice) {
            "1" { Get-InstalldomAD }
            "2" { Get-CreateOUs }
            "3" { Get-CreateUsers }
            "4" { Get-CreateGroups }
            "5" { Get-AddGroupMembers }
            "6" { Get-SetPermissions }
            "7" { Get-CreateShares }
            default { Write-Host "Option not yet implemented." }
        }
    }

  <#menu quatro#>
    if ($M1choice -eq "3") {
        Write-Host "
Windows Client Configuration

1: Rename computer (restart needed)
2: Manually rename network adapter
3: Automatically rename network adapter(s) (based on xml file)
4: Manually add to domain
Q: Return to main menu
"
        $M4choice = Read-Host "Enter your choice"
        Write-Log "Windows Client menu - user selected: $M4choice"

        if ($M4choice -eq "Q") { Write-Log "User returned to main menu"; Get-Menudhma; return }

        switch ($M4choice) {
            "1" { Get-RenamePC }
            "2" { Get-RenameAdapter }
            "3" { Get-RenameAdapXML }
            "4" { Get-JoinDomain }
           
            default { Write-Host "Option not yet implemented." }
        }
    }
}
<#run the menu#>
Get-Menudhma
