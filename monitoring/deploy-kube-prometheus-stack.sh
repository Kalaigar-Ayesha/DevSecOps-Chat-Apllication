#!/bin/bash

# Enterprise-grade Kubernetes Monitoring Deployment Script
# Deploys kube-prometheus-stack with comprehensive monitoring configuration

set -e

# Configuration
NAMESPACE="monitoring"
HELM_CHART="prometheus-community/kube-prometheus-stack"
HELM_VERSION="56.0.0"
RELEASE_NAME="monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    log_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        log_warn "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace $NAMESPACE
        log_info "Namespace $NAMESPACE created"
    fi
}

# Add Helm repository
add_helm_repo() {
    log_info "Adding Prometheus Community Helm repository..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    log_info "Helm repository added and updated"
}

# Deploy kube-prometheus-stack
deploy_monitoring() {
    log_info "Deploying kube-prometheus-stack..."
    
    # Get the directory of this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VALUES_FILE="$SCRIPT_DIR/kube-prometheus-stack-values.yaml"
    
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
    
    log_info "kube-prometheus-stack deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
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
    
    # Check ServiceMonitors
    log_info "Checking ServiceMonitors..."
    kubectl get servicemonitors -n $NAMESPACE
    
    log_info "Deployment verification completed"
}

# Display access information
display_access_info() {
    log_info "Displaying access information..."
    
    echo ""
    echo "=== Access Information ==="
    echo ""
    echo "Grafana:"
    echo "  kubectl port-forward svc/$RELEASE_NAME-grafana -n $NAMESPACE 3000:80"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "Prometheus:"
    echo "  kubectl port-forward svc/$RELEASE_NAME-prometheus -n $NAMESPACE 9090:9090"
    echo "  URL: http://localhost:9090"
    echo ""
    echo "AlertManager:"
    echo "  kubectl port-forward svc/$RELEASE_NAME-alertmanager -n $NAMESPACE 9093:9093"
    echo "  URL: http://localhost:9093"
    echo ""
    echo "Prometheus Targets:"
    echo "  After port-forwarding Prometheus, visit: http://localhost:9090/targets"
    echo ""
    echo "Grafana Dashboards:"
    echo "  After port-forwarding Grafana, visit: http://localhost:3000/dashboards"
    echo ""
}

# Main function
main() {
    log_info "Starting enterprise-grade Kubernetes monitoring deployment..."
    
    check_prerequisites
    create_namespace
    add_helm_repo
    deploy_monitoring
    verify_deployment
    display_access_info
    
    log_info "Enterprise-grade Kubernetes monitoring deployment completed successfully!"
    log_info "Please save the access information above for future reference."
}

# Run main function
main "$@"
