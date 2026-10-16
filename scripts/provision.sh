#!/usr/bin/env sh
set -e

# Load .env and export its values so Terraform can see them
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# Default value of a variable in infra/variables.tf
tf_default() {
  awk -v name="$1" '
    $0 ~ "^variable \"" name "\"" { found = 1 }
    found && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
  ' infra/variables.tf
}

# Auth: Terraform uses the service principal in ARM_CLIENT_ID / ARM_CLIENT_SECRET /
# ARM_TENANT_ID when set (CI), otherwise the current `az login` session (local)
if [ -n "$ARM_CLIENT_ID" ] && [ -n "$ARM_CLIENT_SECRET" ] && ! az account show >/dev/null 2>&1; then
  az login --service-principal --username "$ARM_CLIENT_ID" --password "$ARM_CLIENT_SECRET" \
    --tenant "$ARM_TENANT_ID" --output none
fi

if [ -z "$TF_VAR_subscription_id" ] && [ -n "$ARM_SUBSCRIPTION_ID" ]; then
  TF_VAR_subscription_id="$ARM_SUBSCRIPTION_ID"
fi

if [ -z "$TF_VAR_subscription_id" ] && [ -f infra/terraform.tfvars ]; then
  TF_VAR_subscription_id=$(sed -n 's/^subscription_id *= *"\(.*\)"/\1/p' infra/terraform.tfvars)
fi

# Fall back to the active Azure CLI subscription when running locally
if [ -z "$TF_VAR_subscription_id" ]; then
  TF_VAR_subscription_id=$(az account show --query id -o tsv 2>/dev/null || true)
fi

if [ -z "$TF_VAR_subscription_id" ]; then
  echo "Error: no Azure subscription found (run 'az login' or set ARM_SUBSCRIPTION_ID)" >&2
  exit 1
fi
export TF_VAR_subscription_id

project="${TF_VAR_project:-$(tf_default project)}"
location="${TF_VAR_location:-$(tf_default location)}"
location_short="${TF_VAR_location_short:-$(tf_default location_short)}"

# Per-project state storage. The account name must be globally unique, 3-24 lowercase
# letters and digits, so it gets a stable suffix derived from the subscription and project
suffix=$(printf '%08x' "$(printf '%s/%s' "$TF_VAR_subscription_id" "$project" | cksum | cut -d' ' -f1)")
state_rg="${TFSTATE_RESOURCE_GROUP:-rg-$project-tfstate-$location_short}"
state_account="${TFSTATE_STORAGE_ACCOUNT:-st$(printf '%s' "$project" | tr -cd 'a-z0-9' | cut -c1-12)tf$suffix}"
state_container="${TFSTATE_CONTAINER:-tfstate}"
state_key="${TFSTATE_KEY:-terraform.tfstate}"

# Create the state storage on first run; later runs leave it as it is
if [ "$(az group exists --name "$state_rg" --subscription "$TF_VAR_subscription_id")" != "true" ]; then
  echo "Creating resource group $state_rg"
  az group create --name "$state_rg" --location "$location" \
    --subscription "$TF_VAR_subscription_id" \
    --tags project="$project" managed_by=provision.sh --output none
fi

if ! az storage account show --name "$state_account" --resource-group "$state_rg" \
  --subscription "$TF_VAR_subscription_id" >/dev/null 2>&1; then
  echo "Creating storage account $state_account"
  az storage account create --name "$state_account" --resource-group "$state_rg" \
    --subscription "$TF_VAR_subscription_id" --location "$location" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
    --allow-blob-public-access false --output none
  # Keep previous versions of the state file so a bad apply can be rolled back
  az storage account blob-service-properties update --account-name "$state_account" \
    --resource-group "$state_rg" --subscription "$TF_VAR_subscription_id" \
    --enable-versioning true --output none
fi

az storage container create --name "$state_container" --account-name "$state_account" \
  --subscription "$TF_VAR_subscription_id" --auth-mode key --output none

terraform -chdir=infra init -input=false -reconfigure \
  -backend-config="resource_group_name=$state_rg" \
  -backend-config="storage_account_name=$state_account" \
  -backend-config="container_name=$state_container" \
  -backend-config="key=$state_key" \
  -backend-config="subscription_id=$TF_VAR_subscription_id"

# Ask for confirmation locally, apply straight away in CI
if [ "$CI" = "true" ]; then
  terraform -chdir=infra apply -input=false -auto-approve
else
  terraform -chdir=infra apply
fi
