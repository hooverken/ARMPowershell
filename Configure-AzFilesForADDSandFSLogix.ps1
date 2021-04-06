# Configure-AzFilesForADDSAndFSLogix.ps1
# Configure an Azure Files share for authentication using ADDS Authentication
# Plus permission customization for use with FSLogix

# Original version by John Kelbley <johnkel at Microsoft dotcom>
# Scriptified/Parameterized by Ken Hoover <ken dot hoover at Microsoft dotcom>

# December 2020

###############################################################################################################
#  This is the "Manual" process to configure AD authentication for Azure Files
#  (automated!)
#
#  Assumes:
#	* You are running this script as a user that can create a new object in the target AD
#   * You have the "Az" and "AzureADPreview" modules installed
#   * You are connected via Connect-AzAccount as a user with rights to manually add roles and create Azure files shares
#   * You have connected to the target AzureAD environment using Connect-AzureAD
#	* An OU in the local AD has been identified for the new computer object
#	* You have AAD synced to AD (have you confirmed this is working?)
#	* You are executing this script on a domain joined VM as a user with computer account add rights
#   * The storage account name you are using is LESS THAN 15 characters long
# 
# Process here:  https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable
#
###############################################################################################################
#
# CHANGELOG
#
# 11 Jan 2021  : Find storageAccountRGName for ourselves instead of forcing the user to provide it.
# 19 March 2021: Add connection test for 445/TCP
#
#
############################################################################
# Required parameters - make sure you have all of this info ahead of time
############################################################################
#
[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,      # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$profileShareName,        # The name of the profiles share.  The share will be created if it doesn't exist.
    [Parameter(mandatory = $true)][string]$ADOuDistinguishedName,   # The full DN of the OU to put the new computer object in
    [Parameter(mandatory = $true)][string]$ShareAdminGroupName,     # the name of an AD group which will have elevated access to the profile share
    [Parameter(mandatory = $true)][string]$ShareUserGroupName,      # the name of an AD group which will have normal access to the profile share
    [Parameter(mandatory = $false)][switch]$IsGovCloud              # MUST add this parameter if you're working in Azure Gov Cloud, otherwise don't use it
)

# Some sanity checks before we get started

# Make sure we are connected to Azure
Write-Verbose ("Verifying that we are connected to Azure...")
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
    exit
}

# Make sure this is Azure Commercial Cloud or Azure Gov Cloud since this script doesn't understand other clouds
switch ($currentContext.Environment) {
    "AzureCloud" { Write-Verbose ("Connected to Azure Commercial Cloud ("+$currentContext.Environment + ")")}
    "AzureUSGovernment" { Write-Verbose ("Connected to Azure US Gov Cloud ("+$currentContext.Environment + ")")}
    "default" { Write-Warning "This script only understands Azure Commercial cloud and US Gov cloud, sorry." ; exit}
}

# Make sure we're connected to Azure AD
Write-Verbose ("Verifying that we are connected to Azure AD...")
try { 
    $result = Get-AzureADTenantDetail 
} 
catch [Microsoft.Open.Azure.AD.CommonLibrary.AadNeedAuthenticationException] { 
    Write-Warning "You must conenct to Azure AD using Connect-AzureAD before running this script " 
    exit
}

# Storage account name needs to be <= 15 characters to avoid risk of hitting legacy NetBIOS limits in AD
if ($storageAccountName.Length -ge 15) {
    write-warning ("Storage account name (" + $storageAccountName + ") is >= 15 characters.  Please use a shorter name to avoid issues.")
    exit
}

# Share names in Azure Files must be all lowercase so force whatever the user entered to lowercase.
# ref: https://docs.microsoft.com/en-us/rest/api/storageservices/Naming-and-Referencing-Shares--Directories--Files--and-Metadata
$profilesharename = $profilesharename.ToLower()

# Confirm that the storage account specified actually exists and populate storageAccountRGName
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

Write-Verbose ("Verifying that we can connect to the storage account")
if ($storageAccount) {

    # Grab the RG name that the storage account is in since we'll need it.
    $storageAccountRGName = $storageaccount.ResourceGroupName

    # Verify that we can connect to the storage account's files endpoint on port 445
    Write-Verbose ("Testing connectivity to " + $storageAccount.PrimaryEndpoints.File + " on port TCP/445...")
    if ($storageAccount.PrimaryEndpoints.File -match '\/\/(\S+)\/') {
        if (Test-NetConnection -port 445 -ComputerName $matches[1] -InformationLevel Quiet) {
            write-verbose ("Connection test to " + $matches[1] + " on port TCP/445 successful.")
        } else {
            write-warning ("Unable to connect to " + $matches[1] + " on port 445.  Please check for firewall blocks.  Exiting.")
            exit 
        }
    }

    # Create a Kerberos key for the storage account to use with ADDS
    write-verbose ("Creating Kerberos key for storage account $storageAccountName")
    New-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -name $storageAccountName -KeyName kerb1 | Out-Null
    $Keys = get-azstorageaccountkey -ResourceGroupName $storageAccountRGName -Name $storageAccountName -listkerbkey
    $kerbkey = $keys | where-object {$_.keyname -eq 'kerb1'} 
    $CompPassword = $kerbkey.value | ConvertTo-Securestring -asplaintext -force
} else {
    Write-Warning ("Storage account $storageAccountName not found.")
    exit
}

