# Configure-AzStorageAccountForAzureAdAuthentication.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
# March 2022

# >> Script is currently BROKEN - DO NOT USE AS IS <<

# This script walks through the process for configuring an Azure Files share to use Azure AD Authentication
# as described at this link https://docs.microsoft.com/en-us/azure/virtual-desktop/create-profile-container-azure-ad

# This feature is currently (March 2022) in PREVIEW.

# Most of the code on this page came directly from the above link.

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName  # The name of the storage account to configure
)


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
        [Parameter(Mandatory)]
        [string]$applicationId,
        # The Azure Context]
        [Parameter(Mandatory)]
        [object]$context
    )

    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "74658136-14ec-4630-ad9b-26e160ff0fc6")

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

# Confirm that the storage account specified actually exists
# Yes, this method is slow but it means that we don't need to ask the user for the resource group name of the storage account
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

$storageAccountResourceGroupName = $storageAccountResourceId.Split("/")[4]
$storageAccountSubscriptionId = $storageAccountResourceId.Split("/")[2]
Write-Verbose ("Storage account $storageAccountName is in resource group $storageAccountResourceGroupName")
Write-Verbose ("Storage account $storageAccountName is in subscription $storageAccountSubscriptionId")

Write-Verbose ("Retriving the tenant ID for subscription $storageAccountSubscriptionId")
$storageAccountSubscription = Get-AzSubscription -SubscriptionId $storageAccountSubscriptionId
Write-Verbose ("Tenant ID for subscription $storageAccountSubscriptionId is " + $StorageAccountSubscription.tenantId.toString())

# Now we can configure the storage account for AzureAD Authentication
# Connect-AzAccount -Tenant $storageaccountsubscription.TenantId -SubscriptionId $storageAccountSubscription.Id

$Uri = ('https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Storage/storageAccounts/{2}?api-version=2021-04-01' -f $storageAccountSubscriptionId, $storageAccountResourceGroupName, $storageAccountName);

$json = @{properties=@{azureFilesIdentityBasedAuthentication=@{directoryServiceOptions="AADKERB"}}};
$json = $json | ConvertTo-Json -Depth 5

$token = $(Get-AzAccessToken).Token
$headers = @{ Authorization="Bearer $token" }

try {
    $result = Invoke-RestMethod -Uri $Uri -ContentType 'application/json' -Method PATCH -Headers $Headers -Body $json
} catch {
    Write-Host $_.Exception.ToString()
    Write-Error -Message "Caught exception setting Storage Account directoryServiceOptions=AADKERB: $_" -ErrorAction Stop
}

if ($result.properties.azureFilesIdentityBasedAuthentication.directoryServiceOptions -eq "AADKERB") {
    Write-Verbose ("Successfully set directoryServiceOptions to AADKERB for Storage Account $storageAccountName")
} else {
    Write-Warning ("Failed to set directoryServiceOptions to AADKERB for Storage Account $storageAccountName")
    Exit
}
 
# Generate the kerb1 key for the storage account and apply it.
Write-Verbose ("Generating the kerb1 key for storage account $storageAccountName")
New-AzStorageAccountKey -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName -KeyName kerb1 -ErrorAction Stop | Out-Null
$kerbKey1 = Get-AzStorageAccountKey -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName -ListKerbKey | Where-Object { $_.KeyName -like "kerb1" }
Write-Verbose ("Successfully generated the kerb1 key for storage account $storageAccountName")
$aadPasswordBuffer = [System.Linq.Enumerable]::Take([System.Convert]::FromBase64String($kerbKey1.Value), 32);
$KerbPassword = "kk:" + [System.Convert]::ToBase64String($aadPasswordBuffer);

Write-Verbose ("KerbPassword for storage account $storageAccountName is " + $KerbPassword.Substring(0,10) + "...")

# Now we need to create an Azure AD application ID and SPN for the storage account

Write-Verbose ("Identifying the default domain for tenant " + $storageAccountSubscription.tenantId)
if (!($azureAdTenantDefaultDomain = (get-aztenant -TenantId $storageAccountSubscription.tenantId).extendedproperties.defaultDomain)) {
    Write-Warning ("No default domain found in current subscription.  Please create one and try again.")
    exit
} else {
    Write-Verbose ("Default domain for tenant ID " + $storageAccountSubscription.tenantId + " is " + $azureAdTenantDefaultDomain)
}

# Generate SPN's for the storage account
$servicePrincipalNames = New-Object string[] 3
$servicePrincipalNames[0] = 'HTTP/{0}.file.core.windows.net' -f $storageAccountName
$servicePrincipalNames[1] = 'CIFS/{0}.file.core.windows.net' -f $storageAccountName
$servicePrincipalNames[2] = 'HOST/{0}.file.core.windows.net' -f $storageAccountName

