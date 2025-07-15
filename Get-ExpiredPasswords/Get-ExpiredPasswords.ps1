
param (
    [Parameter(Position = 0)]
    [string]
    $Server
)
    
$Today = Get-date -DisplayHint Date
$ExpiryList = Get-ADUser -Server $Server -filter { Enabled -eq $True -and PasswordNeverExpires -eq $False } –Properties "DisplayName", "msDS-UserPasswordExpiryTimeComputed" | 
Select-Object -Property "Displayname", @{Name = "ExpiryDate"; Expression = { [datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed") } } | 
Where-Object -Property ExpiryDate -lt $Today

$ExpiryList | Sort-Object -Property ExpiryDate | Format-Table
