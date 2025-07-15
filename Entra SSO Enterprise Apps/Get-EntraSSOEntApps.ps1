<#
.SYNOPSIS
    Export all Azure AD Enterprise Applications configured for Single Sign-On to an Excel spreadsheet.

.DESCRIPTION
    This script connects to Microsoft Graph, retrieves all Enterprise Applications (Service Principals)
    with Single Sign-On configured, and exports relevant details to an Excel file.

.NOTES
    Requires Microsoft.Graph PowerShell module and Excel (or ImportExcel module for .xlsx export).
#>

# Install required modules if not present
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module ImportExcel -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Applications
Import-Module ImportExcel

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.Read.All"

# Get all Enterprise Applications (Service Principals)
$apps = Get-MgServicePrincipal -All

# Filter for SSO-enabled apps (those with SAML or OIDC SSO configured)
$ssoApps = $apps | Where-Object {
    $_.PreferredSingleSignOnMode -ne $null -and $_.PreferredSingleSignOnMode -ne "None"
}

# Select relevant properties
$export = $ssoApps | Select-Object DisplayName, AppId, PreferredSingleSignOnMode, PublisherName, AccountEnabled, Homepage, SignInAudience

# Export to Excel
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$excelPath = "EntraSSOEnterpriseApps_$timestamp.xlsx"
$export | Export-Excel -Path $excelPath -AutoSize -Title "Entra SSO Enterprise Apps"

Write-Host "Export complete: $excelPath"