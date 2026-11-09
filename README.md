# AI Gateway en Azure: ejemplo reproducible con observabilidad

Ejemplo de [jmfloreszazo](https://github.com/jmfloreszazo), con licencia MIT, para desplegar
y verificar un AI Gateway en tu propia suscripción. Incluye plantillas de Application Insights,
Log Analytics y un dashboard de Azure Portal. No necesitas acceso al entorno ni a las credenciales del autor.

La publicación es directamente en GitHub. El control de publicación es de solo lectura:
no crea ZIP, manifiestos ni copias de evidencias, y no hace commits ni subidas.

El laboratorio verifica acceso, enrutado y contabilidad de tokens contra AI Gateway.
El recurso actual es `Microsoft.ApiManagement/aigateways` y autentica las claves de runtime
con `Authorization: Bearer`. El modo `api-key` queda disponible solo para el tier anterior.

Hay dos rutas con alcances distintos: `infra/main.bicep` crea Foundry y modelos nuevos;
`infra/gateway-existing.bicep` crea un gateway y referencia un Foundry y un despliegue existentes.
No ejecutes la primera contra un entorno que solo quieres reutilizar. La conexión de telemetría
se completa después con [la plantilla del exportador](infra/gateway-telemetry.bicep).

## Qué hay y qué no

| Pieza | Cómo se despliega aquí | Por qué |
|---|---|---|
| Cuenta Foundry, proyecto y despliegues de modelo | Bicep declarativo | Es el plano de datos. Tiene que ser revisable y repetible. |
| Identidad administrada y asignación de rol | Bicep, con el GUID del rol como parámetro | El id y los permisos del rol se revisan en la suscripción destino. |
| Gateway y conexión a Foundry existente | `infra/gateway-existing.bicep` | Raíz `2026-11-01`, configuración hija `2025-09-01-preview`. Sin cuentas ni modelos nuevos. |
| Application Insights y Log Analytics | [Módulo de observabilidad](infra/modules/observability.bicep), incluido por defecto en la plantilla del gateway | OTLP habilitado y logs con 30 días de retención y límite diario de 1 GB configurables. |
| Exportador OpenTelemetry | [Segunda plantilla](infra/gateway-telemetry.bicep) | Métricas, logs y trazas con identidad administrada, sin captura de payloads. |
| Dashboard compartido de Azure Portal | Módulo de observabilidad | Cuatro paneles KQL: peticiones, códigos HTTP, latencia y tokens reportados en logs. |
| Configuración interactiva | Portal del gateway o extensión `az aigateway` | No confundir las herramientas del recurso nuevo con `az apim` del servicio clásico. |
| Clientes de verificación | C# sobre .NET 10 y Python | Comprueban enrutado y contabilidad de tokens, no solo que el modelo contesta. |
| Pruebas | xUnit y scripts de contrato | Cubren la frontera, no el camino feliz. |

## Estructura

```
AiGateway.sln
Directory.Build.props
infra/
  main.bicep                       Foundry, proyecto, modelos, asignación de rol
  main.bicepparam                  parámetros (con REEMPLAZAR a propósito)
  gateway-existing.bicep           gateway aditivo sobre un backend existente
  gateway-existing.bicepparam      ejemplos sin datos de infraestructura reales
  gateway-telemetry.bicep          exportador OTLP, en un segundo despliegue
  modules/model.bicep              un despliegue de modelo, todo parametrizado
  modules/observability.bicep      Log Analytics, Application Insights y dashboard
scripts/
  00-check-models.sh               qué existe de verdad en tu región
  01-deploy.sh / 01-deploy.ps1     despliegue con what-if previo
  02-smoke-test.sh                 una llamada, tres verificaciones
  02-smoke-test.ps1                verificación y contrato nativos de PowerShell 7
  03-create-lab-user.ps1            alta opcional de una cuenta nativa de Entra
  04-prepare-publication.ps1        revisión de solo lectura, sin ZIP ni otros artefactos
  publication-redact.js            máscaras opacas para capturas de navegador
src/
  AiGateway.Core/                  GatewayClient, contratos y traducción de errores
  AiGateway.Client/                consola de verificación manual
  python/call_gateway.py           equivalente con el SDK de OpenAI
tests/
  AiGateway.Tests/                 xUnit sobre el cliente
  01-bicep-lint.sh                 build y lint de las plantillas
  02-gateway-contract.sh           contrato del gateway contra un entorno real
  03-powershell-contract.ps1       pruebas simuladas del script de Windows
  04-observability-contract.ps1    contrato ARM de observabilidad, sin desplegar
  test_python_gateway.py          SDK real sobre transporte simulado
docs/
  articulo.md                     artículo con resultados y capturas reales
  capturas/                       PNG con identificadores cubiertos
  evidencia/                      copia pública de las pruebas ejecutadas
.github/workflows/ci.yml           bicep + dotnet + python en cada push
```

## Requisitos y primer uso

- Una suscripción Azure propia, acceso a AI Gateway en vista previa y cuota para el modelo elegido.
- Git, Azure CLI con Bicep, PowerShell 7, .NET SDK 10 y Python 3.12, la versión usada en CI.
- Bash y `jq` si utilizas los scripts `.sh`; Windows también tiene una ruta PowerShell.
- Permisos para crear recursos y asignar roles sobre Foundry y la regla de recogida de datos (DCR).
  Contributor por sí solo no permite asignar roles.
- Proveedores registrados: `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`,
  `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.Portal` y `Microsoft.Monitor`.
  Este último es necesario para los recursos administrados de OTLP.

```powershell
git clone https://github.com/jmfloreszazo/ai-gateway-preview-lab.git
Set-Location ai-gateway-preview-lab
az login
az bicep install
dotnet restore AiGateway.sln
python -m pip install -r src/python/requirements.txt
```

También puedes hacer fork. Cambia el nombre del gateway por uno globalmente único y utiliza tus
propios parámetros. Los modelos y versiones de ejemplo no garantizan disponibilidad en tu región:
consulta tu catálogo y cuota antes de desplegar. Los módulos verificados necesitan acceso a `mcr.microsoft.com`.

## Usar infraestructura existente

Los parámetros de `infra/gateway-existing.bicepparam` son ejemplos, no identifican un entorno real.
Cópialos a un archivo local ignorado y ajusta suscripción, grupo, nombre, región, cuenta y despliegue.
En el primer despliegue, el `what-if` debe mostrar solo creaciones; no debe modificar ni borrar
Foundry ni sus modelos. La plantilla actual también incluye los destinos de telemetría y el dashboard.
Usa siempre modo incremental. No elimines el grupo de recursos al limpiar este laboratorio.

```powershell
$Subscription = '<suscripcion confirmada>'
$ResourceGroup = '<grupo que contiene Foundry>'
$ParametersFile = 'infra/gateway-existing.local.bicepparam'

if (-not (Test-Path $ParametersFile)) {
  Copy-Item infra/gateway-existing.bicepparam $ParametersFile
}
# Ajusta el archivo local antes de continuar.

az deployment group what-if --subscription $Subscription --resource-group $ResourceGroup `
  --template-file infra/gateway-existing.bicep --parameters $ParametersFile

# Solo despues de aprobar cambios, acceso publico y coste:
az deployment group create --name gateway-lab --mode Incremental `
  --subscription $Subscription --resource-group $ResourceGroup `
  --template-file infra/gateway-existing.bicep --parameters $ParametersFile
```

La plantilla no entrega ninguna clave como salida. Publica `gatewayBaseUrl`, `model`, los
metadatos del backend, `runtimeKeyId`, `foundryRoleAssignmentId` y las referencias de observabilidad,
incluida `dashboardUrl`. Son salidas para tu entorno, no datos que debas subir a GitHub.
La clave caduca en la siguiente
medianoche UTC: la API probada conserva el día de caducidad y descarta la hora. Verifica siempre la fecha devuelta.
El rol se limita a la cuenta Foundry y autentica el backend con identidad administrada;
no se cambian las opciones de autenticación ni la red de la cuenta existente.

## Application Insights, Log Analytics y dashboard

La plantilla del gateway crea `log-<gateway>`, `appi-<gateway>` y `dash-<gateway>`.
Puedes ajustar `logRetentionInDays` y `logDailyQuotaGb`, o usar `enableObservability = false`
para no crear observabilidad nueva. Desactivarla no elimina recursos ya desplegados en modo incremental.

Si el gateway ya existe, despliega solo [el módulo de observabilidad](infra/modules/observability.bicep)
en su grupo, con `namePrefix=<nombre del gateway>` y `location=<región del gateway>`.
Revisa primero el `what-if`. Ese módulo no crea ni modifica Foundry, sus modelos o el gateway.

### Conectar la telemetría

Crear los destinos no inicia la recogida de datos. `AzureMonitorWorkspaceIngestionMode` activa
la creación de un Azure Monitor workspace administrado para métricas y una DCR. Azure puede
tardar varios minutos en publicar los endpoints OTLP. El exportador necesita esos endpoints y
el rol `Monitoring Metrics Publisher` para la identidad del gateway sobre la DCR.

Puedes conectarlo desde [AI Gateway](https://ai.gateway.azure.com), en **Monitoring > Configure
telemetry > Existing Azure Application Insights resource**, seleccionando `appi-<gateway>`.
Mantén la captura de payloads desactivada y no añadas claims de identidad si no los necesitas.

Como alternativa, estos pasos PowerShell completan la configuración con Bicep. Reutilizan
`$Subscription` y `$ResourceGroup` de la sección anterior. El rol se asigna por CLI porque
el grupo administrado de la DCR bloquea los despliegues ARM en ese ámbito.

```powershell
$GatewayName = '<gatewayName de tu archivo local>'
$AppInsightsName = "appi-$GatewayName"

$component = az resource show --subscription $Subscription --resource-group $ResourceGroup `
  --resource-type Microsoft.Insights/components --name $AppInsightsName `
  --api-version 2020-02-02 --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer Application Insights.' }
$otlp = $component.properties
$required = @($otlp.OTLPMetricsEndpoint, $otlp.OTLPLogsEndpoint,
  $otlp.OTLPTracesEndpoint, $otlp.DataCollectionRuleResourceId)
if (@($required | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
  throw 'Azure aun prepara los endpoints OTLP. Repite este paso dentro de unos minutos.'
}

$principalId = az resource show --subscription $Subscription --resource-group $ResourceGroup `
  --resource-type Microsoft.ApiManagement/aigateways --name $GatewayName `
  --api-version 2026-11-01 --query identity.principalId --output tsv
if ($LASTEXITCODE -ne 0 -or -not $principalId) { throw 'Falta la identidad del gateway.' }

az role assignment create --subscription $Subscription --assignee-object-id $principalId `
  --assignee-principal-type ServicePrincipal --role 'Monitoring Metrics Publisher' `
  --scope $otlp.DataCollectionRuleResourceId --output none
if ($LASTEXITCODE -ne 0) { throw 'No se pudo asignar el permiso de publicacion OTLP.' }

az deployment group what-if --subscription $Subscription --resource-group $ResourceGroup `
  --template-file infra/gateway-telemetry.bicep `
  --parameters gatewayName=$GatewayName applicationInsightsName=$AppInsightsName

# Solo despues de revisar el what-if y aprobar el cambio:
az deployment group create --subscription $Subscription --resource-group $ResourceGroup `
  --name gateway-telemetry --mode Incremental --template-file infra/gateway-telemetry.bicep `
  --parameters gatewayName=$GatewayName applicationInsightsName=$AppInsightsName
```

Si falla justo después de asignar el rol, comprueba los permisos y repite el último despliegue
cuando termine la propagación de RBAC. No añadas claves de instrumentación ni connection strings
para sortear un problema de identidad administrada.

### Consultar el dashboard

Abre la salida `dashboardUrl` del despliegue, o busca `dash-<gateway>` en **Azure Portal > Dashboards**.
Necesitas acceso al dashboard y permisos de consulta sobre el workspace; compartir su URL no concede
acceso a los datos. El portal de AI Gateway también tiene vistas integradas para las tres señales.

| Panel | Origen | Contenido |
|---|---|---|
| Peticiones de modelos | `OTelSpans`, spans `Server` de `/models/` | Volumen por intervalos de cinco minutos. |
| Códigos HTTP | `OTelSpans` | Distribución de los códigos de respuesta observados. |
| Latencia | `OTelSpans` | Media y percentil 95 en milisegundos. |
| Tokens por modelo | `OTelLogs` | Entrada y salida reportadas por el backend. |

Envía tráfico con los clientes después de conectar la telemetría. Espera la ingesta y comprueba
`OTelSpans | take 10` y `OTelLogs | take 10` en **Log Analytics > Logs**. Las tablas pueden no existir
antes de la primera ingesta. El panel de tokens admite uso de Chat Completions y Responses y excluye
registros sin uso completo: desconocido no significa cero. Verifica los atributos recibidos antes
de usar las consultas para alertas o informes.

Las métricas OTLP de tokens y coste estimado van al Azure Monitor workspace administrado, no a
`AppMetrics` ni a las tablas KQL del dashboard. El panel de tokens usa logs y no es una factura.
Los 30 días y 1 GB/día corresponden al workspace de logs, no a métricas ni a inferencia. El límite
diario puede excederse y detener la recogida; no es un presupuesto total garantizado.

La configuración deshabilita la autenticación local de Application Insights, usa identidad administrada
y deja `payloadCapture: false`, sin claims adicionales. Los metadatos técnicos aún pueden identificar
recursos o consumidores: limita el acceso a los logs.

**Estado de la evidencia:** la ampliación se desplegó y verificó el 9 de noviembre de 2026.
Una inferencia nueva consumió 18 tokens; Log Analytics recibió un log y siete spans, con una única
petición de servidor. Las tres capturas reales están en [el artículo](docs/articulo.md) y los datos
anonimizados en [el resumen de observabilidad](docs/evidencia/observability-summary.json).
Las capturas verifican logs, trazas y paneles; no acreditan una consulta PromQL ni facturación.
Referencias: [observabilidad](https://ai.gateway.azure.com/docs/observability)
y [laboratorio oficial](https://github.com/Azure/aigateway/tree/main/labs/13-monitoring).

## Crear Foundry nuevo

Este es un flujo distinto y no es necesario si ya tienes un backend utilizable.
Los scripts `01-deploy` registran proveedores y pueden crear un grupo antes de la confirmación
final. Además, `Workload`, `Environment` y `Location` calculan el grupo, pero los valores de la
plantilla proceden de `main.bicepparam`: no presupongas que los sobrescriben. Revisa ese archivo.

```bash
# 0. Qué existe de verdad en tu región y tu suscripción
export RG=rg-gwlab-dev
bash scripts/00-check-models.sh

# 1. Rellenar infra/main.bicepparam con lo que ha devuelto el paso 0.
#    Los valores REEMPLAZAR están ahí a propósito: la plantilla no debe
#    desplegarse con un catálogo de modelos que no es el tuyo.

# 2. Desplegar el plano de datos (hace what-if y pide confirmación)
bash scripts/01-deploy.sh          # o: pwsh scripts/01-deploy.ps1

# 3. Con los nombres del Foundry y del despliegue recien creados, configurar
#    gateway-existing.local.bicepparam y seguir la ruta anterior para crear
#    el gateway y conectar su observabilidad en dos pasos.

# 4. Verificar
export AI_GATEWAY_BASE_URL="https://<hostname-asignado>.ai.gateway.azure.com/default/models/openai/v1"
export AI_GATEWAY_API_KEY="<runtime-access-key>"
export AI_GATEWAY_MODEL="<nombre exacto publicado>"
export AI_GATEWAY_EXPECTED_MODEL="<identificador canonico esperado en la respuesta>"
export AI_GATEWAY_AUTH_MODE="bearer"
export AI_GATEWAY_MAX_TOKENS="1024"

bash scripts/02-smoke-test.sh                       # curl
dotnet run --project src/AiGateway.Client           # C#
python src/python/call_gateway.py                   # Python
```

Los scripts `.sh` pueden llegar sin bit de ejecución: usa `bash scripts/...` o `chmod +x scripts/*.sh tests/*.sh`.

## Ejecutar en Windows

Requiere PowerShell 7. El script no necesita `jq` ni WSL. Usa la URL de salida de la plantilla,
sin añadir `/chat/completions`, y el alias exacto del portal. El modelo esperado no es necesariamente
el alias: contrástalo con el backend y su versión, nunca con el nombre que el modelo genere en el texto.

```powershell
$env:AI_GATEWAY_BASE_URL = '<gatewayBaseUrl>'
$env:AI_GATEWAY_MODEL = 'chat-principal'
$env:AI_GATEWAY_EXPECTED_MODEL = '<modelo canonico verificado>'
$env:AI_GATEWAY_AUTH_MODE = 'bearer'
$env:AI_GATEWAY_MAX_TOKENS = '1024'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$secureKey = Read-Host 'Runtime access key del gateway' -AsSecureString
$env:AI_GATEWAY_API_KEY = [Net.NetworkCredential]::new('', $secureKey).Password

./scripts/02-smoke-test.ps1 -Contract -OutputPath evidence/gateway-contract.json
dotnet run --project src/AiGateway.Client -- 'Responde solo: gateway-ok.'
python src/python/call_gateway.py

Remove-Item Env:AI_GATEWAY_API_KEY
```

En un recurso antiguo `Microsoft.ApiManagement/service` con SKU `AIGateway`, configura
`AI_GATEWAY_AUTH_MODE=api-key`. No envíes ambos headers ni confundas una clave de runtime
del gateway con una clave del proveedor. La [guía de migración](https://learn.microsoft.com/azure/ai-gateway/ai-gateway-resource)
documenta el cambio de recurso, hostname y header, y la retirada del tier anterior el 15 de enero de 2027.

Los clientes usan `max_completion_tokens`, compatible con los modelos de razonamiento.
Un presupuesto demasiado pequeño puede consumir tokens sin devolver contenido; en ese caso la prueba falla.

## Pruebas

```bash
# Plantillas: compilan y pasan el linter
bash tests/01-bicep-lint.sh

# Cliente: autenticacion actual y legacy, enrutado, tokens y errores
dotnet test AiGateway.sln

# PowerShell: dobles de HTTP, sin llamadas a Azure ni inferencias
pwsh -File tests/03-powershell-contract.ps1

# Observabilidad: diez comprobaciones del ARM generado, sin despliegues
pwsh -File tests/04-observability-contract.ps1

# Python: SDK real con transporte simulado, sin conexiones externas
python -m pip install -r src/python/requirements.txt
python -m unittest discover -s tests -p test_python_gateway.py -v

# Contrato contra un gateway real: 401 sin clave, 401 clave mala,
# 404 modelo inexistente, 200 con el modelo servido y los tokens
bash tests/02-gateway-contract.sh
```

Las pruebas verifican que el modo actual envía solo `Authorization: Bearer` y que el modo legacy
envía solo `api-key`. La aplicación solo posee una credencial del gateway, nunca una de Foundry.
Las pruebas locales no demuestran conectividad real ni deben presentarse como una ejecución contra Azure.
El contrato de observabilidad no verifica disponibilidad regional, RBAC real, ingesta ni representación
de los paneles en el portal.

Otro riesgo es el desvío silencioso: si el gateway tiene un alias o una política de fallback, puedes
pedir un alias y que te atienda otro backend. La respuesta llega, el contenido es razonable y la prueba
parece correcta. `AI_GATEWAY_EXPECTED_MODEL` permite comparar con el identificador real esperado sin
confundir un alias legítimo con fallback. HTTP 200, contenido no vacío y tokens consistentes son obligatorios.

## La decisión que condiciona todo lo demás

`disableLocalAuth: true` en `infra/main.bicep` deshabilita las claves locales de una cuenta nueva.
No debe aplicarse a una cuenta existente sin revisar qué otros consumidores dependen de sus claves.

La plantilla aditiva usa identidad administrada aunque el backend conserve sus claves habilitadas.
El rol `Foundry User` es el recomendado por el producto y se resuelve en la suscripción; no equivale
a un permiso exclusivo de inferencia. Su ámbito se limita a la cuenta Foundry.

## Capturas reales

Las capturas incluidas en [el artículo](docs/articulo.md) ya ocultan los identificadores del entorno.
No son maquetas ni contienen resultados de inferencia nuevos. Conservan estados, regiones y modelos públicos.

| Captura | Evidencia que debe verse | Qué ocultar |
|---|---|---|
| Gateway | Región y estado | Nombre, hostname, grupo, suscripción y perfil |
| Identidad y backend | Identidad habilitada y proveedor Foundry | GUID, endpoint, ID de recurso y nombres reales |
| Modelos y alias | Alias de ejemplo, modelo público y API | Nombre identificativo del proveedor |
| Contrato en terminal | 401 sin clave, 401 clave mala, 404 modelo ausente, 200 válido, modelo y tokens | Claves, rutas locales y datos de infraestructura |
| Clientes | Modelo solicitado, modelo servido, contenido, latencia y tokens | Headers y cualquier identificador del entorno |

El navegador integrado tiene una sesión distinta de Azure CLI: puede pedir otro inicio de sesión.
No captures pantallas de creación/revelado de claves, variables de entorno completas, headers,
historial con credenciales, herramientas de red ni volcados de depuración.
El JSON de `-OutputPath` incluye comprobaciones y uso, no credenciales ni headers.
Los originales de `evidence/`, el plan y parámetros privados de `.azure/`, la configuración
de `.vscode/` y los archivos `*.local.*` no forman parte del repositorio público.

El portal de AI Gateway requiere una cuenta de trabajo o escuela de Microsoft Entra. Una cuenta personal puede
funcionar en Azure CLI y ser rechazada por este inicio de sesión web. Para consultar y capturar,
usa una cuenta organizativa con acceso de lectura al ámbito necesario, sin asignarle roles administrativos.

Las cuatro capturas conservadas pertenecen a la ejecución original sin observabilidad. Las plantillas
nuevas no convierten esas imágenes en evidencia de ingesta o métricas integradas. Las tres capturas
adicionales muestran Application Insights vinculado, una consulta real de Log Analytics y el dashboard
con sus cuatro paneles. Se revisaron visualmente ocultando nombres, IDs, perfil y datos de instrumentación.

Para limpiar, revoca la clave temporal y elimina primero el exportador, después el gateway creado,
su asignación de rol en Foundry y el dashboard. Si son exclusivos del laboratorio, elimina Application
Insights y Log Analytics; comprueba también los recursos y permisos administrados de OTLP.
Conserva Foundry, sus despliegues y el grupo compartido. La caducidad de la clave no elimina los recursos.

## Publicación

El [artículo](docs/articulo.md) incluye siete capturas anonimizadas: cuatro de la ejecución original
y tres de la ampliación de observabilidad, con sus resultados separados.
El ejemplo se publica en [jmfloreszazo/ai-gateway-preview-lab](https://github.com/jmfloreszazo/ai-gateway-preview-lab)
para que otros usuarios lo clonen o hagan fork. Conserva la licencia y revisa el contenido que vas a versionar.

```powershell
./scripts/04-prepare-publication.ps1 -CheckOnly
# Solo después de revisar visualmente todas las imágenes:
./scripts/04-prepare-publication.ps1 -ImagesReviewed
```

Ambos comandos son de solo lectura: no crean ZIP, manifiestos ni evidencias y no publican en GitHub.
El control no ejecuta Azure ni hace inferencias. No sustituye la revisión visual ni un escáner general
de secretos; sin la lista local de identificadores solo aplica comprobaciones genéricas.

Publica con Git o GitHub Desktop respetando [.gitignore](.gitignore). Si partes de una carpeta sin
repositorio, puedes preparar el contenido así y revisarlo antes del commit:

```powershell
git init -b main
git add .gitignore .github AiGateway.sln Directory.Build.props LICENSE README.md infra scripts src tests docs
git status --short
git diff --cached --stat
git diff --cached
```

No subas la carpeta completa por la web ni uses `git add -f`: podrías incluir archivos ignorados.
No publiques claves, archivos `.local.*`, `.env*`, salidas reales de despliegue, evidencias privadas
ni `bin`/`obj`. Cada usuario debe configurar su tenant, suscripción, grupo, modelos y permisos.

## Aviso de vista previa

A fecha de la revisión del 9 de noviembre de 2026, la documentación pública indica East US 2 y
Sweden Central para la vista previa. La página de precios indica que los detalles están pendientes:
no se debe asumir coste cero. Inferencia, ingesta, retención y métricas pueden generar cargos.
Úsalo con cargas no críticas y plan de limpieza; no atribuyas al recurso nuevo las garantías del APIM clásico.

La API actual puede compilar con avisos BCP081 si Bicep aún no dispone de sus tipos. Eso no es una
validación completa de propiedades: contrasta el OpenAPI publicado y exige validación remota y `what-if`.
Los campos nuevos de OTLP tampoco están todos en los tipos locales de Bicep: la definición de
Application Insights sigue el patrón `union()` del ejemplo oficial y el exportador los lee con `any()`.
Las limitaciones documentadas del recurso nuevo incluyen ausencia de private endpoint de entrada
y de la política `contentSafety`. No afirmes que esas capacidades están probadas por este laboratorio.

La clave de runtime tiene alcance de gateway. Si necesitas acotar consumidores a un subconjunto de
assets, hoy la frontera es desplegar un gateway por dominio de confianza.

## Licencia

MIT. Ver [LICENSE](LICENSE).
