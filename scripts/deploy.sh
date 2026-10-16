#!/usr/bin/env sh
set -e

# shellcheck source=scripts/common.sh
. ./scripts/common.sh

# Use SWA_DEPLOYMENT_TOKEN when set, otherwise read it from the Static Web App
if [ -z "$SWA_DEPLOYMENT_TOKEN" ]; then
  SWA_DEPLOYMENT_TOKEN=$(az staticwebapp secrets list --name "$app_name" \
    --resource-group "$app_resource_group" --subscription "$TF_VAR_subscription_id" \
    --query properties.apiKey -o tsv)
fi

if [ -z "$SWA_DEPLOYMENT_TOKEN" ]; then
  echo "Error: no deployment token for $app_name (has it been provisioned?)" >&2
  exit 1
fi

# Build web/ if it has a build step, otherwise deploy it as plain static files
if [ -f web/package.json ]; then
  npm --prefix web ci
  npm --prefix web run build
  app_dir=./web/dist
else
  app_dir=./web
fi

swa deploy "$app_dir" \
  --deployment-token "$SWA_DEPLOYMENT_TOKEN" \
  --env production
