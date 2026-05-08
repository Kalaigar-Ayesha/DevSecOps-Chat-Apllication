#!/bin/bash
# scripts/rotate-secret.sh
# Utility script to rotate and re-seal a secret.

set -e

ENV_NAME=$1
NAMESPACE=$2

if [ -z "$ENV_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "Usage: ./rotate-secret.sh <environment> <namespace>"
  echo "Example: ./rotate-secret.sh prod chat-app-prod"
  exit 1
fi

echo "=== Secret Rotation Workflow ==="
echo "1. Update your local .env.${ENV_NAME} with the NEW secret values."
echo "2. Press any key once you have updated the file..."
read -n 1 -s -r -p ""

# Run the standard sealing script which overwrites the old sealed secret
./scripts/seal-secret.sh "$ENV_NAME" "$NAMESPACE"

echo "Rotation complete!"
echo "Next steps:"
echo "1. git add kubernetes/sealed-secrets/examples/${ENV_NAME}-sealed-secret.yaml"
echo "2. git commit -m \"chore(security): rotate ${ENV_NAME} secrets\""
echo "3. git push"
echo "ArgoCD will automatically apply the new SealedSecret, and the Sealed-Secrets controller will decrypt it."
echo "Note: You may need to restart the backend pods so they pick up the new environment variables."
