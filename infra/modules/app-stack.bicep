targetScope = 'resourceGroup'

@description('Short name for the azd environment, for example dev or prod.')
param environmentName string

@description('Azure region for the deployment.')
param location string = resourceGroup().location

@description('Base prefix used for Azure resource names.')
param namePrefix string

@description('Tags applied to every provisioned resource.')
param tags object = {}

@description('Static Web Apps plan. Standard is required for linked backends.')
@allowed([
  'Standard'
])
param staticWebAppSku string = 'Standard'

@description('Region for Azure Static Web Apps. This can differ from the rest of the stack.')
@allowed([
  'centralus'
  'eastasia'
  'eastus2'
  'westeurope'
  'westus2'
])
param staticWebAppLocation string = 'eastasia'

@description('Admin username for Azure Database for PostgreSQL Flexible Server.')
param postgresAdminUsername string

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

@description('Whether PostgreSQL should expose a public endpoint. For production deployments, set privatePostgresNetworkingMode to enabled instead of enabling the public endpoint. See AGENTS.md for the private networking migration guide.')
@allowed([
  'Enabled'
  'Disabled'
])
param postgresPublicNetworkAccess string = 'Enabled'

@description('Whether to create the broad Allow Azure Services firewall rule for PostgreSQL. This rule permits any Azure-hosted resource (in any subscription) to connect. Disabled by default; enable only as a temporary stopgap when private networking is not yet configured.')
param allowAzureServicesPostgresFirewallRule bool = false

@description('Optional mode for staged private PostgreSQL networking. Set to enabled to provision a VNet-integrated Container Apps environment and private PostgreSQL network.')
@allowed([
  ''
  'disabled'
  'enabled'
])
param privatePostgresNetworkingMode string = 'disabled'

@description('Optional override for the VNet CIDR used when private PostgreSQL networking is enabled.')
param virtualNetworkAddressPrefix string = ''

@description('Optional override for the Container Apps infrastructure subnet CIDR used when private PostgreSQL networking is enabled.')
param containerAppsInfrastructureSubnetPrefix string = ''

@description('Optional override for the delegated PostgreSQL subnet CIDR used when private PostgreSQL networking is enabled.')
param postgresDelegatedSubnetPrefix string = ''

@description('Optional override for the private DNS zone used when private PostgreSQL networking is enabled.')
param postgresPrivateDnsZoneName string = ''

@description('CPU allocation for the API container app.')
param apiCpu int = 1

@description('Memory allocation for the API container app.')
param apiMemory string = '2Gi'

@description('Container port exposed by the Plumber API.')
param apiPort int = 8000

@description('Minimum API replicas.')
@minValue(1)
param apiMinReplicas int = 1

@description('Maximum API replicas. Single replica is recommended for this read-only stats site: the in-process rate limiter is not shared across replicas, so a higher count allows bypass. Increase only after adding a distributed rate store (e.g. Redis).')
@minValue(1)
param apiMaxReplicas int = 1

@description('Optional additional frontend hostname to permit through CORS.')
param customFrontendHostname string = ''

