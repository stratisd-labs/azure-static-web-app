#!/usr/bin/env sh
set -e

# Load .env and export its values so Terraform can see them
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# Auth: Terraform uses the service principal in ARM_CLIENT_ID / ARM_CLIENT_SECRET /
# ARM_TENANT_ID when set (CI), otherwise the current `az login` session (local)
if [ -z "$TF_VAR_subscription_id" ] && [ -n "$ARM_SUBSCRIPTION_ID" ]; then
  export TF_VAR_subscription_id="$ARM_SUBSCRIPTION_ID"
fi

# Fall back to the active Azure CLI subscription when running locally
if [ -z "$TF_VAR_subscription_id" ] && [ ! -f infra/terraform.tfvars ] && command -v az >/dev/null 2>&1; then
  TF_VAR_subscription_id=$(az account show --query id -o tsv 2>/dev/null || true)
  export TF_VAR_subscription_id
fi

for var in TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT; do
  eval "value=\$$var"
  if [ -z "$value" ]; then
    echo "Error: $var is not set" >&2
    exit 1
  fi
done

# One state file per repository, unless overridden
key="${TFSTATE_KEY:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)").tfstate}"

terraform -chdir=infra init -input=false \
  -backend-config="resource_group_name=$TFSTATE_RESOURCE_GROUP" \
  -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
  -backend-config="container_name=${TFSTATE_CONTAINER:-tfstate}" \
  -backend-config="key=$key"

# Ask for confirmation locally, apply straight away in CI
if [ "$CI" = "true" ]; then
  terraform -chdir=infra apply -input=false -auto-approve
else
  terraform -chdir=infra apply
fi
