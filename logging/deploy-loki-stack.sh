#!/bin/bash

# Centralized Logging Stack Deployment Script
# Deploys Loki, Promtail, and Grafana integration

set -e

# Configuration
NAMESPACE="logging"
HELM_CHART="grafana/loki-stack"
HELM_VERSION="2.9.4"
RELEASE_NAME="logging"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Create namespace
create_namespace() {
    log_step "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        log_warn "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace $NAMESPACE
        log_info "Namespace $NAMESPACE created"
    fi
}

# Add Helm repository
add_helm_repo() {
    log_step "Adding Grafana Helm repository..."
    
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    log_info "Helm repository added and updated"
}

# Deploy Loki stack
deploy_loki_stack() {
    log_step "Deploying Loki stack..."
    
    # Get the directory of this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VALUES_FILE="$SCRIPT_DIR/loki-stack-values.yaml"
    
    if [ ! -f "$VALUES_FILE" ]; then
        log_error "Values file not found: $VALUES_FILE"
        exit 1
    fi
    
    # Check if release already exists
    if helm list -n $NAMESPACE | grep -q "^$RELEASE_NAME"; then
        log_warn "Release $RELEASE_NAME already exists in namespace $NAMESPACE"
        log_info "Upgrading existing release..."
        helm upgrade $RELEASE_NAME $HELM_CHART \
            --namespace $NAMESPACE \
            --version $HELM_VERSION \
            --values $VALUES_FILE \
            --wait \
            --timeout 10m
    else
        log_info "Installing new release..."
        helm install $RELEASE_NAME $HELM_CHART \
            --namespace $NAMESPACE \
            --version $HELM_VERSION \
            --values $VALUES_FILE \
            --wait \
            --timeout 10m
    fi
    
    log_info "Loki stack deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --all \
        --timeout=300s
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n $NAMESPACE
    
    # Check persistent volumes
    log_info "Checking persistent volumes..."
    kubectl get pvc -n $NAMESPACE
    
    log_info "Deployment verification completed"
}

# Configure RBAC for Promtail
configure_rbac() {
    log_step "Configuring RBAC for Promtail..."
    
    # Create ServiceAccount with proper permissions
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail-cluster-role
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources:
  - configmaps
  verbs: ["get"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs:
  - "/metrics"
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail-cluster-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail-cluster-role
subjects:
- kind: ServiceAccount
  name: promtail
  namespace: $NAMESPACE
EOF
    
    log_info "RBAC configuration completed"
}

# Create log retention configuration
create_retention_config() {
    log_step "Creating log retention configuration..."
    
    # Create ConfigMap for retention policies
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-retention-config
  namespace: $NAMESPACE
data:
  retention.yaml: |
    limits_config:
      retention_period: 30d
      ingestion_rate_mb: 16
      ingestion_burst_size_mb: 32
      per_stream_rate_limit: 16MB
      per_stream_rate_limit_burst: 32MB
      max_series_per_metric: 100000
      max_series_per_user: 100000
      max_global_series_per_user: 100000
      
    chunk_store_config:
      max_look_back_period: 0s
      
    table_manager:
      retention_deletes_enabled: true
      retention_period: 30d
      
    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h
EOF
    
    log_info "Log retention configuration created"
}

# Display access information
display_access_info() {
    log_step "Displaying access information..."
    
    echo ""
    echo "=== 📊 Centralized Logging Stack Access ==="
    echo ""
    echo "🔍 Loki:"
    echo "  kubectl port-forward svc/logging-loki -n $NAMESPACE 3100:3100"
    echo "  URL: http://localhost:3100"
    echo ""
    echo "📈 Grafana (with Loki integration):"
    echo "  kubectl port-forward svc/logging-grafana -n $NAMESPACE 3000:80"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "📋 Loki API:"
    echo "  Health check: curl http://localhost:3100/ready"
    echo "  Query logs: curl -G -s 'http://localhost:3100/loki/api/v1/query_range' --data-urlencode 'query={job=\"containerlogs\"}'"
    echo ""
    echo "📊 Log Sources:"
    echo "  - Container logs: {job=\"containerlogs\"}"
    echo "  - Systemd logs: {job=\"systemd\"}"
    echo "  - Kubernetes API: {job=\"kubernetes-apiserver\"}"
    echo "  - Kubernetes events: {job=\"kubernetes-events\"}"
    echo ""
    echo "🔧 Configuration Files:"
    echo "  - Loki values: $SCRIPT_DIR/loki-stack-values.yaml"
    echo "  - Retention config: kubectl get configmap loki-retention-config -n $NAMESPACE -o yaml"
    echo ""
}

# Display logging capabilities
display_capabilities() {
    log_step "Displaying logging capabilities..."
    
    echo ""
    echo "=== 📊 Centralized Logging Capabilities ==="
    echo ""
    echo "🔍 Log Collection:"
    echo "  ✅ Container logs from all namespaces"
    echo "  ✅ Pod logs with structured metadata"
    echo "  ✅ Systemd service logs"
    echo "  ✅ Kubernetes API server logs"
    echo "  ✅ Kubernetes events"
    echo ""
    echo "📈 Log Processing:"
    echo "  ✅ JSON log parsing and extraction"
    echo "  ✅ Label-based log routing"
    echo "  ✅ Timestamp normalization"
    echo "  ✅ Stream-based log organization"
    echo ""
    echo "🗄️ Storage & Retention:"
    echo "  ✅ 30-day log retention"
    echo "  ✅ Efficient log compression"
    echo "  ✅ Configurable retention policies"
    echo "  ✅ Persistent storage backend"
    echo ""
    echo "📊 Query & Visualization:"
    echo "  ✅ LogQL query language"
    echo "  ✅ Grafana integration"
    echo "  ✅ Real-time log streaming"
    echo "  ✅ Log aggregation and filtering"
    echo ""
    echo "🔧 Key Features:"
    echo "  - Multi-tenant log aggregation"
    echo "  - High-performance indexing"
    echo "  - Scalable architecture"
    echo "  - Prometheus-compatible metrics"
    echo ""
}

# Main function
main() {
    log_info "🚀 Starting Centralized Logging Stack Deployment..."
    echo ""
    
    check_prerequisites
    create_namespace
    add_helm_repo
    configure_rbac
    create_retention_config
    deploy_loki_stack
    verify_deployment
    display_capabilities
    display_access_info
    
    echo ""
    log_info "🎉 Centralized logging stack deployment completed successfully!"
    log_info "📚 Please save the access information above for future reference."
    echo ""
    log_info "🔧 Next steps:"
    echo "  1. Port-forward services to access Grafana and Loki"
    echo "  2. Create log dashboards in Grafana"
    echo "  3. Set up log alerts based on your requirements"
    echo "  4. Configure log retention policies as needed"
    echo ""
}

# Run main function
main "$@"
