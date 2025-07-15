<#
.SYNOPSIS
Sync mailbox permissions for a shared mailbox based on Microsoft 365 Group membership.

.DESCRIPTION
Assigns FullAccess to group owners and ReadPermission to group members who are not owners.
Adds the shared mailbox to members' Outlook (both Online and Desktop) for easy access.
Removes stale permissions from users who are no longer group members.
Logs all changes and errors to a log file.

.NOTES
A Team needs a shared mailbox to access curated folders of emails from terminated employees.
Rather than setting a tenant wide policy allowing all Teams to create sub-folders within the Team mailbox, 
this script allows for a more controlled approach. A Shared mailbox is created and permissions are assigned based on Team membership.
Team Owners have full access, while regular members have read-only access to the shared mailbox. 
The script can be re-run to update permissions as group membership changes and could be scheduled to run periodically 
(e.g., daily with PowerShell + Azure Automation or Task Scheduler). 

.PARAMETER GroupName
The display name of the Microsoft 365 Group.

.PARAMETER SharedMailbox
The primary SMTP address of the shared mailbox.

.PARAMETER LogPath
(Optional) Path to the log file. Default is script directory.

.EXAMPLE
.\Sync-GroupMailboxPermissions.ps1 -GroupName "Marketing Team" -SharedMailbox "marketing@contoso.com"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$GroupName,

    [Parameter(Mandatory = $true)]
    [string]$SharedMailbox,

    [string]$LogPath = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\GroupMailboxPermissions.log"
)

function Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "$timestamp`t$Message"
}

# Start Logging
Log "----- Starting permission sync for group '$GroupName' and mailbox '$SharedMailbox' -----"

