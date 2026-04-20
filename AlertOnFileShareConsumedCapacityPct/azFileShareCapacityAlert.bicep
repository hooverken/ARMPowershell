param storageAccountName string = 'kentosostgalerttest'
param fileShareName string = '5tb'
param capacityThresholdPercent int = 1
param alertName string = '${fileShareName}-capacity-percentage-utilization-alert'
param actionGroupName string = 'stgpctalerttest'


// Existing resources: storage account, file share, and action group

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' existing = {
  name: fileShareName
  parent: fileServices
}

resource actionGroup 'Microsoft.Insights/actionGroups@2019-06-01' existing = {
  name: actionGroupName
}

// Create a metric alert that triggers when the file share capacity percentage utilization exceeds the specified threshold

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertName
  location: 'global'
  tags: {
    _deployed_by_amba: 'true'
  }
  properties: {
    description: 'Test alert for file share capacity percentage utilization'
    scopes: array(fileServices.id)
    severity: 2 // warning
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: '1st criterion'
          metricName: 'FileCapacity'
          dimensions: []
          operator: 'GreaterThan'
          threshold: capacityThresholdPercent
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output fileShareCapacity int = fileShare.properties.shareQuota
output percentageUtilizationAlertThreshold int = capacityThresholdPercent
output alertId string = metricAlert.id
output alertName string = metricAlert.name
