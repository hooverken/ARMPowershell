# Create-AzureImageBuilderTemplate.ps1
# by Ken Hoover <kendothooveratmicrosoftdotcom>
# September 2021

# This script implements the procedure described at 
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-powershell, with some enhancements,
# to create an Azure Image Builder template from an arbitrary source image publisher/offer/sku combination.


[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$imageTemplateName,  # no whitespace!
    [Parameter(Mandatory=$true)][String]$targetImageGalleryName,
    [Parameter(Mandatory=$true)][String]$imageDefinitionName,
    [Parameter(Mandatory=$true)][String]$sourceImagePublisher,
    [Parameter(Mandatory=$true)][String]$sourceImageOffer,
    [Parameter(Mandatory=$true)][String]$sourceImageSku,
    [Parameter(Mandatory=$true)][String]$myImagePublisher,
    [Parameter(Mandatory=$true)][String]$myImageOffer,
    [Parameter(Mandatory=$true)][String]$myImageSku, 
    [Parameter(Mandatory=$true)][ValidateSet("Windows","Linux")][String]$OSType,
    [Parameter(Mandatory=$true)][String]$RolePermissionsJSONFilePath 
)

### Sanity checking on inputs ###

# Make sure the target image gallery exists.  We can pull some useful stuff by knowing this too
Write-Verbose ("Getting Image Gallery Information...")
if (!($targetImageGallery = Get-AzGallery | where { $_.Name.Equals($targetImageGalleryName)}))
{
    Write-Error "Image Gallery $targetImageGalleryName not found."
    exit 
}

Write-Verbose "Making sure that the source image info points to a valid publisher/offer/sku..."
if (!(Get-AzVMImage -Location $targetImageGallery.Location -PublisherName $sourceImagePublisher -Offer $sourceImageOffer -skus $sourceImageSku -ErrorAction SilentlyContinue)) {
    write-warning ("A VM image with the publisher/offer/sku values $sourceImagePublisher/$sourceImageOffer/$sourceImageSku was not found in location " + $targetImageGallery.Location)
    exit 
}

write-verbose ("Targeting Image Gallery " + $targetImageGallery.Name + " in region " + $targetImageGallery.Location + " and RG " + $targetImageGallery.ResourceGroupName)

# Image Template names can't have whitespace so strip out any whitespace characters
$oldtemplatename = $imageTemplateName
$imageTemplateName = $imageTemplateName -replace '\s+', ''

if ($oldtemplatename -ne $imageTemplateName) { 
    write-warning "Image template names are not allowed to have whitespace."
    Write-Warning "Whitespace characters will be stripped from the provided image template name."
}

# Distribution properties of the managed image upon completion
$runOutputName = 'myDistResults'

# The Azure Subscription ID that is in focus right now
$subscriptionId = (Get-AzContext).Subscription.Id
Write-Verbose "Targeting subscription ID $subscriptionID"


