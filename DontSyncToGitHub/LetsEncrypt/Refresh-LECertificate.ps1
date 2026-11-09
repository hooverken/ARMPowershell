# Refresh-LECErtificate.ps1
# by Ken Hoover <revooH.neK@tfosorcim.moc>
# Oct 2025

# Uses the Posh-ACME module to renew Let's Encrypt SSL certificates

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$domainName,
    [Parameter(Mandatory=$true)][string]$ownerEmailAddress,
    [Parameter(Mandatory=$true)][string]$pfxOutputPath,
    [Parameter(Mandatory=$true)][switch]$useStaging
)

# choose staging or production based on whether the useStaging switch is present
$acmeUrl = 'https://acme-staging-v02.api.letsencrypt.org/directory'

# Set the target environment to request the cert from
$result = Set-PAServer -Name $leEnvironment -ErrorAction Stop