$spnList = $servicePrincipalNames[0] + "," + $servicePrincipalNames[1] + "," + $servicePrincipalNames[2]

Write-Verbose ("Generated SPN's for storage account $storageAccountName are " + $servicePrincipalNames[0] + ", " + $servicePrincipalNames[1] + ", " + $servicePrincipalNames[2])

# Create the AAD Application
Write-Verbose ("Creating AAD Application for storage account")
$application = New-AzADApplication -DisplayName $storageAccountName -IdentifierUris $servicePrincipalNames

# Create the SP for the storage account
Write-Verbose ("Creating Service Principal for storage account")
$servicePrincipal = New-AzADServicePrincipal -AppId $application.AppId -ServicePrincipalType "Application" -AccountEnabled -ServicePrincipalName $servicePrincipalNames
if ($servicePrincipal) {
    Write-Verbose ("Successfully created Service Principal for storage account $storageAccountName")
    # Write-verbose ("Setting SPN's for Service Principal $storageaccountname")
    # Update-AzADServicePrincipal -ObjectId $servicePrincipal.Id -ServicePrincipalName $spnList
} else {
    Write-Warning ("Failed to create Service Principal for storage account $storageAccountName")
    Exit
}

exit

# Set the password for the SP
Write-Verbose ("Setting SP password for storage account $storageAccountName")
$newCredential = New-AzADSpCredential -ServicePrincipalObjectId $servicePrincipal.Id
exit 
# $Token = (Get-AzAccessToken).AccessToken
$Uri = ('https://graph.windows.net/{0}/{1}/{2}?api-version=1.6' -f $azureAdPrimaryDomain, 'servicePrincipals', $servicePrincipal.ObjectId)
$json = @'
{
  "passwordCredentials": [
  {
    "customKeyIdentifier": null,
    "endDate": "<STORAGEACCOUNTENDDATE>",
    "value": "<STORAGEACCOUNTPASSWORD>",
    "startDate": "<STORAGEACCOUNTSTARTDATE>"
  }]
}
'@
$now = [DateTime]::UtcNow
$json = $json -replace "<STORAGEACCOUNTSTARTDATE>", $now.AddDays(-1).ToString("s")
$json = $json -replace "<STORAGEACCOUNTENDDATE>", $now.AddMonths(6).ToString("s")
$json = $json -replace "<STORAGEACCOUNTPASSWORD>", $password

$token = $(Get-AzAccessToken).Token
$headers = @{ Authorization="Bearer $token" }

Write-Verbose ("Calling Graph API to set SP password for storage account $storageAccountName")
try {
  Invoke-RestMethod -Uri $Uri -ContentType 'application/json' -Method Patch -Headers $Headers -Body $json 
  Write-Host "Success: Password is set for $storageAccountName"
} catch {
  Write-Host $_.Exception.ToString()
  Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value
  Write-Host "StatusDescription: " $_.Exception.Response.StatusDescription
}

exit 

# Now here's the stuff that's not on the web page.
# We need to grant permission to the newly created App to read the logged-in user's information.

$ApplicationID = $application.AppId
$consentGrantUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?client_id=$ApplicationID&response_type=code&redirect_uri=http%3A%2F%2Fwww.microsoft.com&response_mode=query&scope=User.Read&state=12345"

# I spent a bunch of time trying to figure out how to do this with the Graph API but decided to
# do it this way so I can get this script out sooner.  I'm going to keep working on inding a way to just
# "make it happen" during script execution but there doesn't seem to be an easy way to do it.

$msgTitle = "Permission grant required"
$msgBody = "You must log in as a global admin account on the next screen in order to grant the $storageAccountName application permission to read the logged-in user's information.  Once you've done that, the process will be complete.  Do you want to do this now?"
Add-Type -AssemblyName PresentationCore,PresentationFramework
$msgButton = 'YesNo'
$msgImage = 'Question'
$Result = [System.Windows.MessageBox]::Show($msgBody,$msgTitle,$msgButton,$msgImage)
if ($Result -eq "Yes") {
    # Bring up the application consent page in the default browser so the user can grant consent.
    Invoke-URLInDefaultBrowser -URL $consentGrantUrl
} else {
    # The user clicked no so put URL they need to go to on the clipboard and notify them.
    $msgTitle = "URL copied to clipboard"
    $msgBody = "The URL to grant permission has been copied to the clipboard.  Please paste it into your browser and grant consent."
    Add-Type -AssemblyName PresentationCore,PresentationFramework
    $msgButton = 'OK'
    $msgImage = 'Warning'
    $Result = [System.Windows.MessageBox]::Show($msgBody,$msgTitle,$msgButton,$msgImage)
    Set-Clipboard $consentGrantUrl  # put the grant consent URL on the clipboard so user can paste it.
    Write-Warning ("Admin Consent must still be granted to the storage account $storageAccountName.  Please visit $url to complete the process.  The URL has been copied to the clipboard.")
}