# Create user identity (if it doesn't already exist)
$identityName = "KentosoAzureImageBuilderManagedUserIdentity"
if ($managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $identityName -ErrorAction SilentlyContinue) {
    Write-Verbose ("Using existing user assigned identity `"" + $managedIdentity.Name + "`"")
} else {
    write-verbose ("Creating managed user identity " + $identityName + " in RG " + $targetimageGallery.ResourceGroupName +"...")
    $managedIdentity = New-AzUserAssignedIdentity -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $identityName
    Write-Verbose "Waiting 30 seconds for new identity to settle in..."
    Start-Sleep -Seconds 30
    $managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $identityName
}

# Pull the role definition that we need to use.  If it doesn't exist, create it.

$imageRoleDefName = "Kentoso Azure Image Builder Role Definition"
if ($roleDefintionObj = Get-AzRoleDefinition -Name $imageRoleDefName -Scope "/subscriptions/$subscriptionId" -ErrorAction SilentlyContinue) {
    Write-verbose ("Using existing role definition " + $roleDefintionObj.Name)
} else {
    # Role definition does not exist so it needs to be created.
    Write-Verbose "Setting up custom role definition..."
    $tf = New-TemporaryFile
    $RolePermissionsObject = Get-Content "AzureImageBuilderRolePermissionsDefinition.json" | ConvertFrom-Json
    $RolePermissionsObject.Name = $imageRoleDefName
    $RolePermissionsObject.AssignableScopes = @("/subscriptions/$subscriptionId/resourceGroups/"+$targetImageGallery.ResourceGroupName)
    $RolePermissionsObject | ConvertTo-Json | Out-File $tf.FullName

    # Create a role definition for the identity to use and grant it to the SP
    Write-Verbose ("Creating new role definition `"" + $imageRoleDefName + "`" for this deployment...")
    $roleDefintionObj = New-AzRoleDefinition -InputFile $tf.FullName
    
    Write-verbose ("New Role Definition "+ $imageRoleDefName + " created.")
}

$managedIdentityPrincipalId = (Get-AzUserAssignedIdentity -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $identityName).PrincipalId
Write-Verbose ("Retrieved user assigned identity ID " + $managedIdentityPrincipalId)

# Verify that the role assignment exists for the managed identity.  If not, create the assignment
if ($RoleAssignmentObj = Get-AzRoleAssignment -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName $imageRoleDefName) {
    write-verbose "Role assignment for $imageRoleDefName is in place."
} else {
    # no role assignment for the custom role so we need to do the assignment
    $RoleAssignParams = @{
        ObjectId = $managedIdentityPrincipalId
        RoleDefinitionName = $roleDefintionObj.Name
        Scope = "/subscriptions/$subscriptionID/resourceGroups/"+$targetImageGallery.ResourceGroupName
    }
    Write-Verbose "Creating role assignment... "
    $RoleAssignmentObj = New-AzRoleAssignment @RoleAssignParams
}


Write-Verbose "Setting up image definition..."
# Check if the image definition specified already exists
if ($ImageDefinition = Get-AzGalleryImageDefinition -GalleryName $targetImageGallery.Name -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $imageDefinitionName -ErrorAction SilentlyContinue) {
    Write-Verbose ("Using existing Image definition $imageDefinitionName in gallery " + $targetImageGallery.Name)
} else {
    Write-Verbose ("Image definition $ImageDefinitionName does not exist, creating a new image definition...")
    # The specified image definition/gallery combo was not found so we need to create a new image definition
    $GalleryParams = @{
        GalleryName = $targetImageGallery.Name
        ResourceGroupName = $targetImageGallery.ResourceGroupName
        Location = $targetImageGallery.Location
        Name = $imageDefinitionName
        OsType = $OSType
        OsState = 'Generalized'
        Publisher = $myImagePublisher
        Offer = $myImageOffer
        Sku = $myImageSku
    }


    # Create the new image definition.  This requires the user to enter the publisher/offer/sku information for the new image

    $GalleryImageDefinition = New-AzGalleryImageDefinition @GalleryParams
}

$GalleryImageDefinition = Get-AzGalleryImageDefinition -GalleryName $targetImageGallery.Name -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $imageDefinitionName

# Create the source object for Image Builder
$SrcObjParams = @{
    SourceTypePlatformImage = $true
    Publisher = $sourceImagePublisher
    Offer = $sourceImageOffer
    Sku = $sourceImageSku
    Version = 'latest'
}
$ImageSource = New-AzImageBuilderSourceObject @SrcObjParams


# Create the distributor object
$disObjParams = @{
    SharedImageDistributor = $true
    ArtifactTag = @{tag='dis-share'}
    GalleryImageId = "/subscriptions/$subscriptionID/resourceGroups/"+$targetImageGallery.ResourceGroupName+"/providers/Microsoft.Compute/galleries/"+$targetImageGallery.Name+"/images/$imageDefinitionName"
    ReplicationRegion = $targetImageGallery.Location
    RunOutputName = $runOutputName
    ExcludeFromLatest = $false
}
$distributor = New-AzImageBuilderDistributorObject @disObjParams

# If this is Windows, set up a couple of Customizers
if ($OSType -eq "Windows") {
# Image builder customization Object
    $ImgCustomParams01 = @{
        PowerShellCustomizer = $true
        CustomizerName = 'settingUpMgmtAgtPath'
        RunElevated = $false
        Inline = @("mkdir c:\\buildActions", "mkdir c:\\buildArtifacts", "echo Created-With-Azure-ImageBuilder  > c:\\buildActions\\buildActionsOutput.txt")
    }
    $Customizer01 = New-AzImageBuilderCustomizerObject @ImgCustomParams01

    # And another one
    $ImgCustomParams02 = @{
        FileCustomizer = $true
        CustomizerName = 'downloadBuildArtifacts'
        Destination = 'c:\\buildArtifacts\\index.html'
        SourceUri = 'https://raw.githubusercontent.com/azure/azvmimagebuilder/master/quickquickstarts/exampleArtifacts/buildArtifacts/index.html'
    }
    $Customizer02 = New-AzImageBuilderCustomizerObject @ImgCustomParams02
}

# Create the image builder template
$ImgTemplateParams = @{
    ImageTemplateName = $imageTemplateName
    ResourceGroupName = $targetImageGallery.ResourceGroupName
    Source = $ImageSource
    Distribute = $distributor
    Location = $targetImageGallery.Location
    UserAssignedIdentityId = $managedIdentity.Id
}

# If this is Windows, add the customizers we created a moment ago
if ($OSType -eq 'Windows') {
    Customize = $Customizer01, $Customizer02
}

# Create template (this takes a minute or two...)
Write-Verbose "Checking if an image template with name $imageTemplateName already exists..."
if (Get-AzImageBuilderTemplate -ImageTemplateName $imageTemplateName -ResourceGroupName $targetImageGallery.ResourceGroupName -erroraction SilentlyContinue) {
    $title = "Image builder template `"$imageTemplateName`" already exists in Image Gallery `"" +$targetImageGallery.Name + "`""
    $prompt = "Do you want to replace it?"
    $replace = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes','Replaces the existing template'
    $cancel = New-Object System.Management.Automation.Host.ChoiceDescription '&No','Cancels  the operation'
    $options = [System.Management.Automation.Host.ChoiceDescription[]] ($replace,$cancel)
    $choice = $host.ui.PromptForChoice($title,$prompt,$options,0) # 0 = yes, 1 = no

    if ($choice -eq 0) {
        # Need to delete the existing template since we can't replace one directly.
        Write-Verbose "Removing existing template $imageTemplateName..."
        $result = Remove-AzImageBuilderTemplate -ImageTemplateName $imageTemplateName -ResourceGroupName $targetImageGallery.ResourceGroupName
        # Now create the new Image Builder template
        Write-Verbose "Creating new Image Builder template.  This may take a few minutes..."
        $newImageBuilderTemplate = New-AzImageBuilderTemplate @ImgTemplateParams
    } else { 
        # User chose not to replace the existing template so we're done.
        Write-Output "Existing template $imageTemplateName unchanged."
        exit
    }
} else {
    Write-Verbose "Creating Image Builder template.  This may take a few minutes..."
    # The template does not currently exist so just go ahead and create it
    $newImageBuilderTemplate = New-AzImageBuilderTemplate @ImgTemplateParams
}

# Ask user if they want to go ahead and build an image version from this definition right now
$title = "Would you like to go ahead and build an image version from this template?  Building an image version will take a while."
$prompt = "Create image version from template?"
$replace = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes','Build an image version from the new template'
$cancel = New-Object System.Management.Automation.Host.ChoiceDescription '&No','Do not build an image version now.'
$options = [System.Management.Automation.Host.ChoiceDescription[]] ($replace,$cancel)
$choice = $host.ui.PromptForChoice($title,$prompt,$options,0) # 0 = yes, 1 = no

if ($choice -eq 0) {
    # User chose to build a new image version
    Write-Output "Building new image version..."
    Start-AzImageBuilderTemplate -ResourceGroupName $targetImageGallery.ResourceGroupName -Name $newImageBuilderTemplate.Name | ft LastRunStatus,LastRunStatusMessage

} else {
    # Do nothing
}

Write-Verbose "Execution complete."

# Creating a VM from the image...
#$ArtifactId = (Get-AzImageBuilderRunOutput -ImageTemplateName $imageTemplateName -ResourceGroupName $imageResourceGroup).ArtifactId
#New-AzVM -ResourceGroupName $imageResourceGroup -Image $ArtifactId -Name myWinVM01 -Credential $Cred
