# Shared setup for provision.sh and deploy.sh. Sourced from the repository root.

# Load .env and export its values so Terraform and the Azure CLI can see them
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
environment="${TF_VAR_environment:-$(tf_default environment)}"
location="${TF_VAR_location:-$(tf_default location)}"
location_short="${TF_VAR_location_short:-$(tf_default location_short)}"

# Resource names; keep in sync with infra/main.tf
app_resource_group="rg-$project-$environment-$location_short"
app_name="stapp-$project-$environment-$location_short"
