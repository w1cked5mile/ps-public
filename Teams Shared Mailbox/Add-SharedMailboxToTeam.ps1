<#
.SYNOPSIS
Creates a new shared mailbox and associates it with an existing Microsoft Team.

.DESCRIPTION
This script creates a new shared mailbox in Exchange Online and adds it as a tab 
in the General channel of an existing Microsoft Team. The script includes comprehensive 
error handling, logging, and validation to ensure successful integration.

.NOTES
This script requires the following PowerShell modules:
- Microsoft.Graph (for Teams integration)
- ExchangeOnlineManagement (for shared mailbox creation)

Prerequisites:
- User must have permissions to create shared mailboxes in Exchange Online
- User must have permissions to modify Teams and add tabs
- The specified Team must already exist

.PARAMETER TeamName
The display name of the existing Microsoft Team.

.PARAMETER SharedMailboxName
The display name for the new shared mailbox.

.PARAMETER SharedMailboxAlias
The email alias for the new shared mailbox (without @domain.com).

.PARAMETER Domain
The domain for the shared mailbox email address (e.g., "contoso.com").

.PARAMETER LogPath
(Optional) Path to the log file. Default is script directory.

.EXAMPLE
.\Add-SharedMailboxToTeam.ps1 -TeamName "Marketing Team" -SharedMailboxName "Marketing Shared" -SharedMailboxAlias "marketing-shared" -Domain "contoso.com"

.EXAMPLE
.\Add-SharedMailboxToTeam.ps1 -TeamName "Sales Team" -SharedMailboxName "Sales Archive" -SharedMailboxAlias "sales-archive" -Domain "company.com" -LogPath "C:\Logs\TeamMailbox.log"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$TeamName,

    [Parameter(Mandatory = $true)]
    [string]$SharedMailboxName,

    [Parameter(Mandatory = $true)]
    [string]$SharedMailboxAlias,

    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [string]$LogPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\TeamMailboxIntegration.log"
)

# Global variables
$SharedMailboxAddress = "$SharedMailboxAlias@$Domain"
$TeamId = $null
$GeneralChannelId = $null
$MailboxCreated = $false

function Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp`t[$Level]`t$Message"
    Add-Content -Path $LogPath -Value $logEntry
    
    # Also output to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
}

function Test-RequiredModules {
    Log "Checking required PowerShell modules..."
    
    $requiredModules = @(
        @{ Name = "Microsoft.Graph"; MinVersion = "1.0" },
        @{ Name = "ExchangeOnlineManagement"; MinVersion = "2.0" }
    )
    
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -Name $module.Name -ListAvailable | 
            Where-Object { $_.Version -ge [version]$module.MinVersion } | 
            Select-Object -First 1
        
        if (-not $installedModule) {
            $missingModules += $module.Name
            Log "Missing required module: $($module.Name) (minimum version $($module.MinVersion))" "ERROR"
        } else {
            Log "Found module: $($module.Name) version $($installedModule.Version)" "SUCCESS"
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Log "Please install missing modules using: Install-Module -Name ModuleName" "ERROR"
        return $false
    }
    
    return $true
}

function Connect-Services {
    Log "Connecting to Microsoft services..."
    
    try {
        # Connect to Microsoft Graph
        Log "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "Group.ReadWrite.All", "TeamSettings.ReadWrite.All", "TeamsTab.ReadWrite.All" -ErrorAction Stop
        Log "Successfully connected to Microsoft Graph" "SUCCESS"
        
        # Connect to Exchange Online
        Log "Connecting to Exchange Online..."
        Connect-ExchangeOnline -ErrorAction Stop
        Log "Successfully connected to Exchange Online" "SUCCESS"
        
        return $true
    }
    catch {
        Log "Failed to connect to services: $_" "ERROR"
        return $false
    }
}

function Get-TeamInformation {
    param ([string]$TeamName)
    
    Log "Searching for Team: $TeamName"
    
    try {
        # Get the team by display name
        $team = Get-MgTeam -Filter "displayName eq '$TeamName'" -ErrorAction Stop
        
        if (-not $team) {
            Log "Team '$TeamName' not found" "ERROR"
            return $null
        }
        
        if ($team.Count -gt 1) {
            Log "Multiple teams found with name '$TeamName'. Using the first one." "WARNING"
            $team = $team[0]
        }
        
        Log "Found Team: $($team.DisplayName) (ID: $($team.Id))" "SUCCESS"
        
        # Get the General channel
        $channels = Get-MgTeamChannel -TeamId $team.Id -ErrorAction Stop
        $generalChannel = $channels | Where-Object { $_.DisplayName -eq "General" }
        
        if (-not $generalChannel) {
            Log "General channel not found in team '$TeamName'" "ERROR"
            return $null
        }
        
        Log "Found General channel (ID: $($generalChannel.Id))" "SUCCESS"
        
        return @{
            TeamId = $team.Id
            TeamName = $team.DisplayName
            GeneralChannelId = $generalChannel.Id
        }
    }
    catch {
        Log "Error retrieving team information: $_" "ERROR"
        return $null
    }
}

function New-SharedMailbox {
    param (
        [string]$Name,
        [string]$Alias,
        [string]$PrimarySmtpAddress
    )
    
    Log "Creating shared mailbox: $Name ($PrimarySmtpAddress)"
    
    try {
        # Check if mailbox already exists
        $existingMailbox = Get-Mailbox -Identity $PrimarySmtpAddress -ErrorAction SilentlyContinue
        
        if ($existingMailbox) {
            Log "Shared mailbox '$PrimarySmtpAddress' already exists" "WARNING"
            return $existingMailbox
        }
        
        # Create the shared mailbox
        $mailbox = New-Mailbox -Shared -Name $Name -DisplayName $Name -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress -ErrorAction Stop
        
        Log "Successfully created shared mailbox: $($mailbox.DisplayName) ($($mailbox.PrimarySmtpAddress))" "SUCCESS"
        
        # Wait a moment for mailbox to be fully provisioned
        Start-Sleep -Seconds 10
        
        return $mailbox
    }
    catch {
        Log "Failed to create shared mailbox: $_" "ERROR"
        return $null
    }
}