try {
    $owners = Get-UnifiedGroupLinks -Identity $GroupName -LinkType Owners -ErrorAction Stop
    $members = Get-UnifiedGroupLinks -Identity $GroupName -LinkType Members -ErrorAction Stop

    $ownerEmails = $owners.PrimarySmtpAddress
    $memberEmails = $members.PrimarySmtpAddress
    $allCurrentUsers = @()
    $allCurrentUsers += $ownerEmails
    $allCurrentUsers += $memberEmails
    $allCurrentUsers = $allCurrentUsers | Sort-Object -Unique

    # Remove stale permissions
    Log "----- Checking for stale permissions -----"
    try {
        $currentPermissions = Get-MailboxPermission -Identity $SharedMailbox -ErrorAction Stop | 
            Where-Object { $_.User -notlike "NT AUTHORITY\SELF" -and $_.User -notlike "S-1-*" -and $_.IsInherited -eq $false }
        
        foreach ($permission in $currentPermissions) {
            $userEmail = $permission.User.ToString()
            
            # Skip if it's a system account or domain admin
            if ($userEmail -like "*\*" -or $userEmail -like "NT AUTHORITY\*" -or $userEmail -like "BUILTIN\*") {
                continue
            }
            
            # Check if this user is still a member or owner
            if ($allCurrentUsers -notcontains $userEmail) {
                try {
                    Remove-MailboxPermission -Identity $SharedMailbox -User $userEmail -AccessRights $permission.AccessRights -Confirm:$false -ErrorAction Stop
                    Log "Removed stale permission for user: $userEmail (Access: $($permission.AccessRights))"
                }
                catch {
                    Log "ERROR removing stale permission for $userEmail`: $_"
                }
            }
        }
    }
    catch {
        Log "ERROR checking existing permissions: $_"
    }

    # Remove stale folder permissions
    Log "----- Checking for stale folder permissions -----"
    try {
        $folderPermissions = Get-MailboxFolderPermission -Identity "$SharedMailbox" -ErrorAction Stop | 
            Where-Object { $_.User -notlike "Default" -and $_.User -notlike "Anonymous" -and $_.User -notlike "Owner@*" }
        
        foreach ($folderPermission in $folderPermissions) {
            $userEmail = $folderPermission.User.ToString()
            
            # Skip if it's a system account
            if ($userEmail -like "*\*" -or $userEmail -like "NT AUTHORITY\*" -or $userEmail -like "BUILTIN\*") {
                continue
            }
            
            # Check if this user is still a member or owner
            if ($allCurrentUsers -notcontains $userEmail) {
                try {
                    Remove-MailboxFolderPermission -Identity "$SharedMailbox" -User $userEmail -Confirm:$false -ErrorAction Stop
                    Log "Removed stale folder permission for user: $userEmail"
                }
                catch {
                    Log "ERROR removing stale folder permission for $userEmail`: $_"
                }
            }
        }
    }
    catch {
        Log "ERROR checking existing folder permissions: $_"
    }

    # Assign FullAccess to Owners
    foreach ($owner in $owners) {
        try {
            Add-MailboxPermission -Identity $SharedMailbox `
                                  -User $owner.PrimarySmtpAddress `
                                  -AccessRights FullAccess `
                                  -InheritanceType All `
                                  -AutoMapping:$true -ErrorAction Stop
            Log "Granted FullAccess to owner: $($owner.PrimarySmtpAddress)"
        }
        catch {
            Log "ERROR assigning FullAccess to $($owner.PrimarySmtpAddress): $_"
        }
    }

    # Assign ReadPermission to Members (if not also owner)
    foreach ($member in $members) {
        if ($ownerEmails -notcontains $member.PrimarySmtpAddress) {
            try {
                Add-MailboxPermission -Identity $SharedMailbox `
                                      -User $member.PrimarySmtpAddress `
                                      -AccessRights ReadPermission `
                                      -InheritanceType All `
                                      -AutoMapping:$false -ErrorAction Stop
                Log "Granted ReadPermission to member: $($member.PrimarySmtpAddress)"
            }
            catch {
                Log "ERROR assigning ReadPermission to $($member.PrimarySmtpAddress): $_"
            }
        }
    }

    # Add shared mailbox to Outlook for all members (owners and regular members)
    Log "----- Adding shared mailbox to members' Outlook -----"
    
    # Combine owners and members for mailbox folder access
    $allUsers = @()
    $allUsers += $owners
    $allUsers += $members | Where-Object { $ownerEmails -notcontains $_.PrimarySmtpAddress }
    
    foreach ($user in $allUsers) {
        try {
            # Add the shared mailbox to the user's mailbox folder list
            # This makes the shared mailbox appear in their Outlook client
            Add-MailboxFolderPermission -Identity "$SharedMailbox" `
                                      -User $user.PrimarySmtpAddress `
                                      -AccessRights Reviewer `
                                      -ErrorAction SilentlyContinue
            
            # Try to add the shared mailbox to user's additional mailbox list
            # This ensures it shows up in both Outlook Online and Desktop
            try {
                Set-MailboxFolderPermission -Identity "$SharedMailbox" `
                                          -User $user.PrimarySmtpAddress `
                                          -AccessRights Reviewer `
                                          -ErrorAction SilentlyContinue
            }
            catch {
                # Permission might already exist, which is fine
            }
            
            Log "Added shared mailbox to Outlook for user: $($user.PrimarySmtpAddress)"
        }
        catch {
            Log "ERROR adding shared mailbox to Outlook for $($user.PrimarySmtpAddress): $_"
        }
    }
    
    # Ensure AutoMapping is enabled for owners so the mailbox appears automatically
    Log "----- Configuring AutoMapping for owners -----"
    foreach ($owner in $owners) {
        try {
            Set-MailboxPermission -Identity $SharedMailbox `
                                -User $owner.PrimarySmtpAddress `
                                -AccessRights FullAccess `
                                -InheritanceType All `
                                -AutoMapping:$true `
                                -ErrorAction SilentlyContinue
            Log "Enabled AutoMapping for owner: $($owner.PrimarySmtpAddress)"
        }
        catch {
            Log "ERROR configuring AutoMapping for $($owner.PrimarySmtpAddress): $_"
        }
    }

    Log "----- Permission sync complete -----`n"
}
catch {
    Log "FATAL ERROR: $_"
    throw
}