var resourceToken = toLower(take(uniqueString(subscription().id, resourceGroup().name, environmentName, namePrefix), 6))
var normalizedPrefix = toLower(replace(namePrefix, '-', ''))
var containerRegistryName = take('${normalizedPrefix}${resourceToken}acr', 50)
var postgresServerName = take('${normalizedPrefix}-${resourceToken}-pg', 63)
var enablePrivatePostgresNetworking = toLower(privatePostgresNetworkingMode) == 'enabled'
var defaultVirtualNetworkAddressPrefix = '10.30.0.0/16'
var defaultContainerAppsInfrastructureSubnetPrefix = '10.30.0.0/21'
var defaultPostgresDelegatedSubnetPrefix = '10.30.8.0/28'
var effectiveVirtualNetworkAddressPrefix = empty(virtualNetworkAddressPrefix) ? defaultVirtualNetworkAddressPrefix : virtualNetworkAddressPrefix
var effectiveContainerAppsInfrastructureSubnetPrefix = empty(containerAppsInfrastructureSubnetPrefix) ? defaultContainerAppsInfrastructureSubnetPrefix : containerAppsInfrastructureSubnetPrefix
var effectivePostgresDelegatedSubnetPrefix = empty(postgresDelegatedSubnetPrefix) ? defaultPostgresDelegatedSubnetPrefix : postgresDelegatedSubnetPrefix
var effectivePostgresPrivateDnsZoneName = empty(postgresPrivateDnsZoneName) ? '${normalizedPrefix}-${resourceToken}.postgres.database.azure.com' : postgresPrivateDnsZoneName
var staticWebAppName = take('${namePrefix}-web-${resourceToken}', 40)
var containerEnvironmentName = take('${namePrefix}-aca-env-${resourceToken}', 32)
var containerAppName = take('${namePrefix}-api-${resourceToken}', 32)
var dbRefreshJobSatName = take('${namePrefix}-db-sat-${resourceToken}', 32)
var dbRefreshJobSunName = take('${namePrefix}-db-sun-${resourceToken}', 32)
var keyVaultName = take('${normalizedPrefix}-${resourceToken}-kv', 24)
var workspaceName = take('${namePrefix}-logs-${resourceToken}', 63)
var browserTelemetryInsightsName = take('${namePrefix}-browser-ai-${resourceToken}', 64)
var userAssignedIdentityName = take('${namePrefix}-api-mi-${resourceToken}', 64)
var virtualNetworkName = take('${namePrefix}-vnet-${resourceToken}', 64)
var containerAppsInfrastructureSubnetName = 'aca-infrastructure'
var postgresDelegatedSubnetName = 'postgres-flex'
var postgresPrivateDnsZoneLinkName = take('${namePrefix}-postgres-dns-${resourceToken}', 80)
var allowAllAzureIpsRuleName = 'allow-azure-services'
var staticWebAppHostName = 'https://${staticWebApp.properties.defaultHostname}'
var allowedCorsOrigins = empty(customFrontendHostname)
  ? [
      staticWebAppHostName
    ]
  : [
      staticWebAppHostName
      customFrontendHostname
    ]
var allowedCorsOriginsCsv = join(allowedCorsOrigins, ',')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
    // Daily ingestion cap: limits cost from connection-string abuse.
    // The browser telemetry connection string is intentionally semi-public
    // (required by the App Insights browser SDK design) so a cap is the
    // practical blast-radius control.
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

resource browserTelemetryInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: browserTelemetryInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: false
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: userAssignedIdentityName
  location: location
  tags: tags
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, userAssignedIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    enableRbacAuthorization: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 90
    tenantId: tenant().tenantId
  }
}

resource postgresAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'postgres-admin-password'
  properties: {
    value: postgresAdminPassword
  }
}

resource postgresApiPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'postgres-api-password'
  properties: {
    value: postgresApiPassword
  }
}

resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, userAssignedIdentity.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource privateNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = if (enablePrivatePostgresNetworking) {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        effectiveVirtualNetworkAddressPrefix
      ]
    }
  }
}

