#!/usr/bin/env sh
set -e

# shellcheck source=scripts/common.sh
. ./scripts/common.sh

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
