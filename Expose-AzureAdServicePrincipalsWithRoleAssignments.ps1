# expose-AzureAdServicePrincipalsWithRoles.ps1

# Ref: https://posts.specterops.io/azure-privilege-escalation-via-service-principal-abuse-210ae2be2a5
#      and https://www.nytimes.com/2021/10/25/us/politics/russia-cybersurveillance-biden.html

# Outputs all SPs that have a role assignment.

# Role assignments that offer an escalation path to GA are:

$RiskyRolesList = @("Application Administrator",
                "Authentication Administrator",
                "Azure AD joined device local administrator",
                "Cloud Application Administrator",
                "Cloud device Administrator",
                "Exchange Administrator",
                "Groups Administrator",
                "Helpdesk Administrator",
                "Hybrid Identity Administrator",
                "Intune Administrator",
                "Password Administrator",
                "Privileged Authentication Administrator",
                "User Administrator",
                "Directory Synchronization Accounts",
                "Partner Tier1 Support",
                "Partner Tier2 Support")

$riskyRolesList | % {
    $riskyRoleDefinitions = Get-AzureADDirectoryRole | where { $_.}
}

# Build our users and roles object
$UserRoles = Get-AzureADDirectoryRole | ForEach-Object {
        
    $Role = $_
    $RoleDisplayName = $_.DisplayName
        
    $RoleMembers = Get-AzureADDirectoryRoleMember -ObjectID $Role.ObjectID
        
    ForEach ($Member in $RoleMembers) {
    $RoleMembership = [PSCustomObject]@{
            MemberName      = $Member.DisplayName
            MemberID        = $Member.ObjectID
            MemberOnPremID  = $Member.OnPremisesSecurityIdentifier
            MemberUPN       = $Member.UserPrincipalName
            MemberType      = $Member.ObjectType
            RoleID          = $Role.RoleTemplateId
            RoleDisplayName = $RoleDisplayName
    }
    if ($RoleMembership.ObjectType -eq "ServicePrincipal") -and ()
        
    }    
}

if ($riskyRoleAssignments.count -gt 0) {
    Write-Warning "Service Principals with risky role assignments found.  Please check these carefully."
    $riskyRoleAssignments
} else {
    Write-Output "No Service Principals with risky role assignments found."
}