# ArgoCD GitOps Architecture & Deployment Model

This document outlines the enterprise GitOps workflow using ArgoCD to continuously deliver the DevSecOps Chat Application.

## GitOps Reconciliation Flow

ArgoCD continuously monitors the remote Git repository (`https://github.com/Kalaigar-Ayesha/DevSecOps-Chat-Apllication.git`) and compares the desired state defined in the repository (specifically the `Helm/` directory) against the live state in the Kubernetes cluster.

### Self-Service Deployment Model
Our CI/CD pipelines automatically update the image tags in the `Helm/values-<env>.yaml` files upon successful builds and tests.
1. **Developer Commits**: A developer merges a PR into `develop`, `staging`, or `main`.
2. **CI Updates Git**: GitHub Actions builds the Docker image and commits the new SHA tag back to the respective branch.
3. **ArgoCD Reconciles**: ArgoCD detects the Git commit and automatically applies the Helm chart to the cluster. **Developers never need `kubectl` access.**

### Drift Detection and Self-Healing
All ArgoCD Applications are configured with:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```
- **Prune**: If a resource is deleted from Git (e.g., removing a Service), ArgoCD will safely delete it from the cluster.
- **Self-Heal**: If a cluster administrator manually alters a resource (e.g., `kubectl edit deployment`), ArgoCD detects the **drift** and immediately reverts the live state back to the Git truth. This guarantees compliance and prevents configuration drift.

## Environment Promotion Workflow

Code promotion relies strictly on branching strategies and Pull Requests:
1. **`develop` branch -> `dev` environment**:
   - Represents the latest cutting-edge code. Merges here trigger the CI pipeline, update `values-dev.yaml`, and ArgoCD automatically syncs `chat-app-dev`.
2. **`staging` branch -> `staging` environment**:
   - Create a Pull Request from `develop` to `staging`. Once merged, ArgoCD automatically syncs `chat-app-staging`, running it with higher replicas and resources.
3. **`main` branch -> `production` environment**:
   - Create a Pull Request from `staging` to `main`. This is protected by GitHub required reviewers. Once merged, ArgoCD syncs the `chat-app-prod` application, bringing the app to end-users.

## Rollback Strategy

In a pure GitOps model, **you do not use `kubectl rollout undo` or `helm rollback`.**

### To perform a rollback:
1. Identify the bad commit in GitHub that introduced the failure (typically an automated CI commit that updated the image tag).
2. Revert the commit in Git: `git revert <commit-sha>`.
3. Push the revert commit to the target branch.
4. ArgoCD will instantly detect the reverted state in Git and synchronize the cluster back to the previous, healthy configuration.
