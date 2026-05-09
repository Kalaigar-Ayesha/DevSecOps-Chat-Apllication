#!/bin/bash

# Distributed Tracing Deployment Script
# Deploys Jaeger and OpenTelemetry Collector for MERN application

set -e

# Configuration
NAMESPACE="tracing"
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

# Deploy Jaeger stack
deploy_jaeger() {
    log_step "Deploying Jaeger distributed tracing stack..."
    
    if [ -f "$SCRIPT_DIR/jaeger-deployment.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/jaeger-deployment.yaml"
        log_info "Jaeger stack deployed successfully"
    else
        log_error "jaeger-deployment.yaml not found"
        exit 1
    fi
}

# Configure RBAC for tracing
configure_rbac() {
    log_step "Configuring RBAC for tracing components..."
    
    # Create ServiceAccount with proper permissions
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jaeger
  namespace: $NAMESPACE
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: otel-collector
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jaeger-role
rules:
- apiGroups: [""]
  resources:
  - pods
  - nodes
  - services
  - endpoints
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
  - replicasets
  - deployments
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jaeger-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jaeger-role
subjects:
- kind: ServiceAccount
  name: jaeger
  namespace: $NAMESPACE
- kind: ServiceAccount
  name: otel-collector
  namespace: $NAMESPACE
EOF
    
    log_info "RBAC configuration completed"
}

# Configure service mesh integration
configure_service_mesh() {
    log_step "Configuring service mesh integration..."
    
    # Create ConfigMap for OpenTelemetry configuration
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: tracing-config
  namespace: $NAMESPACE
data:
  jaeger-config.yaml: |
    # Jaeger Collector Configuration
    collector:
      zipkin:
        host-port: 0.0.0.0:9411
      otlp:
        grpc:
          host-port: 0.0.0.0:14250
        http:
          host-port: 0.0.0.0:14268
    
    query:
      base-path: /
      
    storage:
      type: memory
      
  otel-config.yaml: |
    # OpenTelemetry Collector Configuration
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    
    processors:
      batch:
        timeout: 1s
        send_batch_size: 1024
      memory_limiter:
        limit_mib: 512
      resource:
        attributes:
        - key: environment
          value: production
          action: upsert
        - key: service.name
          value: chat-app-backend
          action: upsert
    
    exporters:
      jaeger:
        endpoint: jaeger-collector:14250
        tls:
          insecure: true
      prometheus:
        endpoint: "0.0.0.0:8889"
        namespace: "otel"
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch, resource]
          exporters: [jaeger]
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [prometheus]
EOF
    
    log_info "Service mesh configuration created"
}

# Create tracing alerts
create_tracing_alerts() {
    log_step "Creating tracing alerts..."
    
    # Create PrometheusRule for tracing alerts
    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: jaeger-tracing-alerts
  namespace: monitoring
  labels:
    app: jaeger
    release: monitoring
spec:
  groups:
  - name: jaeger.rules
    rules:
    - alert: JaegerHighQueryLatency
      expr: histogram_quantile(0.95, sum(rate(jaeger_query_latency_bucket[5m])) by (le)) > 1
      for: 2m
      labels:
        severity: warning
        service: jaeger
        component: tracing
      annotations:
        summary: "High query latency detected in Jaeger"
        description: "95th percentile query latency is {{ $value }}s"
        
    - alert: JaegerQueryErrors
      expr: sum(rate(jaeger_query_errors_total[5m])) > 0.1
      for: 1m
      labels:
        severity: critical
        service: jaeger
        component: tracing
      annotations:
        summary: "Query errors detected in Jaeger"
        description: "Query error rate is {{ $value }} errors/second"
        
    - alert: JaegerNoTraces
      expr: sum(rate(jaeger_traces_created_total[5m])) == 0
      for: 5m
      labels:
        severity: warning
        service: jaeger
        component: tracing
      annotations:
        summary: "No traces detected in Jaeger"
        description: "No traces have been received for the last 5 minutes"
        
    - alert: JaegerHighMemoryUsage
      expr: sum(jaeger_storage_memory_usage_bytes{type="memory"}) / (1024*1024*1024) > 1
      for: 5m
      labels:
        severity: warning
        service: jaeger
        component: tracing
      annotations:
        summary: "High memory usage in Jaeger"
        description: "Jaeger memory usage is {{ $value | humanize1024 }}GB"
EOF
    
    log_info "Tracing alerts created successfully"
}

