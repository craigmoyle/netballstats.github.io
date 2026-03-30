targetScope = 'subscription'

@description('Short name for the azd environment, for example dev or prod.')
param environmentName string = 'dev'

@description('Azure region for the deployment.')
param location string = deployment().location

@description('Base prefix used for Azure resource names.')
param namePrefix string = 'netballstats'

@description('Optional override for the resource group name.')
param resourceGroupName string = 'rg-${namePrefix}-${take(uniqueString(subscription().id, environmentName, location), 6)}'

@description('Tags applied to every provisioned resource.')
param tags object = {}

@description('Static Web Apps plan. Standard is required for linked backends.')
@allowed([
  'Standard'
])
param staticWebAppSku string = 'Standard'

@description('Region for Azure Static Web Apps. This resource type is not available in every Azure region.')
@allowed([
  'centralus'
  'eastasia'
  'eastus2'
  'westeurope'
  'westus2'
])
param staticWebAppLocation string = 'eastasia'

@description('Admin username for Azure Database for PostgreSQL Flexible Server.')
param postgresAdminUsername string = 'netballstatsadmin'

@description('Admin password for Azure Database for PostgreSQL Flexible Server.')
@secure()
param postgresAdminPassword string

@description('Read-only PostgreSQL user used by the API at runtime.')
param postgresApiUsername string = 'netballstats_api'

@description('Password for the read-only PostgreSQL API user.')
@secure()
param postgresApiPassword string

@description('Database name used by the application.')
param postgresDatabaseName string = 'netballstats'

@description('PostgreSQL version.')
@allowed([
  '16'
  '17'
])
param postgresVersion string = '16'

@description('PostgreSQL compute SKU name.')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL compute tier.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgresSkuTier string = 'Burstable'

@description('Storage size for PostgreSQL in GB.')
@minValue(32)
param postgresStorageSizeGb int = 32

// FIND-02 remediated: private networking enabled. PostgreSQL is only reachable
// from within the VNet (Container Apps environment is VNet-integrated).
// The public endpoint and "Allow Azure Services" firewall rule are both disabled.
@description('Whether PostgreSQL should expose a public endpoint. Disabled — private networking handles connectivity.')
@allowed([
  'Enabled'
  'Disabled'
])
param postgresPublicNetworkAccess string = 'Disabled'

@description('Whether to create the broad Allow Azure Services firewall rule for PostgreSQL. Disabled — private networking handles connectivity.')
param allowAzureServicesPostgresFirewallRule bool = false

@description('CPU allocation for the API container app.')
param apiCpu int = 1

@description('Memory allocation for the API container app.')
param apiMemory string = '2Gi'

@description('Container port exposed by the Plumber API.')
param apiPort int = 8000

@description('Minimum API replicas.')
@minValue(1)
param apiMinReplicas int = 1

@description('Maximum API replicas. Keep at 1 unless a distributed rate-limiter is added — the in-process limiter is per-replica.')
@minValue(1)
param apiMaxReplicas int = 1

@description('Optional additional frontend hostname to permit through CORS.')
param customFrontendHostname string = ''

@description('Optional mode for staged private PostgreSQL networking. Set to enabled to provision a VNet-integrated Container Apps environment and private PostgreSQL network.')
@allowed([
  ''
  'disabled'
  'enabled'
])
param privatePostgresNetworkingMode string = 'enabled'

@description('Optional override for the VNet CIDR used when private PostgreSQL networking is enabled.')
param virtualNetworkAddressPrefix string = ''

@description('Optional override for the Container Apps infrastructure subnet CIDR used when private PostgreSQL networking is enabled.')
param containerAppsInfrastructureSubnetPrefix string = ''

@description('Optional override for the delegated PostgreSQL subnet CIDR used when private PostgreSQL networking is enabled.')
param postgresDelegatedSubnetPrefix string = ''

@description('Optional override for the private DNS zone used when private PostgreSQL networking is enabled.')
param postgresPrivateDnsZoneName string = ''

@description('Container image for the API and DB refresh jobs. Populated by azd after first deploy via SERVICE_API_IMAGE_NAME. Empty on first provision — Bicep defaults to the placeholder image.')
param apiImageName string = ''

var resourceGroupTags = union(tags, {
  'azd-env-name': environmentName
})

resource appResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: resourceGroupTags
}

module appStack './modules/app-stack.bicep' = {
  name: 'app-stack-${environmentName}'
  scope: appResourceGroup
  params: {
    environmentName: environmentName
    location: location
    namePrefix: namePrefix
    tags: resourceGroupTags
    staticWebAppSku: staticWebAppSku
    staticWebAppLocation: staticWebAppLocation
    postgresAdminUsername: postgresAdminUsername
    postgresAdminPassword: postgresAdminPassword
    postgresApiUsername: postgresApiUsername
    postgresApiPassword: postgresApiPassword
    postgresDatabaseName: postgresDatabaseName
    postgresVersion: postgresVersion
    postgresSkuName: postgresSkuName
    postgresSkuTier: postgresSkuTier
    postgresStorageSizeGb: postgresStorageSizeGb
    postgresPublicNetworkAccess: postgresPublicNetworkAccess
    allowAzureServicesPostgresFirewallRule: allowAzureServicesPostgresFirewallRule
    apiCpu: apiCpu
    apiMemory: apiMemory
    apiPort: apiPort
    apiMinReplicas: apiMinReplicas
    apiMaxReplicas: apiMaxReplicas
    customFrontendHostname: customFrontendHostname
    privatePostgresNetworkingMode: privatePostgresNetworkingMode
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    containerAppsInfrastructureSubnetPrefix: containerAppsInfrastructureSubnetPrefix
    postgresDelegatedSubnetPrefix: postgresDelegatedSubnetPrefix
    postgresPrivateDnsZoneName: postgresPrivateDnsZoneName
    apiImageName: apiImageName
  }
}

output staticWebAppHostname string = appStack.outputs.staticWebAppHostname
output staticWebAppUrl string = appStack.outputs.staticWebAppUrl
output apiContainerAppFqdn string = appStack.outputs.apiContainerAppFqdn
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = appStack.outputs.containerRegistryLoginServer
output containerRegistryLoginServer string = appStack.outputs.containerRegistryLoginServer
output browserTelemetryInsightsName string = appStack.outputs.browserTelemetryInsightsName
output postgresServerFqdn string = appStack.outputs.postgresServerFqdn
output postgresDatabase string = appStack.outputs.postgresDatabase
output postgresAdminSecretUri string = appStack.outputs.postgresAdminSecretUri
output postgresApiUser string = appStack.outputs.postgresApiUser
output dbRefreshJobSatName string = appStack.outputs.dbRefreshJobSatName
output dbRefreshJobSunName string = appStack.outputs.dbRefreshJobSunName
