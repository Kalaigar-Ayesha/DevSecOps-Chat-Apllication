#!/bin/bash
# scripts/seal-secret.sh
# Utility script to generate a Kubernetes Secret and encrypt it into a SealedSecret.

set -e

ENV_NAME=$1
NAMESPACE=$2

if [ -z "$ENV_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "Usage: ./seal-secret.sh <environment> <namespace>"
  echo "Example: ./seal-secret.sh dev chat-app-dev"
  exit 1
fi

# Ensure .env file exists
if [ ! -f ".env.${ENV_NAME}" ]; then
  echo "Error: .env.${ENV_NAME} file not found. Please create one with your secrets."
  exit 1
fi

echo "Generating raw Kubernetes Secret from .env.${ENV_NAME}..."
kubectl create secret generic chat-app-backend-secret \
  --namespace "$NAMESPACE" \
  --from-env-file=".env.${ENV_NAME}" \
  --dry-run=client -o yaml > raw-secret.yaml

echo "Encrypting into SealedSecret using kubeseal..."
# Assuming kubeseal is connected to the cluster where the controller is running
kubeseal \
  --format=yaml \
  --controller-namespace=kube-system \
  --controller-name=sealed-secrets-controller < raw-secret.yaml > "kubernetes/sealed-secrets/examples/${ENV_NAME}-sealed-secret.yaml"

# Cleanup the raw secret so it never hits the disk permanently
rm raw-secret.yaml

echo "Success! The SealedSecret has been saved to kubernetes/sealed-secrets/examples/${ENV_NAME}-sealed-secret.yaml"
echo "You can now safely commit this file to Git!"
