targetScope = 'resourceGroup'

@description('Azure region for all resources. AI Gateway preview supports only these regions.')
@allowed([
  'eastus2'
  'swedencentral'
])
param location string = 'eastus2'

@description('Resource name prefix. Use lowercase letters, digits, or hyphens; start and end with a letter or digit.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'aigw-demo'

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags applied to all resources.')
param tags object = {
  project: 'ai-gateway-demo'
  environment: 'demo'
  managedBy: 'bicep'
}

var resourceName = '${namePrefix}-${uniqueString(resourceGroup().id)}'

resource gateway 'Microsoft.ApiManagement/aigateways@2026-09-01-preview' = {
  name: resourceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Consumption'
  }
  properties: {}
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${resourceName}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output gatewayResourceId string = gateway.id
output gatewayName string = gateway.name
output gatewayPrincipalId string = gateway.identity.principalId
output applicationInsightsResourceId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output logAnalyticsResourceId string = logAnalytics.id
