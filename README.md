# AI Gateway demo

Bicep infrastructure for the dedicated Azure API Management **AI Gateway tier
(preview)**, with workspace-backed Application Insights and GitHub Actions
deployment.

## Resources

`infra/main.bicep` creates the following resources in an existing resource group:

| Resource | Configuration |
| --- | --- |
| AI Gateway | `Microsoft.ApiManagement/aigateways@2026-09-01-preview`, `Consumption` SKU, system-assigned managed identity |
| Application Insights | Workspace-based, backed by the Log Analytics workspace below |
| Log Analytics workspace | `PerGB2018`, 30-day retention by default |

This uses the dedicated AI Gateway resource, **not** a classic APIM
`Microsoft.ApiManagement/service` instance. The
[current ARM reference](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/aigateways)
publishes `2026-09-01-preview`; the
[overview](https://learn.microsoft.com/azure/api-management/ai-gateway-overview)
still mentions an earlier preview API version.

The native resource accepts `Consumption` and `Premium` SKU names; `AIGateway`
is not a valid SKU for this resource type. This demo uses `Consumption`.

All resources default to **East US 2**. Edit `infra/main.parameters.json` to change
the region to `swedencentral`, resource name prefix, or log retention. These are
the two documented preview regions; subscription eligibility and capacity still
apply. Generated names have a stable suffix derived from the resource group ID.
The prefix must contain only lowercase letters, digits, or hyphens, start and end
with a letter or digit, and be 3-10 characters long. Changing the prefix or
resource group creates new resources rather than renaming existing ones.

The gateway is initially empty: no models, MCP tools, runtime keys, backend role
assignments, or private networking are configured. Preview availability is
best-effort, without an SLA. Log ingestion and other related services can incur
charges; see the overview for current preview pricing terms.

## One-time Azure and GitHub setup

Use an Azure identity with permission to create a resource group and assign roles
for the setup below. Choose your subscription explicitly:

```bash
az login
az account set --subscription "<subscription-id>"
az group create --name "<resource-group>" --location eastus2

az provider register --namespace Microsoft.ApiManagement --wait
az provider register --namespace Microsoft.Insights --wait
az provider register --namespace Microsoft.OperationalInsights --wait
```

Create an Entra application/service principal or a user-assigned managed identity
for GitHub Actions. Grant it **Contributor on this resource group**, not on the
entire subscription. Provider registration and resource group creation above are
bootstrap operations; the pipeline does neither.

Add a federated identity credential with these values:

| Setting | Value |
| --- | --- |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Subject | `repo:anotherRedbeard/ai-gateway-demo:environment:azure` |

In GitHub, create an environment named **`azure`** under **Settings > Environments**.
Restrict its deployment branches to `main`. Add these environment variables:

| Variable | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | Application/client ID of the deployment identity |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `AZURE_RESOURCE_GROUP` | Existing target resource group name |

No client secret is needed: the workflow uses GitHub's OIDC token. If you fork or
rename this repository, change the federated credential subject accordingly.
Optional required reviewers on the environment can gate automatic deployments.

## Pipeline

`.github/workflows/deploy-infrastructure.yml` builds and lints Bicep on relevant
pull requests and pushes to `main`. Pushes changing `infra/**` or the workflow
itself then sign in to Azure, run ARM validation and what-if, and deploy in
**incremental** mode. Unrelated pushes do not redeploy infrastructure.

You can also run **Deploy infrastructure** manually from the Actions tab after
the workflow is on `main`; select `main` to deploy. Pull requests never get Azure
credentials or deploy resources. Deployments are serialized and running
deployments are not canceled by newer pushes.

ARM validation fails the run before deployment if the subscription lacks access
to this preview or Azure rejects the configuration. What-if is a preview, not an
approval gate: an enabled push deployment proceeds automatically.

Bicep versions without the new gateway type in their type catalog can emit
`BCP081` while still compiling successfully. The resource declaration follows the
published ARM reference; the authenticated pipeline's ARM validation checks it
against Azure before deployment.

## Local deployment

With Azure CLI and Bicep installed, select the intended subscription first:

```bash
az account set --subscription "<subscription-id>"
az bicep lint --file infra/main.bicep

az deployment group what-if \
  --resource-group "<resource-group>" \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json

az deployment group create \
  --name ai-gateway-demo \
  --resource-group "<resource-group>" \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  --mode Incremental \
  --query properties.outputs
```

## Connect gateway monitoring

The `2026-09-01-preview` native gateway API does not publish a telemetry-exporter
child resource. The template therefore provisions the monitoring resources but
does **not** automatically connect gateway telemetry to Application Insights.
Do not substitute classic APIM logger/diagnostic resources for the new tier.

After deployment, open [the AI Gateway portal](https://ai.gateway.azure.com),
select the gateway, and configure its monitoring destination to use the deployed
Application Insights resource. Follow
[the monitoring guide](https://learn.microsoft.com/azure/api-management/ai-gateway-govern-secure-assets#monitoring).
Token usage is the documented OpenTelemetry export signal in this preview; do not
assume all logs, traces, or prompt/response capture are available.

Import a model or configure an MCP server separately, then create a runtime key
and send requests to verify telemetry. Copy the exact runtime endpoint from the
portal rather than constructing it from the gateway name. When using managed
identity for a model backend, grant the gateway identity the documented backend
role at that backend's scope. Runtime keys and Application Insights connection
strings are deliberately not emitted as deployment outputs.
