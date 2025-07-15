function Get-UsersSSOApps {
    <#
    .SYNOPSIS
    Retrieves the list of applications a user logs into using Single Sign-On (SSO) through Entra ID.

    .DESCRIPTION
    This function queries Entra ID (Azure AD) to determine the applications a specified user has accessed using Single Sign-On (SSO).

    .PARAMETER UserPrincipalName
    The User Principal Name (UPN) of the user to query.

    .EXAMPLE
    Get-UsersSSOApps -UserPrincipalName "user@domain.com"

    .NOTES
    Requires the Microsoft.Graph module.
    #>

    param (
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName
    )

    # Ensure the Microsoft.Graph module is imported
    if (-not (Get-Module -Name Microsoft.Graph)) {
        Import-Module Microsoft.Graph
    }

    # Connect to Microsoft Graph if not already connected
    if (-not (Get-MgContext)) {
        Connect-MgGraph -Scopes "AuditLog.Read.All"
    }

    try {
        # Get the date 30 days ago in ISO 8601 format
        $startDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $filter = "userPrincipalName eq '$UserPrincipalName' and createdDateTime ge $startDate"

        # Get the user's sign-in logs for the last 30 days, only needed properties
        $signInLogs = Get-MgAuditLogSignIn -Filter $filter -Top 500 | Select-Object AppDisplayName

        $apps = $signInLogs | Select-Object -ExpandProperty AppDisplayName | Sort-Object -Unique

        return $apps
    } catch {
        Write-Error "Failed to retrieve SSO applications for user $UserPrincipalName $_"
    }
}