function Add-MailboxTabToTeam {
    param (
        [string]$TeamId,
        [string]$ChannelId,
        [string]$MailboxAddress,
        [string]$DisplayName
    )
    
    Log "Adding shared mailbox tab to Team channel..."
    
    try {
        # Create the tab configuration for Outlook
        $tabConfig = @{
            "displayName" = $DisplayName
            "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/1542629c-01b3-4a6d-8f76-1938b779e48d"  # Outlook app ID
            "configuration" = @{
                "entityId" = $MailboxAddress
                "contentUrl" = "https://outlook.office.com/mail/$MailboxAddress"
                "websiteUrl" = "https://outlook.office.com/mail/$MailboxAddress"
                "removeUrl" = "https://outlook.office.com/mail/$MailboxAddress"
            }
        }
        
        # Add the tab to the General channel
        $tab = New-MgTeamChannelTab -TeamId $TeamId -ChannelId $ChannelId -BodyParameter $tabConfig -ErrorAction Stop
        
        Log "Successfully added shared mailbox tab: $($tab.DisplayName)" "SUCCESS"
        return $tab
    }
    catch {
        Log "Failed to add mailbox tab to team: $_" "ERROR"
        
        # Try alternative method with simpler configuration
        try {
            Log "Attempting alternative tab creation method..."
            
            $altTabConfig = @{
                "displayName" = $DisplayName
                "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/1542629c-01b3-4a6d-8f76-1938b779e48d"
                "configuration" = @{
                    "entityId" = $MailboxAddress
                    "contentUrl" = "https://outlook.office365.com/mail/$MailboxAddress"
                }
            }
            
            $altTab = New-MgTeamChannelTab -TeamId $TeamId -ChannelId $ChannelId -BodyParameter $altTabConfig -ErrorAction Stop
            Log "Successfully added shared mailbox tab using alternative method: $($altTab.DisplayName)" "SUCCESS"
            return $altTab
        }
        catch {
            Log "Alternative tab creation method also failed: $_" "ERROR"
            return $null
        }
    }
}

function Remove-SharedMailboxOnError {
    param ([string]$MailboxAddress)
    
    if ($MailboxCreated) {
        Log "Cleaning up: Removing shared mailbox due to error..." "WARNING"
        try {
            Remove-Mailbox -Identity $MailboxAddress -Confirm:$false -ErrorAction Stop
            Log "Successfully removed shared mailbox: $MailboxAddress" "SUCCESS"
        }
        catch {
            Log "Failed to remove shared mailbox during cleanup: $_" "ERROR"
        }
    }
}

function Disconnect-Services {
    Log "Disconnecting from Microsoft services..."
    
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Log "Successfully disconnected from services" "SUCCESS"
    }
    catch {
        Log "Error during service disconnection: $_" "WARNING"
    }
}

# Main execution
Log "===== Starting Team Shared Mailbox Integration ====="
Log "Team: $TeamName"
Log "Shared Mailbox: $SharedMailboxName ($SharedMailboxAddress)"

try {
    # Check required modules
    if (-not (Test-RequiredModules)) {
        throw "Required modules are not installed"
    }
    
    # Connect to services
    if (-not (Connect-Services)) {
        throw "Failed to connect to required services"
    }
    
    # Get team information
    $teamInfo = Get-TeamInformation -TeamName $TeamName
    if (-not $teamInfo) {
        throw "Could not retrieve team information"
    }
    
    $TeamId = $teamInfo.TeamId
    $GeneralChannelId = $teamInfo.GeneralChannelId
    
    # Create shared mailbox
    $mailbox = New-SharedMailbox -Name $SharedMailboxName -Alias $SharedMailboxAlias -PrimarySmtpAddress $SharedMailboxAddress
    if (-not $mailbox) {
        throw "Failed to create shared mailbox"
    }
    
    $MailboxCreated = $true
    
    # Add mailbox tab to team
    $tab = Add-MailboxTabToTeam -TeamId $TeamId -ChannelId $GeneralChannelId -MailboxAddress $SharedMailboxAddress -DisplayName $SharedMailboxName
    if (-not $tab) {
        Log "Failed to add mailbox tab to team, but mailbox was created successfully" "WARNING"
        Log "You can manually add the mailbox tab in Teams using: $SharedMailboxAddress" "INFO"
    }
    
    # Success summary
    Log "===== Integration Complete ====="
    Log "✓ Shared mailbox created: $SharedMailboxAddress" "SUCCESS"
    Log "✓ Team identified: $($teamInfo.TeamName)" "SUCCESS"
    
    if ($tab) {
        Log "✓ Mailbox tab added to General channel" "SUCCESS"
    } else {
        Log "⚠ Mailbox tab creation failed - manual addition required" "WARNING"
    }
    
    Log "Team members can now access the shared mailbox through:" "INFO"
    Log "  - Outlook: $SharedMailboxAddress" "INFO"
    Log "  - Teams: General channel tab (if successfully added)" "INFO"
}
catch {
    Log "FATAL ERROR: $_" "ERROR"
    
    # Cleanup on error
    Remove-SharedMailboxOnError -MailboxAddress $SharedMailboxAddress
    
    # Exit with error code
    exit 1
}
finally {
    # Always disconnect services
    Disconnect-Services
    Log "===== Script execution completed ====="
}