resource containerAppsInfrastructureSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = if (enablePrivatePostgresNetworking) {
  parent: privateNetwork
  name: containerAppsInfrastructureSubnetName
  properties: {
    addressPrefix: effectiveContainerAppsInfrastructureSubnetPrefix
    delegations: [
      {
        name: 'container-apps'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource postgresDelegatedSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = if (enablePrivatePostgresNetworking) {
  parent: privateNetwork
  name: postgresDelegatedSubnetName
  properties: {
    addressPrefix: effectivePostgresDelegatedSubnetPrefix
    delegations: [
      {
        name: 'postgres-flex'
        properties: {
          serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
        }
      }
    ]
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enablePrivatePostgresNetworking) {
  name: effectivePostgresPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource postgresPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enablePrivatePostgresNetworking) {
  parent: postgresPrivateDnsZone
  name: postgresPrivateDnsZoneLinkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: privateNetwork.id
    }
  }
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: postgresSkuName
    tier: postgresSkuTier
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    createMode: 'Create'
    highAvailability: {
      mode: 'Disabled'
    }
    network: enablePrivatePostgresNetworking
      ? {
          delegatedSubnetResourceId: postgresDelegatedSubnet.id
          privateDnsZoneArmResourceId: postgresPrivateDnsZone.id
        }
      : {
          publicNetworkAccess: postgresPublicNetworkAccess
        }
    storage: {
      autoGrow: 'Enabled'
      storageSizeGB: postgresStorageSizeGb
    }
    version: postgresVersion
  }
  dependsOn: [
    postgresPrivateDnsZoneLink
  ]
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-08-01' = {
  parent: postgresServer
  name: postgresDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource postgresFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2025-08-01' = if (!enablePrivatePostgresNetworking && allowAzureServicesPostgresFirewallRule) {
  parent: postgresServer
  name: allowAllAzureIpsRuleName
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

var containerEnvironmentProperties = union({
  appLogsConfiguration: {
    destination: 'log-analytics'
    logAnalyticsConfiguration: {
      customerId: logAnalyticsWorkspace.properties.customerId
      sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    }
  }
}, enablePrivatePostgresNetworking ? {
  vnetConfiguration: {
    infrastructureSubnetId: containerAppsInfrastructureSubnet.id
    internal: false
  }
  workloadProfiles: [
    {
      name: 'Consumption'
      workloadProfileType: 'Consumption'
    }
  ]
} : {})

resource containerEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: containerEnvironmentName
  location: location
  tags: tags
  properties: containerEnvironmentProperties
}

resource apiContainerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  tags: union(tags, {
    'azd-service-name': 'api'
  })
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: false
        corsPolicy: {
          allowCredentials: false
          allowedHeaders: [
            'Content-Type'
          ]
          allowedMethods: [
            'GET'
            'OPTIONS'
          ]
          allowedOrigins: allowedCorsOrigins
        }
        external: true
        targetPort: apiPort
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        transport: 'Auto'
      }
      registries: [
        {
          identity: userAssignedIdentity.id
          server: containerRegistry.properties.loginServer
        }
      ]
      secrets: [
        {
          name: 'postgres-api-password'
          identity: userAssignedIdentity.id
          keyVaultUrl: postgresApiPasswordSecret.properties.secretUriWithVersion
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'NETBALL_STATS_REPO_ROOT'
              value: '/app'
            }
            {
              name: 'NETBALL_STATS_HOST'
              value: '0.0.0.0'
            }
            {
              name: 'NETBALL_STATS_PORT'
              value: string(apiPort)
            }
            {
              name: 'NETBALL_STATS_ALLOWED_ORIGINS'
              value: allowedCorsOriginsCsv
            }
            {
              name: 'NETBALL_STATS_DB_BACKEND'
              value: 'postgres'
            }
            {
              name: 'NETBALL_STATS_DB_HOST'
              value: postgresServer.properties.fullyQualifiedDomainName
            }
            {
              name: 'NETBALL_STATS_DB_PORT'
              value: '5432'
            }
            {
              name: 'NETBALL_STATS_DB_NAME'
              value: postgresDatabaseName
            }
            {
              name: 'NETBALL_STATS_DB_USER'
              value: postgresApiUsername
            }
            {
              name: 'NETBALL_STATS_DB_PASSWORD'
              secretRef: 'postgres-api-password'
            }
            {
              name: 'NETBALL_STATS_DB_SSLMODE'
              value: 'require'
            }
            {
              name: 'NETBALL_STATS_DB_CONNECT_TIMEOUT_SECONDS'
              value: '5'
            }
            {
              name: 'NETBALL_STATS_DB_STATEMENT_TIMEOUT_MS'
              value: '15000'
            }
            {
              name: 'NETBALL_STATS_REQUEST_TELEMETRY'
              value: 'true'
            }
            {
              name: 'NETBALL_STATS_BROWSER_APPINSIGHTS_CONNECTION_STRING'
              value: browserTelemetryInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: apiPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 18
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: apiPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 15
              timeoutSeconds: 5
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/live'
                port: apiPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 5
            }
          ]
          resources: {
            cpu: apiCpu
            memory: apiMemory
          }
        }
      ]
      scale: {
        minReplicas: apiMinReplicas
        maxReplicas: apiMaxReplicas
      }
    }
  }
  dependsOn: [
    acrPullAssignment
    keyVaultSecretsUserAssignment
    postgresDatabase
    postgresFirewallRule
  ]
}