#################################
#Step 2 Create Computer Account and SPN, and get AD information
#################################

# AD Settings - You will want to run to following to get all the parameters you need:
$Forest = get-adforest
$Domain = get-ADdomain

if ((!($Forest)) -or (!($Domain))) {
    write-error ("Unable to get domain/forest information from ADDS. Exiting.")
    exit
}

# For Azure Commercial
# SPN should look like:		cifs/your-storage-account-name-here.file.core.windows.net	
# For Gov looks like:		cifs/your-storage-account-name-here.file.core.usgovcloudapi.net 
#
if ($isGovCloud)  {
	$SPN = "cifs/$storageAccountName.file.core.usgovcloudapi.net" 
} Else { 
	$SPN = "cifs/$storageAccountName.file.core.windows.net" 
}

Write-Verbose "SPN for new account will be $SPN"

if (Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName) {

    # Make sure the target OU DN actually exists just to make sure
    $OUlist = get-adobject -filter 'ObjectClass -eq "organizationalUnit"'
    if ($oulist.distinguishedName -contains $ADOuDistinguishedName) {
        if (get-ADComputer -Filter { Name -eq $storageAccountName } -ErrorAction SilentlyContinue) {
            write-verbose ("Computer object $storageAccountName already exists in AD.")
        } else {
            # The computer object doesn't exist in AD so we will create it.
            write-verbose ("Creating computer object in AD...")
            $result = New-ADComputer -name $storageAccountName `
                -path $ADOUDistinguishedName `
                -Description "DO NOT DELETE - Azure File Share" `
                -ServicePrincipalNames $SPN `
                -PasswordNeverExpires $true `
                -OperatingSystem "Azure Files" `
                -AccountPassword $CompPassword
        }
    } else {
        write-warning ("OU `"$ADOuDistinguishedName`" not found.")
        exit
    }
} else {
    write-warning ("Storage account $storageAccountName not found in RG $storageAccountRGName. Exiting")
}

write-verbose "Reading computer object from AD..."
try {
    $Computer = get-ADComputer $storageAccountName  # The computer object in AD for the share.
}
catch {
    write-warning "Unable to retrieve computer object $storageAccountName from AD."
    exit
}

# if you fail to create the account, it could be rights (often), but commonly the DN for the OU is wrong (folks guess at it!)
# check to see what the DN actually is either in ADUC or pull all the OUs with the following command:
# 	get-adobject -filter 'ObjectClass -eq "organizationalUnit"'

##################################################################
# Step 3 update Storage account in Azure to use AD Authentication
##################################################################
#
# Set the feature flag on the target storage account and provide the required AD domain information
write-verbose ("Configuring storage account $storageAccountName for ADDS Authentication...")
$updateresult = Set-AzStorageAccount `
        -ResourceGroupName $storageAccountRGName `
        -Name $storageAccountName `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $Domain.dnsroot `
        -ActiveDirectoryNetBiosDomainName $Domain.netbiosname `
        -ActiveDirectoryForestName $Forest.name `
	    -ActiveDirectoryDomainGuid $Domain.ObjectGUID `
        -ActiveDirectoryDomainsid $Domain.DomainSID `
        -ActiveDirectoryAzureStorageSid $Computer.sid

if (!($updateresult)) {
    write-warning "Error occurred while updating the storage account.  Exiting."
    exit 
}

#################################
#Step 4 Confirm settings
#################################

#
# Get the target storage account
$storageaccount = Get-AzStorageAccount -ResourceGroupName $storageAccountRGName -Name $storageAccountName

if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account $storageAccountName is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account configuration does not match expectations.  Please check and try again.")
    exit 
}


#####################################################
# Step 5 Set Azure Roles (share) security
#####################################################
#
################################################################################
#
#  Add Share-level permissions as per https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-assign-permissions
#
#  Users should have "Storage File Data SMB Share Contributor" and Admins "Storage File Data SMB Share Elevated Contributor"  
#

Write-verbose ("Setting storage context for role assignment...")

$storageAccountKey = (get-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -Name $storageAccountName)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

# Check if the share exists.  If not, create it.
Write-Verbose ("Checking if share $profileShareName exists in storage account $storageAccountName...")
if (!(get-AzStorageShare -Name $profileShareName -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share $profileShareName does not exist.  Creating new share $profileShareName...")
    New-AzStorageShare -Name $profileShareName -Context $storageContext
} else {
    write-verbose ("Share $profileShareName is present (OK)")
}

Write-Verbose ("Assigning IAM roles for access to the $profileShareName share...")

if (Get-AdGroup -Identity $ShareAdminGroupName) {
    write-verbose ("Getting ObjectID for AAD group $ShareadminGroupName...")
    $filter = "Displayname eq '$ShareAdminGroupName'"
    $elevatedContributorObjectId = (Get-AzureADGroup -filter $filter).ObjectId
    if ($true -ne $?) {
        write-warning ( "Error retrieving information for group $ShareAdminGroupName.  Check the name and try again.")
        exit
    }
    write-verbose("Object ID for AAD group $ShareAdminGroupName is $elevatedContributorObjectId")
} else {
    write-warning "Group $ShareAdminGroupName not found in AD!"
    exit 
}

if (get-AdGroup -Identity $ShareUserGroupName) {
    write-verbose ("Getting ObjectID for AAD group $ShareUserGroupName...")
    $filter = "Displayname eq '$ShareUserGroupName'"
    $ContributorObjectId = (Get-AzureADGroup -filter $filter).ObjectId
    if ($true -ne $?) {
        write-warning ( "Error retrieving information for group $ShareUSerGroupName.  Check the name and try again.")
        exit
    }
    write-verbose("Object ID for AAD group $ShareUserGroupName is $ContributorObjectId")
} else {
    write-warning "Group $ShareUserroupName not found in AD!"
    exit 
}

# Assign SMB Contributor role to users on the share and the elevated contributor role to admins
$scope = (Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName).Id + "/fileservices/default/fileshares/" + $profileShareName

write-verbose ("Assigning role `Storage File Data SMB Share Contributor to ObjectID $ContributorObjectID...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Contributor" -Scope $scope -ObjectId $ContributorObjectId

write-verbose ("Assigning role `Storage File Data SMB Share Elevated Contributor to ObjectID $elevatedContributorObjectID...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" -Scope $scope -ObjectId $elevatedContributorObjectId


################################
#Step 6 Map Drive with storage Key / Set NTFS permissions on root
#################################
#
#  Here's what I've been using specific to WVD / FSLogix
#

#below needed for setting NTFS rights on file system - can also do manually
$ShareName		= $profileShareName
$drive 			= "Y:"
$path = $Drive + "\"
$Mapkey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -Name $storageAccountName).value[0]

################################
# Note that the next line is for Azure Commercial - must change DNS suffix for gov and other soverign clouds
#   Azure Gov:  .file.core.usgovcloudapi.net
################################
if ($isGovCloud) {
    $MapPath = "\\"+$storageAccountName+".file.core.usgovcloudapi.net\"+$sharename
} else {
    $MapPath = "\\"+$storageAccountName+".file.core.windows.net\"+$sharename
}

write-verbose ("Mounting the $profileShareName share...")
$result = new-smbmapping -LocalPath $drive -RemotePath $MapPath -UserName $storageAccountName -Password $Mapkey -Persistent $false

if (!($result.status -eq "OK")) {
    write-warning "Attempt to map path $MapPath failed."
    exit 
}

Write-verbose ("Successfully mounted $MapPath as drive $drive")

##############################################################
#  Let's list out the ACLs on the screen so we see what's there already
##############################################################
$acl = Get-Acl $path
# $acl.Access | where IsInherited -eq $false #Gets all non inherited rules.

# from https://blog.netwrix.com/2018/04/18/how-to-manage-file-system-acls-with-powershell-scripts/
##############################################################
# clears existing users rights (for Azure Files)
##############################################################
write-verbose ("Removing Users...")
$acl = Get-Acl $path
$usersid = New-Object System.Security.Principal.Ntaccount ("Users")
$acl.PurgeAccessRules($usersid)
$acl | Set-Acl $path

## used information from https://win32.io/posts/How-To-Set-Perms-With-Powershell

#############################################################
# adding my admin user - YOU DON'T NEED THIS, but might want your admin here!
# Commented out for reference or future use
#############################################################
# $acl = Get-Acl $path
# $rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $AdAdminUPN, "FullControl", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
# $acl.SetAccessRule($rule)
# $acl | Set-Acl -Path $path

#############################################################
# set " Domain Administrators / Subfolders and Files Only / Modify
#############################################################
write-verbose ("Adding Admins...")
$Admins = $Domain.netbiosname + "\Domain Admins"
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $admins, "FullControl", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

# set "Users / This Folder Only / Modify
write-verbose ("Adding Authenticated Users...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "NT AUTHORITY\Authenticated Users", "Modify,Synchronize", "None", "None", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

# set "Creator Owner / Subfolders and Files Only / Modify
write-verbose ("Adding CREATOR OWNER...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "CREATOR OWNER", "Modify,Synchronize", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

##############################################################
#  Uncomment to list out the resulting ACL on the share.
##############################################################
# $acl = Get-Acl $path
# $acl.Access | where IsInherited -eq $false #Gets all non inherited rules.

Write-Verbose ("Disconnecting from file share...")
# Disconnect the mounted file share
Remove-SmbMapping -LocalPath $drive -Force

Write-Verbose ("Execution complete.")