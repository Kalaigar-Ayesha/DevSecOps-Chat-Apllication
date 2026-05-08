# Helm Deployment Lifecycle

This document outlines the architecture and deployment lifecycle of the enterprise-grade Helm chart for the DevSecOps Chat Application, orchestrated through FluxCD GitOps workflows.

## Helm Chart Architecture

The chart is located in the `Helm/` directory and is designed to be highly modular and environment-agnostic. 
The core templates (`Helm/templates/`) do not contain hardcoded values. Instead, they dynamically render based on values injected at deployment time.

### Configuration Hierarchy
1. **`values.yaml`**: The fallback/default configuration (useful for local minikube deployments).
2. **`values-<env>.yaml`**: Environment-specific overrides.
   - `values-dev.yaml`: Minimal resources, `dev.*` ingress hosts, scaled down.
   - `values-staging.yaml`: Moderate resources, replica counts increased, HPA enabled.
   - `values-prod.yaml`: High availability, aggressive autoscaling, production ingress.

## GitOps Workflow (FluxCD)

We have implemented an automated GitOps model using FluxCD. The deployment lifecycle is completely hands-off and triggered by Git commits.

### The Mechanism
1. **GitHub Actions CI**: On every push to a target branch (`develop`, `staging`, `main`), the CI pipeline builds and scans the Docker image.
2. **Automated Manifest Update**: The CI pipeline dynamically updates the image tags in the target branch's `values-<env>.yaml` and commits the change.
3. **FluxCD Reconciliation**: FluxCD runs inside the Kubernetes cluster and continuously monitors the GitHub repository.

### Flux Components (`flux-releases/`)
Each environment has a dedicated release manifest (e.g., `dev-release.yaml`):
- **`GitRepository`**: Tells Flux which branch to track (`develop` for dev, `staging` for staging, `main` for prod).
- **`HelmRelease`**: Tells Flux to install the Helm chart located at `./Helm`, merging `values.yaml` with the specific `values-<env>.yaml` file.

## Manual Interventions (Break-glass)

While GitOps handles automated deployments, you can deploy the chart manually for testing or emergency overrides:

```bash
# Dry run the template locally for production
helm template chat-app ./Helm -f ./Helm/values.yaml -f ./Helm/values-prod.yaml

# Manually upgrade/install the dev environment
helm upgrade --install chat-app-dev ./Helm \
  -f ./Helm/values.yaml \
  -f ./Helm/values-dev.yaml \
  --namespace chat-app-dev --create-namespace
```

### Rollbacks
In a GitOps environment, **rollbacks are performed by reverting the Git commit**. 
If a bad image tag is deployed, use `git revert <commit-hash>` to restore the previous `values-<env>.yaml` state. FluxCD will automatically detect the revert and downgrade the Helm release in the cluster.
