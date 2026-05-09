#!/bin/bash

# Complete Enterprise Monitoring Deployment Script
# Deploys all monitoring components for the Chat Application

set -e

# Configuration
NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Deploy kube-prometheus-stack
deploy_prometheus_stack() {
    log_step "Deploying kube-prometheus-stack..."
    
    # Run the deployment script
    if [ -f "$SCRIPT_DIR/deploy-kube-prometheus-stack.sh" ]; then
        chmod +x "$SCRIPT_DIR/deploy-kube-prometheus-stack.sh"
        "$SCRIPT_DIR/deploy-kube-prometheus-stack.sh"
    else
        log_error "deploy-kube-prometheus-stack.sh not found"
        exit 1
    fi
}

# Deploy ServiceMonitors
deploy_servicemonitors() {
    log_step "Deploying ServiceMonitors..."
    
    if [ -f "$SCRIPT_DIR/backend-servicemonitor.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/backend-servicemonitor.yaml"
        log_info "ServiceMonitors deployed successfully"
    else
        log_error "backend-servicemonitor.yaml not found"
        exit 1
    fi
}

# Deploy alerting rules
deploy_alerting_rules() {
    log_step "Deploying alerting rules..."
    
    if [ -f "$SCRIPT_DIR/alerting-rules.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/alerting-rules.yaml"
        log_info "Alerting rules deployed successfully"
    else
        log_error "alerting-rules.yaml not found"
        exit 1
    fi
}

# Deploy Grafana dashboards
deploy_grafana_dashboards() {
    log_step "Deploying Grafana dashboards..."
    
    DASHBOARDS_DIR="$SCRIPT_DIR/grafana-dashboards"
    
    if [ -d "$DASHBOARDS_DIR" ]; then
        # Create ConfigMap for dashboards
        kubectl create configmap chat-app-grafana-dashboards \
            --namespace $NAMESPACE \
            --from-file="$DASHBOARDS_DIR" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        # Label the ConfigMap for Grafana sidecar
        kubectl label configmap chat-app-grafana-dashboards \
            --namespace $NAMESPACE \
            grafana_dashboard=1 \
            --overwrite
        
        log_info "Grafana dashboards deployed successfully"
    else
        log_error "grafana-dashboards directory not found"
        exit 1
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    log_step "Waiting for monitoring stack to be ready..."
    
    # Wait for Prometheus
    log_info "Waiting for Prometheus..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=prometheus \
        --timeout=300s
    
    # Wait for Grafana
    log_info "Waiting for Grafana..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=grafana \
        --timeout=300s
    
    # Wait for AlertManager
    log_info "Waiting for AlertManager..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=alertmanager \
        --timeout=300s
    
    log_info "All monitoring components are ready"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Check pods
    log_info "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n $NAMESPACE
    
    # Check ServiceMonitors
    log_info "Checking ServiceMonitors..."
    kubectl get servicemonitors -n $NAMESPACE
    
    # Check PrometheusRules
    log_info "Checking PrometheusRules..."
    kubectl get prometheusrules -n $NAMESPACE
    
    # Check ConfigMaps (dashboards)
    log_info "Checking dashboard ConfigMaps..."
    kubectl get configmaps -n $NAMESPACE | grep grafana
    
    log_info "Deployment verification completed"
}

# Display access information
display_access_info() {
    log_step "Displaying access information..."
    
    echo ""
    echo "=== 🚀 Enterprise Monitoring Stack Access ==="
    echo ""
    echo "📊 Grafana:"
    echo "  kubectl port-forward svc/monitoring-grafana -n $NAMESPACE 3000:80"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "🔍 Prometheus:"
    echo "  kubectl port-forward svc/monitoring-prometheus -n $NAMESPACE 9090:9090"
    echo "  URL: http://localhost:9090"
    echo ""
    echo "🚨 AlertManager:"
    echo "  kubectl port-forward svc/monitoring-alertmanager -n $NAMESPACE 9093:9093"
    echo "  URL: http://localhost:9093"
    echo ""
    echo "📈 Available Dashboards:"
    echo "  - Chat Application Overview"
    echo "  - Kubernetes Infrastructure"
    echo "  - Node Exporter"
    echo "  - Kubernetes API Server"
    echo ""
    echo "🎯 Prometheus Targets:"
    echo "  After port-forwarding Prometheus, visit: http://localhost:9090/targets"
    echo ""
    echo "📋 Alert Rules:"
    echo "  Check alerts in Prometheus: http://localhost:9090/alerts"
    echo "  Manage alerts in AlertManager: http://localhost:9093"
    echo ""
    echo "🔧 Configuration Files:"
    echo "  - Prometheus Values: $SCRIPT_DIR/kube-prometheus-stack-values.yaml"
    echo "  - ServiceMonitors: $SCRIPT_DIR/backend-servicemonitor.yaml"
    echo "  - Alert Rules: $SCRIPT_DIR/alerting-rules.yaml"
    echo "  - Dashboards: $SCRIPT_DIR/grafana-dashboards/"
    echo ""
}

# Display monitoring capabilities
display_capabilities() {
    log_step "Displaying monitoring capabilities..."
    
    echo ""
    echo "=== 📊 Monitoring Capabilities ==="
    echo ""
    echo "🔍 Metrics Collection:"
    echo "  ✅ Application metrics (HTTP requests, latency, errors)"
    echo "  ✅ WebSocket connections and message throughput"
    echo "  ✅ Database connection monitoring"
    echo "  ✅ Container resource usage (CPU, memory)"
    echo "  ✅ Node-level metrics (CPU, memory, disk, network)"
    echo "  ✅ Kubernetes cluster metrics"
    echo ""
    echo "📈 Dashboards:"
    echo "  ✅ Chat Application Overview (real-time app metrics)"
    echo "  ✅ Kubernetes Infrastructure (cluster health)"
    echo "  ✅ Pre-built Grafana dashboards"
    echo ""
    echo "🚨 Alerting:"
    echo "  ✅ High CPU/Memory usage (warning & critical)"
    echo "  ✅ Pod failures and restarts"
    echo "  ✅ High latency detection"
    echo "  ✅ Container crashes and OOM kills"
    echo "  ✅ Application error rates"
    echo "  ✅ Infrastructure health monitoring"
    echo ""
    echo "📊 Key Metrics Tracked:"
    echo "  - HTTP request rate and latency (50th, 95th percentile)"
    echo "  - Error rates and status codes"
    echo "  - WebSocket active connections"
    echo "  - Message throughput (sent/received)"
    echo "  - Database connection pool status"
    echo "  - User registrations and logins"
    echo "  - Container resource utilization"
    echo "  - Pod restart counts"
    echo "  - Node resource usage"
    echo ""
}

# Main function
main() {
    log_info "🚀 Starting Enterprise-grade Kubernetes Monitoring Deployment..."
    echo ""
    
    check_prerequisites
    create_namespace
    deploy_prometheus_stack
    deploy_servicemonitors
    deploy_alerting_rules
    deploy_grafana_dashboards
    wait_for_deployment
    verify_deployment
    display_capabilities
    display_access_info
    
    echo ""
    log_info "🎉 Enterprise-grade Kubernetes monitoring deployment completed successfully!"
    log_info "📚 Please save the access information above for future reference."
    echo ""
    log_info "🔧 Next steps:"
    echo "  1. Port-forward the services to access dashboards"
    echo "  2. Import additional dashboards if needed"
    echo "  3. Configure notification channels in AlertManager"
    echo "  4. Set up custom alert thresholds based on your requirements"
    echo ""
}

# Run main function
main "$@"
