module acmebot 'br:cracmebotprod.azurecr.io/bicep/modules/keyvault-acmebot:v3' = {
  name: 'acmebot'
  params: {
    appNamePrefix: 'ACMEbot'
    mailAddress: 'ken.hoover@microsoft.com'
    acmeEndpoint: 'https://acme-v02.api.letsencrypt.org/'
    createWithKeyVault: false
    keyVaultSkuName: 'standard'
    
  }
}

output function string = acmebot.outputs.functionAppName
