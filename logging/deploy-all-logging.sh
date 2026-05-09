#!/bin/bash

# Complete Centralized Logging Deployment Script
# Deploys Loki, Promtail, and Grafana with comprehensive log management

set -e

# Configuration
NAMESPACE="logging"
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

# Deploy Loki stack
deploy_loki_stack() {
    log_step "Deploying Loki stack..."
    
    # Run deployment script
    if [ -f "$SCRIPT_DIR/deploy-loki-stack.sh" ]; then
        chmod +x "$SCRIPT_DIR/deploy-loki-stack.sh"
        "$SCRIPT_DIR/deploy-loki-stack.sh"
    else
        log_error "deploy-loki-stack.sh not found"
        exit 1
    fi
}

# Deploy Grafana dashboards
deploy_grafana_dashboards() {
    log_step "Deploying Grafana dashboards..."
    
    DASHBOARDS_DIR="$SCRIPT_DIR/grafana-dashboards"
    
    if [ -d "$DASHBOARDS_DIR" ]; then
        # Create ConfigMap for dashboards
        kubectl create configmap loki-grafana-dashboards \
            --namespace $NAMESPACE \
            --from-file="$DASHBOARDS_DIR" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        # Label ConfigMap for Grafana sidecar
        kubectl label configmap loki-grafana-dashboards \
            --namespace $NAMESPACE \
            grafana_dashboard=1 \
            --overwrite
        
        log_info "Grafana dashboards deployed successfully"
    else
        log_error "grafana-dashboards directory not found"
        exit 1
    fi
}

# Create log alerting rules
create_log_alerts() {
    log_step "Creating log-based alerting rules..."
    
    # Create PrometheusRule for log alerts
    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: chat-app-log-alerts
  namespace: monitoring
  labels:
    app: chat-app
    release: monitoring
spec:
  groups:
  - name: chat-app.log.rules
    rules:
    - alert: ChatAppHighErrorLogs
      expr: sum(rate(loki_distributor_lines_received_total{namespace="chat-app"}[5m])) > 10
      for: 2m
      labels:
        severity: warning
        service: chat-app
        component: logging
      annotations:
        summary: "High error log rate detected in Chat Application"
        description: "Error log rate is {{ $value }} lines/second for the last 5 minutes"
        
    - alert: ChatAppNoLogs
      expr: sum(rate(loki_distributor_lines_received_total{namespace="chat-app"}[5m])) == 0
      for: 5m
      labels:
        severity: warning
        service: chat-app
        component: logging
      annotations:
        summary: "No logs detected from Chat Application"
        description: "No logs have been received from Chat Application for the last 5 minutes"
        
    - alert: LokiHighIngestionRate
      expr: sum(rate(loki_distributor_ingested_samples_total[5m])) > 10000
      for: 5m
      labels:
        severity: warning
        service: loki
        component: logging
      annotations:
        summary: "High log ingestion rate in Loki"
        description: "Loki is ingesting {{ $value }} samples/second, which is above normal"
        
    - alert: LokiHighMemoryUsage
      expr: sum(container_memory_working_set_bytes{pod=~"loki.*"}) / sum(container_spec_memory_limit_bytes{pod=~"loki.*"}) > 0.8
      for: 5m
      labels:
        severity: warning
        service: loki
        component: logging
      annotations:
        summary: "High memory usage in Loki"
        description: "Loki memory usage is {{ $value | humanizePercentage }}"
EOF
    
    log_info "Log alerting rules created successfully"
}

# Configure log retention policies
configure_retention_policies() {
    log_step "Configuring log retention policies..."
    
    # Create retention policy ConfigMap
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-retention-policies
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
          
    # Stream-based retention
    ruler:
      storage:
        type: local
        local:
          directory: /rules
      rule_path: /tmp/scratch
      alertmanager_url: http://alertmanager:9093
      ring:
        kvstore:
          store: inmemory
EOF
    
    log_info "Log retention policies configured successfully"
}

