function Connect-ToAzure {
    $Subscription0 = $Scopes | Select-Object -First 1 | ForEach-Object {$_.split("/")[2]}
    # Connect To Azure Tenant
    Write-Host 'Authenticating to Azure'
    if ($Script:ShellPlatform -eq 'Win32NT') {
      Clear-AzContext -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue
      if ([string]::IsNullOrEmpty($TenantID)) {
        Write-Host 'Tenant ID not specified.'
        Write-Host ''
        Connect-AzAccount -WarningAction SilentlyContinue -Environment $AzureEnvironment
        $Tenants = Get-AzTenant
        if ($Tenants.count -gt 1) {
          Write-Host 'Select the Azure Tenant to connect : '
          $Selection = 1
          foreach ($Tenant in $Tenants) {
            $TenantName = $Tenant.Name
            Write-Host "$Selection)  $TenantName"
            $Selection ++
          }
          Write-Host ''
          [int]$SelectedTenant = Read-Host 'Select Tenant'
          $defaultTenant = --$SelectedTenant
          $TenantID = $Tenants[$defaultTenant]
          Connect-AzAccount -Tenant $TenantID -Subscription $Subscription0 -WarningAction SilentlyContinue -Environment $AzureEnvironment
        }
      } else {
        if ((Get-AzContext).tenantid -ne $TenantID) {
          Clear-AzContext -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue
          Connect-AzAccount -Tenant $TenantID -Subscription $Subscription0 -WarningAction SilentlyContinue -Environment $AzureEnvironment
        }
      }
      #Set the default variable with the list of subscriptions in case no Subscription File was informed
      $Script:SubIds = Get-AzSubscription -TenantId $TenantID -WarningAction SilentlyContinue
    } else {
      if ( (Get-AzContext).tenantid -ne $TenantID) {
        Clear-AzContext -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue
        Connect-AzAccount -Identity -Environment $AzureEnvironment
      }
      $Script:SubIds = Get-AzSubscription -WarningAction SilentlyContinue
    }
  }