# Restore-AzureVmToDifferentVnet.ps1
# by Ken Hoover <kendothooveratmicrosoftdotcom>

# Pulls a VM recovery point from a recovery valut and restores it to a different VM.
# During the VM creation process the provided VNET/Subnet information will be sunstituted for the original one.

# There are plenty of ways to move a VM to a diffrerent VNET -- most of them way less complex.  This one 
# lets you create a duplicate of a VM without needing to interrupt the original (as long as pulling the
# most recent restore point is acceptable).

# CHANGELOG
# 17 Oct 2022 - Initial version


[CmdletBinding()]

param (
    [Parameter(Mandatory=$true)][String]$VMName,  # VM name to restore
    [Parameter(Mandatory=$true)][String]$VaultName,  # Recoverty vault to restore it from
    [Parameter(Mandatory=$true)][String]$targetStorageAccount, # Storage account to hold the restored bits and config info
    [Parameter(Mandatory=$true)][String]$TargetResourceGroupName,    # RG to put the managed disk(s) in
    [Parameter(Mandatory=$true)][String]$NewVNETName,    # Name of the VNET to create the new VM on 
    [Parameter(Mandatory=$true)][String]$NewSubnetName  # Name of the subnet to create the new VM on
)

$backupLookbackDays = 90  # How far back to look for backup restore points to use.  I just picked this arbitrarily, deal with it.

Write-verbose ("Checking if VM `"$VMName`" already exists in RG $TargetResourceGroupName.")
if (Get-AzVM -Name $VMName -ResourceGroupName $targetresourcegroupname -ErrorAction SilentlyContinue) {
    Write-Error "Target VM already exists.  Please delete it and try again."
    exit
}

Write-Verbose ("Verifying that VNET `"$NewVNETName`" exists.")
if (-not($NewVNET = Get-AzVirtualNetwork | where { $_.name.equals($NewVNETName) })){
    Write-Warning "VNET $NewVNETName was not found.  Please check the name and try again."
    exit 
}

Write-Verbose ("Getting recovery vault `"$VaultName`"")
if (-not($vault = Get-AzRecoveryServicesVault | where { $_.name.Equals($VaultName) })) {
    Write-Warning "Vault $vault not found. Please check the name and try again."
    exit 
}

Write-Verbose ("Getting storage account `"$targetStorageAccount`"")
if (-not($storageAccount = Get-AzStorageAccount | where { $_.StorageAccountName.Equals($targetStorageAccount) })) {
    Write-Warning "Storage account $targetStorageAccount not found. Please check the name and try again."
    exit 
}

Write-Verbose ("Getting backup container for VM `"$vmName`"")
if (-not ($backupContainer = Get-AzRecoveryServicesBackupContainer  -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VMName -VaultId $vault.ID)) {
    Write-Warning "Backup container for $VMName not found.  Please make ure that it is being backed up in vault `"$vaultName`"."
    exit 
}

Write-Verbose ("Getting backup item for `"$vmName`"")
if (-not ($backupitem = Get-AzRecoveryServicesBackupItem -Container $backupContainer  -WorkloadType "AzureVM" -VaultId $vault.ID)) {
    Write-Warning "No backups found in container for $VMName.  Please make sure that it is being backed up in vault `"$vaultName`"."
    exit 
}

Write-Verbose ("Getting recovery points for `"$vmName`" in the last 90 days")
$startDate = (Get-Date).AddDays(0 - $backupLookbackDays)  # look back 90 days for recovery points.
$endDate = Get-Date
if (-not ($recoveryPointList = Get-AzRecoveryServicesBackupRecoveryPoint -Item $backupitem -StartDate $startdate.ToUniversalTime() -EndDate $enddate.ToUniversalTime() -VaultId $vault.ID)) {
    Write-Warning "No recovery points found for $VMName in the last $backupLookbackDays days."
    exit 
}

# choose the most recent recovery point
$mostRecentRecoveryPoint = ($recoveryPointList | Sort-Object -Property "RecoveryPointTime" -Descending)[0]

Write-output ("Most recent recovery point for VM `"$VMName`" in recovery vault "+ $vault.Name + " is " + $mostRecentRecoveryPoint.RecoveryPointTime)

# Set vault context
Write-Verbose ("Setting vault context to `"$vaultName`"")
$vaultContext = Set-AzRecoveryServicesVaultContext -Vault $vault

Write-Verbose ("Creating restore job for `"$vmName`".  This may take a minute or two.")
if (-not ($restorejob = Restore-AzRecoveryServicesBackupItem -RecoveryPoint $mostRecentRecoveryPoint -StorageAccountName $storageAccount.StorageAccountName  -StorageAccountResourceGroupName $storageAccount.ResourceGroupName -TargetResourceGroupName $TargetResourceGroupName -VaultId $vault.ID)) {
    Write-Warning "Restore job creation failed"
    exit 
}

Write-output ("Restore job for VM `"$VMName`" created with ID " + $restorejob.JobId)
$restoreResult = Wait-AzRecoveryServicesBackupJob -Job $restorejob -Timeout 43200

$duration = $restoreResult.StartTime - $restoreResult.StartTime
Write-Output ("RESTORE JOB COMPLETE with status `"" + $restoreResult.Status + "`".  Duration was $duration")

# When we get to here the recovery job has completed so now we can get details about the restored VM
Write-Verbose ("Getting backup job details")
$restorejob = Get-AzRecoveryServicesBackupJob -Job $restorejob -VaultId $vault.ID
$JobDetails = Get-AzRecoveryServicesBackupJobDetail -Job $restorejob -VaultId $vault.ID

# $templateBlobUri = $JobDetails.properties.'Template Blob Uri'
# Write-Verbose ("Template blob URI is $templateBlobUri")

# Get a SAS token for the blob (read only) so we can download it.  Validity time is only 5 minutes so it can't be stolen/reused easily
Write-Verbose ("Creating SAS token for template blob")
$storageContext = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName

# This returns a complete URI for the target object (because we're using the -FullUri option)
$sasToken = New-AzStorageBlobSASToken -Container $jobDetails.properties.'Config Blob Container Name' `
                                      -Blob $templateBlobUri.split("/")[-1] `
                                      -StartTime (Get-Date) `
                                      -ExpiryTime (Get-Date).AddMinutes(5) `
                                      -Context $storageContext `
                                      -Permission r `
                                      -FullUri

# Set up a parameters object for the VM deployment with the new VNET and subnet
Write-Verbose ("Setting parameter values")
$parametersObj = @{
    'VirtualMachineName' = $VMName
    'VirtualNetwork' = $NewVNet.Name
    'VirtualNetworkResourceGroup' = $newVnet.ResourceGroupName
    'Subnet' = $NewSubnetName
}

$parametersObj

# Kick off a deployment using the template and the customized parameters

Write-verbose ("Starting VM deployment")
$deployResult = New-AzResourceGroupDeployment -ResourceGroupName $TargetResourceGroupName -TemplateUri $sasToken -TemplateParameterObject $parametersObj -Verbose

$deployResult

# hope it worked!