# Azure Static Web App template

This is a template to be used for creating static web apps, hosted on Azure.

It provisions an [Azure Static Web App](https://learn.microsoft.com/azure/static-web-apps/) with Terraform and deploys the contents of `web/` to it with the SWA CLI. Both run automatically from GitHub Actions, and can also be run locally.

## Repository layout

```text
infra/              Terraform for the resource group and Static Web App
scripts/            provision.sh - runs Terraform; deploy.sh - builds (if needed) and deploys web/;
                    common.sh - settings shared by both
web/                The site itself (a placeholder index.html to start with)
.github/workflows/  provision-and-deploy.yml - provisions and deploys on push to main
.vscode/tasks.json  "Provision Azure infrastructure" and "Deploy to Azure" tasks
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`
- [SWA CLI](https://azure.github.io/static-web-apps-cli/): `npm install -g @azure/static-web-apps-cli`
- Node.js and npm, only if `web/` has a build step

## Using this template

### 1. Set the project name

Resource names are derived from the `project`, `environment` and `location_short` variables:

| Resource       | Name                                             |
| -------------- | ------------------------------------------------ |
| Resource group | `rg-<project>-<environment>-<location_short>`    |
| Static Web App | `stapp-<project>-<environment>-<location_short>` |

Change the `default` of `project` in [infra/variables.tf](infra/variables.tf). It is `web-app` out of the box, so **change it for every new project**, otherwise resources will clash with other projects created from this template. The scripts refuse to run until it is changed. Use lowercase letters, numbers and hyphens.

Set it in `variables.tf` rather than `terraform.tfvars`: `.tfvars` files are git-ignored, so the GitHub workflow would never see them.

The other variables can be changed the same way:

| Variable          | Default      | Description                                      |
| ----------------- | ------------ | ------------------------------------------------ |
| `subscription_id` |              | Azure subscription to deploy into (see below)    |
| `project`         | `web-app`    | Project name used in resource names and tags     |
| `environment`     | `prod`       | Environment name used in resource names and tags |
| `location`        | `westeurope` | Azure region for all resources                   |
| `location_short`  | `weu`        | Short region code used in resource names         |
| `sku_tier`        | `Free`       | Static Web App SKU (`Free` or `Standard`)        |
| `tags`            | `{}`         | Extra tags merged onto the default tags          |

> If you change `location`, also update `location_short` to match the new region.

`subscription_id` is not committed. It is taken from, in order: `infra/terraform.tfvars` (copy `terraform.tfvars.example`), `ARM_SUBSCRIPTION_ID`, or locally the subscription currently selected in the Azure CLI (`az account show`).

### 2. Replace the site content

Put your site in `web/`. The included `web/index.html` is only a placeholder.

- **Plain static site:** put the HTML, CSS, JS and assets directly in `web/`. They are deployed as-is.
- **Site with a build step** (Vite, React, etc.): add a `web/package.json` with a `build` script that outputs to `web/dist/`. The deploy script runs `npm ci` and `npm run build`, then deploys `web/dist/`.

### 3. Terraform state storage

Terraform state is kept in an Azure Storage account so that local runs and GitHub Actions share it. Each project gets its own, which `provision.sh` creates on the first run:

| Resource         | Name                                              |
| ---------------- | ------------------------------------------------- |
| Resource group   | `rg-<project>-tfstate-<location_short>`           |
| Storage account  | `st<project>tf<suffix>` (letters and digits only) |
| Container / blob | `tfstate` / `terraform.tfstate`                   |

Storage account names must be globally unique, so `<suffix>` is derived from the subscription ID and project name. It is the same on every run and every machine. The account has blob versioning on, so earlier versions of the state can be restored.

The state lives outside the app's resource group on purpose: `terraform destroy` must not delete its own state.

To use an existing account instead, set `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER` and `TFSTATE_KEY` (in `.env` and as GitHub variables). The script still creates them if they don't exist.

### 4. Configure local settings

```sh
cp .env.example .env
```

Nothing in it is required. It only holds optional overrides. `.env` is git-ignored.

Locally, Terraform authenticates with your `az login` session, so the `ARM_*` service principal variables are optional. Set them only if you want to run as the service principal.

### 5. Provision the infrastructure

Run from the repository root, or use the **Provision Azure infrastructure** VS Code task (`Tasks: Run Task`):

```sh
sh scripts/provision.sh
```

The script creates the state storage if needed, runs `terraform init` against it and then `terraform apply`. Locally it asks for confirmation before applying. After `apply`, the site URL is shown in the `default_hostname` output.

### 6. Deploy the site

Run from the repository root, or use the **Deploy to Azure** VS Code task:

```sh
sh scripts/deploy.sh
```

The script reads the deployment token from the Static Web App with the Azure CLI, so no token needs to be stored. To use a specific token instead, set `SWA_DEPLOYMENT_TOKEN` in the environment or in `.env`.

## GitHub Actions

One workflow, `provision-and-deploy.yml`, runs on push to `main`. It only runs the jobs whose files changed, and deploy always waits for provision, so a push that changes both never deploys to an app that doesn't exist yet:

| Job       | Runs when the push changes                                                                            |
| --------- | ----------------------------------------------------------------------------------------------------- |
| Provision | `infra/**`, `scripts/provision.sh`, `scripts/common.sh`, `.github/workflows/provision-and-deploy.yml` |
| Deploy    | `web/**`, `scripts/deploy.sh`, `scripts/common.sh`, `.github/workflows/provision-and-deploy.yml`      |

Running it manually (**Actions → Provision and deploy → Run workflow**) runs both jobs.

### Service principal

Both jobs sign in to Azure as a service principal using [OpenID Connect](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect): GitHub issues a short-lived token for each run, so there is no client secret to store or rotate.

Create one per project with Contributor access to the subscription (it creates resource groups, so resource-group scope is not enough), and trust GitHub Actions runs on `main` of this repository:

```sh
app_id=$(az ad app create --display-name sp-<project>-github --query appId -o tsv)
az ad sp create --id "$app_id"
az role assignment create --assignee "$app_id" --role Contributor \
  --scope /subscriptions/<subscription-id>
az ad app federated-credential create --id "$app_id" --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

### Repository variables

Add these in **Settings → Secrets and variables → Actions → Variables**. None of them are secrets. Until `ARM_CLIENT_ID` is set, the workflow is skipped instead of failing:

| Name                      | Value                                                 |
| ------------------------- | ----------------------------------------------------- |
| `ARM_CLIENT_ID`           | `$app_id` from above                                  |
| `ARM_TENANT_ID`           | Tenant ID (`az account show --query tenantId -o tsv`) |
| `ARM_SUBSCRIPTION_ID`     | Subscription to deploy into                           |
| `TFSTATE_RESOURCE_GROUP`  | Optional, overrides the state resource group          |
| `TFSTATE_STORAGE_ACCOUNT` | Optional, overrides the state storage account         |
| `TFSTATE_CONTAINER`       | Optional, defaults to `tfstate`                       |
| `TFSTATE_KEY`             | Optional, defaults to `terraform.tfstate`             |

On a new project, the first push after setting the variables runs both jobs only if it changes files for both. To provision and deploy everything at once, run the workflow manually.

## Tearing down

```sh
terraform -chdir=infra destroy
```

Run `provision.sh` first on a fresh clone so Terraform is initialised against the remote state.

This leaves the state storage in place. Once you no longer need the state, remove it too:

```sh
az group delete --name rg-<project>-tfstate-<location_short>
```
