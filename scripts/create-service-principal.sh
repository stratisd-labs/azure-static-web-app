#!/usr/bin/env sh
set -e

# Creates the service principal GitHub Actions signs in as, and trusts runs on main of
# this repository via OIDC. Safe to re-run: existing pieces are reused, not duplicated

# shellcheck source=scripts/common.sh
. ./scripts/common.sh

# owner/repo from GITHUB_REPOSITORY, or from the origin remote
repo="$GITHUB_REPOSITORY"
if [ -z "$repo" ]; then
  repo=$(git remote get-url origin 2>/dev/null | sed -n 's#.*github\.com[:/]\(.*\)$#\1#p' | sed 's#\.git$##')
fi
if [ -z "$repo" ]; then
  echo "Error: could not determine the GitHub repository; set GITHUB_REPOSITORY=<owner>/<repo>" >&2
  exit 1
fi

sp_name="sp-$project-github"
scope="/subscriptions/$TF_VAR_subscription_id"
tenant_id=$(az account show --subscription "$TF_VAR_subscription_id" --query tenantId -o tsv)

app_id=$(az ad app list --display-name "$sp_name" --query "[0].appId" -o tsv)
if [ -z "$app_id" ]; then
  echo "Creating app registration $sp_name"
  app_id=$(az ad app create --display-name "$sp_name" --query appId -o tsv)
fi

sp_object_id=$(az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true)
if [ -z "$sp_object_id" ]; then
  echo "Creating service principal for $sp_name"
  sp_object_id=$(az ad sp create --id "$app_id" --query id -o tsv)
fi

# Contributor on the subscription: Terraform creates resource groups, so a
# resource-group scope is not enough
if [ -z "$(az role assignment list --assignee "$sp_object_id" --role Contributor \
  --scope "$scope" --query "[0].id" -o tsv)" ]; then
  echo "Assigning Contributor on $scope"
  # A new service principal can take a moment to replicate, so retry briefly
  attempt=1
  until az role assignment create --assignee-object-id "$sp_object_id" \
    --assignee-principal-type ServicePrincipal --role Contributor \
    --scope "$scope" --output none; do
    if [ "$attempt" -ge 5 ]; then
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 10
  done
fi

if [ "$(az ad app federated-credential list --id "$app_id" \
  --query "length([?name=='github-main'])" -o tsv)" = "0" ]; then
  echo "Adding federated credential for $repo on main"
  az ad app federated-credential create --id "$app_id" --output none --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$repo:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
fi

# Set the repository variables with the GitHub CLI when it is signed in
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Setting repository variables on $repo"
  gh variable set ARM_CLIENT_ID --repo "$repo" --body "$app_id"
  gh variable set ARM_TENANT_ID --repo "$repo" --body "$tenant_id"
  gh variable set ARM_SUBSCRIPTION_ID --repo "$repo" --body "$TF_VAR_subscription_id"
else
  echo
  echo "Add these repository variables on $repo (Settings > Secrets and variables > Actions > Variables):"
  echo "  ARM_CLIENT_ID=$app_id"
  echo "  ARM_TENANT_ID=$tenant_id"
  echo "  ARM_SUBSCRIPTION_ID=$TF_VAR_subscription_id"
fi