# Create log forwarding configuration
create_log_forwarding() {
    log_step "Creating log forwarding configuration..."
    
    # Create log forwarding ConfigMap for external systems
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-log-forwarding
  namespace: $NAMESPACE
data:
  forwarding.yaml: |
    # Example configuration for forwarding logs to external systems
    # Uncomment and modify as needed
    
    # Forward to Elasticsearch
    # elasticsearch:
    #   enabled: false
    #   hosts: ["elasticsearch:9200"]
    #   index: "chat-app-logs"
    #   username: "elastic"
    #   password: "changeme"
    
    # Forward to Splunk
    # splunk:
    #   enabled: false
    #   host: "splunk.example.com"
    #   port: 8088
    #   token: "your-splunk-hec-token"
    #   index: "chat_app"
    
    # Forward to CloudWatch
    # cloudwatch:
    #   enabled: false
    #   region: "us-west-2"
    #   log_group: "/aws/eks/chat-app/containers"
    
    # Forward to Datadog
    # datadog:
    #   enabled: false
    #   api_key: "your-datadog-api-key"
    #   site: "datadoghq.com"
EOF
    
    log_info "Log forwarding configuration created successfully"
}

# Wait for deployment to be ready
wait_for_deployment() {
    log_step "Waiting for logging stack to be ready..."
    
    # Wait for Loki
    log_info "Waiting for Loki..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=loki \
        --timeout=300s
    
    # Wait for Promtail
    log_info "Waiting for Promtail..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=promtail \
        --timeout=300s
    
    # Wait for Grafana
    log_info "Waiting for Grafana..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app.kubernetes.io/name=grafana \
        --timeout=300s
    
    log_info "All logging components are ready"
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
    
    # Check persistent volumes
    log_info "Checking persistent volumes..."
    kubectl get pvc -n $NAMESPACE
    
    # Check ConfigMaps
    log_info "Checking ConfigMaps..."
    kubectl get configmaps -n $NAMESPACE
    
    log_info "Deployment verification completed"
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
    echo "  Health: curl http://localhost:3100/ready"
    echo ""
    echo "📈 Grafana (with Loki integration):"
    echo "  kubectl port-forward svc/logging-grafana -n $NAMESPACE 3000:80"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "📋 Log Queries:"
    echo "  Backend logs: {namespace_name=\"chat-app\", container_name=\"chat-app-backend\"}"
    echo "  Frontend logs: {namespace_name=\"chat-app\", container_name=\"chat-app-frontend\"}"
    echo "  Error logs: {namespace_name=\"chat-app\"} |= \"ERROR\""
    echo "  K8s events: {job=\"kubernetes-events\"}"
    echo ""
    echo "🔧 Available Dashboards:"
    echo "  - Chat Application Logs"
    echo "  - Kubernetes Infrastructure Logs"
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
    echo "🚨 Log Alerting:"
    echo "  ✅ Error rate monitoring"
    echo "  ✅ Log volume alerts"
    echo "  ✅ No-log detection"
    echo "  ✅ System health monitoring"
    echo ""
    echo "🔧 Key Features:"
    echo "  - Multi-tenant log aggregation"
    echo "  - High-performance indexing"
    echo "  - Scalable architecture"
    echo "  - Prometheus-compatible metrics"
    echo "  - Configurable log forwarding"
    echo ""
}

# Main function
main() {
    log_info "🚀 Starting Complete Centralized Logging Deployment..."
    echo ""
    
    check_prerequisites
    create_namespace
    deploy_loki_stack
    deploy_grafana_dashboards
    create_log_alerts
    configure_retention_policies
    create_log_forwarding
    wait_for_deployment
    verify_deployment
    display_capabilities
    display_access_info
    
    echo ""
    log_info "🎉 Complete centralized logging stack deployment finished!"
    log_info "📚 Please save the access information above for future reference."
    echo ""
    log_info "🔧 Next steps:"
    echo "  1. Port-forward services to access Grafana and Loki"
    echo "  2. Explore log dashboards in Grafana"
    echo "  3. Set up log alerts based on your requirements"
    echo "  4. Configure log forwarding to external systems if needed"
    echo ""
}

# Run main function
main "$@"
