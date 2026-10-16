# Azure Static Web App template

This is a template to be used for creating static web apps, hosted on Azure.

It provisions an [Azure Static Web App](https://learn.microsoft.com/azure/static-web-apps/) with Terraform and deploys the contents of `web/` to it with the SWA CLI. Both run automatically from GitHub Actions, and can also be run locally.

## Repository layout

```text
infra/              Terraform for the resource group and Static Web App
scripts/            provision.sh - runs Terraform; deploy.sh - builds (if needed) and deploys web/
web/                The site itself (a placeholder index.html to start with)
.github/workflows/  provision.yml (on infra/ changes) and deploy.yml (on web/ changes)
.vscode/tasks.json  "Provision Azure infrastructure" and "Deploy to Azure" tasks
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`
- [SWA CLI](https://azure.github.io/static-web-apps-cli/): `npm install -g @azure/static-web-apps-cli`
- Node.js and npm, only if `web/` has a build step

## Using this template

### 1. Set the project name

Resource names are derived from the `project` variable:

| Resource       | Name                       |
| -------------- | -------------------------- |
| Resource group | `rg-<project>-prod-weu`    |
| Static Web App | `stapp-<project>-prod-weu` |

Change the `default` of `project` in [infra/variables.tf](infra/variables.tf). It is `web-app` out of the box, so **change it for every new project**, otherwise resources will clash with other projects created from this template. Use lowercase letters, numbers and hyphens.

Set it in `variables.tf` rather than `terraform.tfvars`: `.tfvars` files are git-ignored, so the GitHub workflow would never see them.

The other variables can be changed the same way:

| Variable          | Default      | Description                                   |
| ----------------- | ------------ | --------------------------------------------- |
| `subscription_id` |              | Azure subscription to deploy into (see below) |
| `project`         | `web-app`    | Project name used in resource names and tags  |
| `location`        | `westeurope` | Azure region for all resources                |
| `sku_tier`        | `Free`       | Static Web App SKU (`Free` or `Standard`)     |
| `tags`            | `{}`         | Extra tags merged onto the default tags       |

> If you change `location`, also update the `-weu` suffix in the resource names in `infra/main.tf` to match the new region.

`subscription_id` is not committed. It is taken from, in order: `infra/terraform.tfvars` (copy `terraform.tfvars.example`), `ARM_SUBSCRIPTION_ID`, or locally the subscription currently selected in the Azure CLI (`az account show`).

### 2. Replace the site content

Put your site in `web/`. The included `web/index.html` is only a placeholder.

- **Plain static site:** put the HTML, CSS, JS and assets directly in `web/`. They are deployed as-is.
- **Site with a build step** (Vite, React, etc.): add a `web/package.json` with a `build` script that outputs to `web/dist/`. The deploy script runs `npm ci` and `npm run build`, then deploys `web/dist/`.

### 3. Set up Terraform state storage

Terraform state is kept in an Azure Storage account so that local runs and GitHub Actions share it. One account can hold the state of many projects: each repository gets its own `<repo-name>.tfstate` file (override with `TFSTATE_KEY`).

If your team already has a state storage account, use it. Otherwise create one (the name must be globally unique):

```sh
az group create --name rg-tfstate --location westeurope
az storage account create --name <stateaccount> --resource-group rg-tfstate --sku Standard_LRS
az storage container create --name tfstate --account-name <stateaccount> --auth-mode key
```

### 4. Configure local settings

```sh
cp .env.example .env
```

Fill in `TFSTATE_RESOURCE_GROUP` and `TFSTATE_STORAGE_ACCOUNT` (and `TFSTATE_CONTAINER` if it isn't `tfstate`). `.env` is git-ignored.

Locally, Terraform authenticates with your `az login` session, so the `ARM_*` service principal variables are optional. Set them only if you want to run as the service principal.

### 5. Provision the infrastructure

Run from the repository root, or use the **Provision Azure infrastructure** VS Code task (`Tasks: Run Task`):

```sh
sh scripts/provision.sh
```

The script runs `terraform init` against the remote state and then `terraform apply`. Locally it asks for confirmation before applying. After `apply`, the site URL is shown in the `default_hostname` output.

### 6. Deploy the site

Run from the repository root, or use the **Deploy to Azure** VS Code task:

```sh
sh scripts/deploy.sh
```

The script looks for the deployment token in this order:

1. The `SWA_DEPLOYMENT_TOKEN` environment variable
2. `SWA_DEPLOYMENT_TOKEN` in `.env`
3. The `deployment_token` Terraform output (requires `provision.sh` to have run on this machine)

To print the token yourself (e.g. to store it as a CI secret):

```sh
terraform -chdir=infra output -raw deployment_token
```

## GitHub Actions

| Workflow        | Runs on push to `main` that changes                                   | Also                |
| --------------- | --------------------------------------------------------------------- | ------------------- |
| `provision.yml` | `infra/**`, `scripts/provision.sh`, `.github/workflows/provision.yml` | Can be run manually |
| `deploy.yml`    | `web/**`                                                              |                     |

### Service principal

The provision workflow authenticates as a service principal. Create one with Contributor access to the subscription:

```sh
az ad sp create-for-rbac --name sp-<project>-github --role Contributor \
  --scopes /subscriptions/<subscription-id>
```

The output gives `appId`, `password` and `tenant`.

### Repository secrets and variables

Add these in **Settings → Secrets and variables → Actions**:

| Name                      | Kind     | Value                                                           |
| ------------------------- | -------- | --------------------------------------------------------------- |
| `ARM_CLIENT_ID`           | Secret   | Service principal `appId`                                       |
| `ARM_CLIENT_SECRET`       | Secret   | Service principal `password`                                    |
| `ARM_TENANT_ID`           | Secret   | Service principal `tenant`                                      |
| `ARM_SUBSCRIPTION_ID`     | Secret   | Subscription to deploy into                                     |
| `SWA_DEPLOYMENT_TOKEN`    | Secret   | Output of `terraform -chdir=infra output -raw deployment_token` |
| `TFSTATE_RESOURCE_GROUP`  | Variable | Resource group of the state storage account                     |
| `TFSTATE_STORAGE_ACCOUNT` | Variable | Name of the state storage account                               |
| `TFSTATE_CONTAINER`       | Variable | Optional, defaults to `tfstate`                                 |

`SWA_DEPLOYMENT_TOKEN` only exists after the first provision, so on a new project: provision first (locally or via the workflow), then add the secret, then push to `web/`.

## Tearing down

```sh
terraform -chdir=infra destroy
```

Run `provision.sh` first on a fresh clone so Terraform is initialised against the remote state.