// Shared environment variable list for both database refresh jobs.
// Jobs connect as the admin user (write access required for full rebuild).
var dbRefreshEnv = [
  {
    name: 'NETBALL_STATS_REPO_ROOT'
    value: '/app'
  }
  {
    name: 'NETBALL_STATS_DB_BACKEND'
    value: 'postgres'
  }
  {
    name: 'NETBALL_STATS_DB_HOST'
    value: postgresServer.properties.fullyQualifiedDomainName
  }
  {
    name: 'NETBALL_STATS_DB_PORT'
    value: '5432'
  }
  {
    name: 'NETBALL_STATS_DB_NAME'
    value: postgresDatabaseName
  }
  {
    name: 'NETBALL_STATS_DB_USER'
    value: postgresAdminUsername
  }
  {
    name: 'NETBALL_STATS_DB_PASSWORD'
    secretRef: 'postgres-admin-password'
  }
  {
    name: 'NETBALL_STATS_DB_SSLMODE'
    value: 'require'
  }
  {
    name: 'NETBALL_STATS_DB_STATEMENT_TIMEOUT_MS'
    value: '0'
  }
]

// Saturday 21:00 AEST (UTC+10) = 11:00 UTC
resource dbRefreshJobSat 'Microsoft.App/jobs@2025-02-02-preview' = {
  name: dbRefreshJobSatName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnvironment.id
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: '0 11 * * 6'
        replicaCompletionCount: 1
        parallelism: 1
      }
      replicaTimeout: 3600
      replicaRetryLimit: 1
      registries: [
        {
          identity: userAssignedIdentity.id
          server: containerRegistry.properties.loginServer
        }
      ]
      secrets: [
        {
          name: 'postgres-admin-password'
          identity: userAssignedIdentity.id
          keyVaultUrl: postgresAdminPasswordSecret.properties.secretUriWithVersion
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'db-refresh'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          command: [
            'Rscript'
            'scripts/build_database.R'
          ]
          env: dbRefreshEnv
          resources: {
            cpu: json('2')
            memory: '4Gi'
          }
        }
      ]
    }
  }
  dependsOn: [
    acrPullAssignment
    keyVaultSecretsUserAssignment
    postgresDatabase
    postgresFirewallRule
  ]
}

// Sunday 18:00 AEST (UTC+10) = 08:00 UTC
resource dbRefreshJobSun 'Microsoft.App/jobs@2025-02-02-preview' = {
  name: dbRefreshJobSunName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnvironment.id
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: '0 8 * * 0'
        replicaCompletionCount: 1
        parallelism: 1
      }
      replicaTimeout: 3600
      replicaRetryLimit: 1
      registries: [
        {
          identity: userAssignedIdentity.id
          server: containerRegistry.properties.loginServer
        }
      ]
      secrets: [
        {
          name: 'postgres-admin-password'
          identity: userAssignedIdentity.id
          keyVaultUrl: postgresAdminPasswordSecret.properties.secretUriWithVersion
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'db-refresh'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          command: [
            'Rscript'
            'scripts/build_database.R'
          ]
          env: dbRefreshEnv
          resources: {
            cpu: json('2')
            memory: '4Gi'
          }
        }
      ]
    }
  }
  dependsOn: [
    acrPullAssignment
    keyVaultSecretsUserAssignment
    postgresDatabase
    postgresFirewallRule
  ]
}

resource staticWebApp 'Microsoft.Web/staticSites@2025-03-01' = {
  name: staticWebAppName
  location: staticWebAppLocation
  identity: {
    type: 'SystemAssigned'
  }
  tags: union(tags, {
    'azd-service-name': 'web'
  })
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
  }
}

resource staticWebAppLinkedBackend 'Microsoft.Web/staticSites/linkedBackends@2025-03-01' = {
  parent: staticWebApp
  name: 'api'
  kind: 'ContainerApp'
  properties: {
    backendResourceId: apiContainerApp.id
    region: location
  }
}

output staticWebAppHostname string = staticWebApp.properties.defaultHostname
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output apiContainerAppFqdn string = apiContainerApp.properties.configuration.ingress.fqdn
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output browserTelemetryInsightsName string = browserTelemetryInsights.name
output postgresServerFqdn string = postgresServer.properties.fullyQualifiedDomainName
output postgresDatabase string = postgresDatabaseName
output postgresAdminSecretUri string = postgresAdminPasswordSecret.properties.secretUriWithVersion
output postgresApiUser string = postgresApiUsername
output dbRefreshJobSatName string = dbRefreshJobSat.name
output dbRefreshJobSunName string = dbRefreshJobSun.name
