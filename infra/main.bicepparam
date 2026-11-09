using 'main.bicep'

param workload    = 'gwlab'
param environment = 'dev'
param location    = 'swedencentral'

// IMPORTANTE: estos valores NO son universales.
// Ejecuta scripts/00-check-models.sh y sustituyelos por lo que exista
// en TU region, TU suscripcion y TU cuota. Si los copias a ciegas,
// la plantilla compila y el despliegue falla.
param models = [
  {
    deploymentName: 'chat-principal'
    modelName:      'REEMPLAZAR'
    modelVersion:   'REEMPLAZAR'
    modelFormat:    'OpenAI'
    skuName:        'GlobalStandard'
    capacity:       50
  }
  {
    deploymentName: 'chat-fallback'
    modelName:      'REEMPLAZAR'
    modelVersion:   'REEMPLAZAR'
    modelFormat:    'OpenAI'
    skuName:        'GlobalStandard'
    capacity:       20
  }
]

// Vacios = sin asignacion de rol. Resuelve el GUID con scripts/00-check-models.sh.
param granteePrincipalId = ''
param roleDefinitionId   = ''

// true = el gateway tendra que importar con identidad administrada.
param disableLocalAuth = true
