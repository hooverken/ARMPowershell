# ScheduledFileMoveToAzure.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
# January 2024

# *** EXAMPLE/DEMO CODE -- Not for production use ***

# See README.md for setup/usage instructions.

# Parameters.

[cmdletbinding()]
param (
    [Parameter(mandatory=$true)][string]$servicePrincipalCertFilePath,
    [Parameter(mandatory=$true)][string]$servicePrincipalCredsFile,
    [Parameter(mandatory=$true)][string]$tenantId,
    [Parameter(mandatory=$true)][string]$storageAccountName,
    [Parameter(mandatory=$true)][string]$containerName,
    [Parameter(mandatory=$true)][int]$MaxAgeDays,
    [Parameter(mandatory=$true)][string]$sourcePath
)

# The creds file has the SP's app ID as the username and the password for the .pfx file 
# as the password to keep it safe.
$cred = import-clixml $storageAccountCredsFile

if (-not($cred)) {
    throw "Unable to import credentials file $storageAccountCredsFile"
    exit
}

# Set up environment variables for azCopy auto-login using a SP
# Ref: https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-authorize-azure-active-directory#authorize-a-service-principal-by-using-a-certificate

$env:AZCOPY_AUTO_LOGIN_TYPE = 'SPN'
$env:AZCOPY_SPA_APPLICATION_ID = $cred.UserName
$env:AZCOPY_SPA_CERT_PATH = $servicePrincipalCertFilePath
$env:AZCOPY_SPA_CERT_PASSWORD = $cred.GetNetworkCredential().Password
$env:AZCOPY_TENANT_ID = $tenantId
$env:AZCOPY_LOG_LOCATION = ".\AzCopyLogs"  # Put log files in this subdirectory in case we need them later.

# Get the list of files in the target directory
$fileList = Get-ChildItem -Path $Path

# Create a new list consisting only of files that have not been modified in $MaxAgeDays
$filesToMove = $fileList | Where-Object { ($null -ne $_.Directory) -and ($_.LastWriteTime -lt ((Get-Date).AddDays(-$MaxAgeDays))) }

Write-Host "$($filesToMove.Count) files older than $MaxAgeDays days in `'$path`'."

# Create ISO8601-format timestamp since that's how AzCopy wants it :-/
$olderThanThis = ((Get-Date).AddDays(-$MaxAgeDays)).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Move the files in the target directory that are older than $olderThanThis to Azure using AzCopy (login is automagic)
.\azcopy copy ($Path+'\*') "https://$storageAccountName.blob.core.windows.net/$containerName" --include-before $olderThanThis
