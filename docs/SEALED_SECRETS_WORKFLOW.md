# Sealed Secrets GitOps Workflow

This document describes how to securely manage secrets in our GitOps workflow using Bitnami Sealed Secrets.
With this workflow, you can safely commit encrypted secrets to the GitHub repository. The `SealedSecret` controller running in the Kubernetes cluster automatically decrypts them into standard `Secret` objects.

## Prerequisites
1. You must be connected to the Kubernetes cluster (`kubectl`).
2. Install the `kubeseal` CLI tool on your local machine:
   - Mac: `brew install kubeseal`
   - Linux: `wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/kubeseal-linux-amd64 -O kubeseal && sudo mv kubeseal /usr/local/bin/kubeseal && sudo chmod +x /usr/local/bin/kubeseal`

## Installation (Cluster Admin)
If the Sealed Secrets controller is not installed in the cluster, apply the manifests:
```bash
kubectl apply -f kubernetes/sealed-secrets/controller.yaml
```

---

## 1. Creating a New Secret (Sealing Workflow)

We have provided a utility script to make sealing secrets effortless.

### Step 1: Create an environment file
Create a local `.env.dev` file (this file is `.gitignore`'d and will NOT be pushed to GitHub) containing your sensitive variables:
```env
MONGODB_URI=mongodb+srv://admin:my-super-secret-password@cluster.mongodb.net
JWT_SECRET=this-is-a-very-secure-jwt-key
CLIENT_URL=https://dev.chatapp.com
```

### Step 2: Run the sealing script
Use the utility script to generate the `SealedSecret` resource:
```bash
# Usage: ./scripts/seal-secret.sh <env> <namespace>
./scripts/seal-secret.sh dev chat-app-dev
```
This will generate an encrypted manifest at `kubernetes/sealed-secrets/examples/dev-sealed-secret.yaml`.

### Step 3: GitOps Promotion
You can now safely add, commit, and push this file to the repository:
```bash
git add kubernetes/sealed-secrets/examples/dev-sealed-secret.yaml
git commit -m "chore(security): add dev environment secrets"
git push
```
ArgoCD will synchronize the `SealedSecret` manifest to the cluster, where the controller will decrypt it into a normal `Secret` named `chat-app-backend-secret`.

---

## 2. Secret Rotation Workflow

To rotate a compromised or expired secret, you simply overwrite the existing `SealedSecret`.

### Step 1: Update your local environment file
Modify your local `.env.dev` file with the **NEW** secret values.

### Step 2: Run the rotation script
```bash
./scripts/rotate-secret.sh dev chat-app-dev
```
This script will re-encrypt the entire file and overwrite the old `SealedSecret` manifest.

### Step 3: Push and Restart
Commit the updated `SealedSecret` and push to Git.
Once ArgoCD syncs the changes, the cluster's underlying `Secret` will be updated. You will need to trigger a rollout restart of your backend pods so they pick up the new environment variables:
```bash
kubectl rollout restart deployment/chat-app-backend -n chat-app-dev
```
