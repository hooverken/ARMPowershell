targetScope = 'subscription'

resource securityContacts 'Microsoft.Security/securityContacts@2020-01-01-preview' = {
    name: 'default'
    properties: {
      alertNotifications: {
        minimalSeverity: 'low'
        state: 'On'
      }
      emails: 'email.address@contoso.com'
      notificationsByRole: {
        roles: [
          'Owner'
          'ServiceAdmin'
        ]
        state: 'On'
      }
      phone: '+12345678901'
    }
  }
