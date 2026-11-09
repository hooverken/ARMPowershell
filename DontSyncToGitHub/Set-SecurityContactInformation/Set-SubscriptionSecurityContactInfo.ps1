
$uri = "https://management.azure.com/subscriptions/" + (Get-AzContext).Subscription.Id + "/providers/Microsoft.Security/securityContacts/default?api-version=2020-01-01-preview"
Invoke-RestMethod -Method PUT -Uri $uri -Headers (.\New-GraphAuthHeader.ps1) -Body (get-content .\settings.json)