# Wait for deployment to be ready
wait_for_deployment() {
    log_step "Waiting for tracing stack to be ready..."
    
    # Wait for Jaeger
    log_info "Waiting for Jaeger..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app=jaeger \
        --timeout=300s
    
    # Wait for OpenTelemetry Collector
    log_info "Waiting for OpenTelemetry Collector..."
    kubectl wait --for=condition=ready pod \
        --namespace $NAMESPACE \
        --selector=app=otel-collector \
        --timeout=300s
    
    log_info "All tracing components are ready"
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
    
    # Check ConfigMaps
    log_info "Checking ConfigMaps..."
    kubectl get configmaps -n $NAMESPACE
    
    log_info "Deployment verification completed"
}

# Display access information
display_access_info() {
    log_step "Displaying access information..."
    
    echo ""
    echo "=== 🔍 Distributed Tracing Stack Access ==="
    echo ""
    echo "🌐 Jaeger UI:"
    echo "  kubectl port-forward svc/jaeger-ui -n $NAMESPACE 16686:16686"
    echo "  URL: http://localhost:16686"
    echo ""
    echo "📊 Jaeger Collector:"
    echo "  kubectl port-forward svc/jaeger-collector -n $NAMESPACE 14268:14268"
    echo "  URL: http://localhost:14268"
    echo ""
    echo "📡 OpenTelemetry Collector:"
    echo "  kubectl port-forward svc/otel-collector -n $NAMESPACE 4317:4317"
    echo "  gRPC endpoint: localhost:4317"
    echo ""
    echo "📈 OpenTelemetry Metrics:"
    echo "  kubectl port-forward svc/otel-collector -n $NAMESPACE 8889:8889"
    echo "  URL: http://localhost:8889/metrics"
    echo ""
    echo "🔧 Configuration Files:"
    echo "  - Jaeger deployment: $SCRIPT_DIR/jaeger-deployment.yaml"
    echo "  - Backend tracing: $SCRIPT_DIR/../backend/src/tracing/tracer.js"
    echo "  - Instrumented app: $SCRIPT_DIR/../backend/src/tracing/instrumented-app.js"
    echo ""
}

# Display tracing capabilities
display_capabilities() {
    log_step "Displaying tracing capabilities..."
    
    echo ""
    echo "=== 🔍 Distributed Tracing Capabilities ==="
    echo ""
    echo "📊 Trace Collection:"
    echo "  ✅ HTTP request tracing"
    echo "  ✅ MongoDB operation tracing"
    echo "  ✅ WebSocket connection tracing"
    echo "  ✅ External API call tracing"
    echo "  ✅ Custom span instrumentation"
    echo ""
    echo "📈 Visualization:"
    echo "  ✅ Jaeger UI for trace exploration"
    echo "  ✅ Service dependency graphs"
    echo "  ✅ Performance analysis"
    echo "  ✅ Error tracking and debugging"
    echo ""
    echo "🔧 Integration:"
    echo "  ✅ OpenTelemetry standards"
    echo "  ✅ Prometheus metrics integration"
    echo "  ✅ Grafana dashboard support"
    echo "  ✅ Alert management"
    echo ""
    echo "📊 Key Features:"
    echo "  - Automatic instrumentation for Express.js"
    echo "  - MongoDB query tracing"
    echo "  - WebSocket event tracing"
    echo "  - Distributed context propagation"
    echo "  - Custom span creation"
    echo "  - Performance monitoring"
    echo ""
}

# Main function
main() {
    log_info "🚀 Starting Distributed Tracing Stack Deployment..."
    echo ""
    
    check_prerequisites
    create_namespace
    configure_rbac
    configure_service_mesh
    deploy_jaeger
    create_tracing_alerts
    wait_for_deployment
    verify_deployment
    display_capabilities
    display_access_info
    
    echo ""
    log_info "🎉 Distributed tracing stack deployment completed successfully!"
    log_info "📚 Please save the access information above for future reference."
    echo ""
    log_info "🔧 Next steps:"
    echo "  1. Port-forward services to access Jaeger UI"
    echo "  2. Update backend application to use tracing"
    echo "  3. Configure OpenTelemetry environment variables"
    echo "  4. Set up tracing alerts based on your requirements"
    echo ""
}

# Run main function
main "$@"
