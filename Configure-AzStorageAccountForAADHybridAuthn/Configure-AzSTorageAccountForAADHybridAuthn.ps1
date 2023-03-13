# Configure-AzStorageAccountForAzureAdAuthentication.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
# March 2023

# >> Script is WIP - DO NOT USE <<

# This script enables an Azure Storage account for Kerberos Authentication
# This is intended for use with FSLogix


[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,  # The name of the storage account to configure
    [Parameter(mandatory = $true)][string]$domainFQDN,      # The FQDN of the domain to configure, like "contoso.com"
    [Parameter(mandatory = $true)][PSCredential]$credentials       # The GUID (ObjectID) for the domain
)   

#

###############################################################################################
# Function below borrowed intact from https://gist.github.com/jkdba/54fd3a3222ee3bae1436028d54634e7a
function Invoke-URLInDefaultBrowser
{
    <#
        .SYNOPSIS
            Cmdlet to open a URL in the User's default browser.
        .DESCRIPTION
            Cmdlet to open a URL in the User's default browser.
        .PARAMETER URL
            Specify the URL to be Opened.
        .EXAMPLE
            PS> Invoke-URLInDefaultBrowser -URL 'http://jkdba.com'
            
            This will open the website "jkdba.com" in the user's default browser.
        .NOTES
            This cmdlet has only been test on Windows 10, using edge, chrome, and firefox as default browsers.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(
            Position = 0,
            Mandatory = $true
        )]
        [ValidateNotNullOrEmpty()]
        [String] $URL
    )
    #Verify Format. Do not want to assume http or https so throw warning.
    if( $URL -notmatch "http://*" -and $URL -notmatch "https://*")
    {
        Write-Warning -Message "The URL Specified is formatted incorrectly: ($URL)" 
        Write-Warning -Message "Please make sure to include the URL Protocol (http:// or https://)"
        break;
    }
    #Replace spaces with encoded space
    $URL = $URL -replace ' ','%20'
    
    #Get Default browser
    $DefaultSettingPath = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
    $DefaultBrowserName = (Get-Item $DefaultSettingPath | Get-ItemProperty).ProgId
    
    #Handle for Edge
    ##edge will no open with the specified shell open command in the HKCR.
    if($DefaultBrowserName -eq 'AppXq0fevzme2pys62n3e0fbqa7peapykr8v')
    {
        #Open url in edge
        Start-Process Microsoft-edge:$URL 
    }
    else
    {
        try
        {
            #Create PSDrive to HKEY_CLASSES_ROOT
            $null = New-PSDrive -PSProvider registry -Root 'HKEY_CLASSES_ROOT' -Name 'HKCR'
            #Get the default browser executable command/path
            $DefaultBrowserOpenCommand = (Get-Item "HKCR:\$DefaultBrowserName\shell\open\command" | Get-ItemProperty).'(default)'
            $DefaultBrowserPath = [regex]::Match($DefaultBrowserOpenCommand,'\".+?\"')
            #Open URL in browser
            Start-Process -FilePath $DefaultBrowserPath -ArgumentList $URL   
        }
        catch
        {
            Throw $_.Exception
        }
        finally
        {
            #Clean up PSDrive for 'HKEY_CLASSES_ROOT
            Remove-PSDrive -Name 'HKCR'
        }
    }
}

# Below function from Sven
function Set-AdminConsent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$applicationId,
        # The Azure Context]
        [Parameter(Mandatory)][object]$context
    )

    # $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
    #     $context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "74658136-14ec-4630-ad9b-26e160ff0fc6")

    $headers = @{
        'Authorization'          = 'Bearer ' + (Get-AzAccessToken).token
        'X-Requested-With'       = 'XMLHttpRequest'
        'x-ms-client-request-id' = [guid]::NewGuid()
    }

    $url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$applicationId/Consent?onBehalfOfAll=true"

    Invoke-RestMethod -Uri $url -Headers $headers -Method POST -ErrorAction Stop -verbose

}

######################### MAIN PROGRAM EXECUTION BEGINS BELOW ##############################


# Need to get the tenant ID, subscription ID and RG name.  We can reverse-engineer all of this just from
# the storage account name since storage account names must be globally unique

