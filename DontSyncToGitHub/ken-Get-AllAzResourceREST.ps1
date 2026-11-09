function Get-AllAzGraphResourceREST {
# by Ken Hoover <ken.hoover@microsoft.com>
# 3 August 2024
# This function executes Resource Graph queries by directly calling the API so 
# hopefully it's faster than Get-AllAzGraphResource (above) which does it all with Powershell
# 
# Assumes that an Azure context is present

    param (
    [string[]]$subscriptionId,
    [string]$query = 'Resources | project id, resourceGroup, subscriptionId, name, type, location'
    )

    # Generate the header and bearer token from the current context
    $headers = @{
        "Authorization" = "Bearer " + (Get-AzAccessToken).token
        "Content-Type" = "application/json"
    }

    # The body (payload) to send with the API call.  This is the Graph query to execute.
    $body = @{
        query = $query
    }

    # Azure Resource Graph URI
    $uri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"

    $allResources = @() ; $pageCounter = 1
    do {

    # Yes this needs better error handling.
    try {
        $results = Invoke-RestMethod -Uri $uri -Headers $headers -Body ($body | ConvertTo-Json) -Method POST
    } catch {
        Write-Host "Error: $_"
        break
    }

    if (!$results) {
        # If we didn't get a response it's probably because we're being throttled so pause for 
        # 500ms and try again.
        Write-Warning "No results returned for page $pageCounter.  Waiting 500ms and trying again."
        Start-Sleep -Milliseconds 500
    } else {
        # Since we got something back, add the payload to the aggregated results
        $allResources += $results.data
        if ($results.'$skipToken') {
            # We got a SkipToken so there are more results to retrieve.  
            # Update the skipToken option's value in the body to tell the API we want the next page
            $body.options = @{ '$skipToken' = $results.'$skipToken' }
        }
        Write-Host ("$($allResources.count) of $($results.totalRecords) retrieved.")
        $pagecounter += 1
    }
    } while ($null -ne $results.'$skipToken')
    write-verbose ("Total records retrieved: " + $allResources.count)

    return $allResources
}
    