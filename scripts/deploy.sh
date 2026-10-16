#!/usr/bin/env sh
set -e

if [ -z "$SWA_DEPLOYMENT_TOKEN" ] && [ -f .env ]; then
  # shellcheck disable=SC1091
  . ./.env
fi

# Fall back to the token from Terraform state when running locally
if [ -z "$SWA_DEPLOYMENT_TOKEN" ] && command -v terraform >/dev/null 2>&1; then
  SWA_DEPLOYMENT_TOKEN=$(terraform -chdir=infra output -raw deployment_token 2>/dev/null || true)
fi

if [ -z "$SWA_DEPLOYMENT_TOKEN" ]; then
  echo "Error: SWA_DEPLOYMENT_TOKEN is not set" >&2
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