# Confirm that the storage account specified actually exists in this subscription
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

Write-Verbose ("Verifying that we can connect to the storage account")
if ($storageAccount) {
    $storageAccountResourceId = $storageAccount.Id
    Write-Verbose ("Storage account $storageAccountName resource ID is $storageAccountResourceId")
} else {
    Write-Warning ("Storage account $storageAccountName not found in current subscription.")
    exit
}

$domainInformation = Get-ADDomain -Credential $credentials -Server $domainFQDN
$domainGuid = $domainInformation.ObjectGUID.ToString()
$domainName = $domainInformation.DnsRoot

# Enable the storage account for Azure AD Kerberos authentication
Set-AzStorageAccount -ResourceGroupName $storageAccount.ResourceGroupName -StorageAccountName $storageAccount.StorageAccountName -EnableAzureActiveDirectoryKerberosForFile $true -ActiveDirectoryDomainName $domainName -ActiveDirectoryDomainGuid $domainGuid

$application = Get-AzADApplication | where { $_.DisplayName.contains($storageAccount.PrimaryEndpoints.File.split('/')[2])}
$ApplicationID = $application.AppId

$msGraphApplicationObjectId
$params = @{
    "ClientId" = $ApplicationID                             # Storage account's SP
    "ConsentType" = "AllPrincipals"                         # Grant to all principals
    "ResourceId" = (Get-MgContext).ClientId                 # Microsoft Graph GUID
    "Scope" = "openid profile User.Read"                    # Permission to grant
  }

New-MgOauth2PermissionGrant -BodyParameter $params | 
    Format-List Id, ClientId, ConsentType, ResourceId, Scope


# Verify that it worked
$filter = "clientId eq $ApplicationId consentType eq 'AllPrincipals'"
Get-MgOauth2PermissionGrant -Filter $filter

# Set-AdminConsent -applicationId $ApplicationID -context (Get-AzContext)


# We need to grant permission to the newly created App to read the logged-in user's information.

# $application = Get-AzADApplication | where { $_.DisplayName.contains($storageAccount.storageAccountName)}
# $ApplicationID = $application.AppId
# $tenantId = (Get-AzContext).Tenant.Id
# $consentGrantUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?client_id=$ApplicationID&response_type=code&redirect_uri=http%3A%2F%2Fwww.microsoft.com&response_mode=query&scope=User.Read&state=12345"

# I spent a bunch of time trying to figure out how to do this with the Graph API but decided to
# do it this way so I can get this script out sooner.  I'm going to keep working on finding a way to just
# "make it happen" during script execution but there doesn't seem to be an easy way to do it.

# $msgTitle = "Permission grant required"
# $msgBody = "You must log in as a global admin account on the next screen in order to grant the $storageAccountName application permission to read the logged-in user's information.  Once you've done that, the process will be complete.  Do you want to do this now?"
# Add-Type -AssemblyName PresentationCore,PresentationFramework
# $msgButton = 'YesNo'
# $msgImage = 'Question'
# $Result = [System.Windows.MessageBox]::Show($msgBody,$msgTitle,$msgButton,$msgImage)
# if ($Result -eq "Yes") {
#     # Bring up the application consent page in the default browser so the user can grant consent.
#     Invoke-URLInDefaultBrowser -URL $consentGrantUrl
# } else {
#     # The user clicked no so put URL they need to go to on the clipboard and notify them.
#     $msgTitle = "URL copied to clipboard"
#     $msgBody = "The URL to grant permission has been copied to the clipboard.  Please paste it into your browser and grant consent."
#     Add-Type -AssemblyName PresentationCore,PresentationFramework
#     $msgButton = 'OK'
#     $msgImage = 'Warning'
#     $Result = [System.Windows.MessageBox]::Show($msgBody,$msgTitle,$msgButton,$msgImage)
#     Set-Clipboard $consentGrantUrl  # put the grant consent URL on the clipboard so user can paste it.
#     Write-Warning ("Admin Consent must still be granted to the storage account $storageAccountName.  Please visit $url to complete the process.  The URL has been copied to the clipboard.")
# }

