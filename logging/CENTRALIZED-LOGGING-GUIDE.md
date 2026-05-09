# Centralized Logging Architecture Guide

## 📋 Overview

This guide provides comprehensive documentation for the centralized logging solution implemented for the Chat Application using Loki, Promtail, and Grafana.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Chat Application                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │   Frontend  │  │   Backend   │  │  MongoDB    │           │
│  │   (React)   │  │  (Node.js)  │  │ Database    │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
│         │               │               │                     │
│         └───────────────┼───────────────┘                     │
│                         │                                     │
│              ┌─────────────────────────────────┐                │
│              │      Container Logs          │                │
│              │   (stdout/stderr)           │                │
│              └─────────────────────────────────┘                │
└─────────────────────────┼─────────────────────────────────────┘
                          │
┌─────────────────────────┼─────────────────────────────────────┐
│                 Logging Stack                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │   Promtail  │  │    Loki     │  │   Grafana   │           │
│  │ (Collector) │  │ (Aggregator)│  │(Visualization)│         │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
│         │               │               │                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │Systemd Logs │  │K8s Events  │  │Log Alerts  │           │
│  │             │  │             │  │             │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Deploy Complete Logging Stack

```bash
cd logging
chmod +x deploy-all-logging.sh
./deploy-all-logging.sh
```

### 2. Access Services

**Loki:**
```bash
kubectl port-forward svc/logging-loki -n logging 3100:3100
# URL: http://localhost:3100
# Health check: curl http://localhost:3100/ready
```

**Grafana (with Loki integration):**
```bash
kubectl port-forward svc/logging-grafana -n logging 3000:80
# URL: http://localhost:3000
# Username: admin, Password: admin123
```

## 📊 Logging Components

### 1. Loki Configuration

**File:** `loki-stack-values.yaml`

**Key Features:**
- 30-day log retention with configurable policies
- High-performance indexing with boltdb-shipper
- Efficient log compression and storage
- Multi-tenant architecture
- Configurable ingestion limits

**Resource Requirements:**
- Loki: 2CPU, 4GB RAM, 50GB storage
- Promtail: 500m CPU, 512MB RAM (DaemonSet)
- Grafana: 1CPU, 2GB RAM (if deployed separately)

**Storage Configuration:**
```yaml
persistence:
  enabled: true
  storageClassName: standard
  accessModes: ["ReadWriteOnce"]
  size: 50Gi
```

### 2. Promtail Configuration

**Log Sources:**
- **Container logs:** All container stdout/stderr
- **Systemd logs:** System service logs
- **Kubernetes API server:** Control plane logs
- **Kubernetes events:** Cluster events

**Log Processing Pipeline:**
```yaml
pipeline_stages:
- json:
    expressions:
      output: log
      stream: stream
      attrs:
- regex:
    source: tag
    expression: '^(?P<namespace_name>[^_]+)_(?P<pod_name>[^_]+)_(?P<container_name>.+)$'
- timestamp:
    source: time
    format: RFC3339Nano
- labels:
    stream:
    namespace_name:
    pod_name:
    container_name:
```

### 3. Grafana Integration

**Loki Datasource Configuration:**
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
      isDefault: false
      editable: true
      jsonData:
        maxLines: 1000
        derivedFields:
        - datasourceUid: prometheus
          matcherRegex: ".*\"trace_id\":\"(\\w+)\".*"
          name: TraceID
          url: "$${__value.raw}"
```

## 📈 Log Queries and Dashboards

### Available Dashboards

#### Chat Application Logs
- **File:** `grafana-dashboards/chat-app-logs.json`
- **Panels:**
  - Backend Error Logs
  - Frontend Error Logs
  - Error Rate Over Time
  - Kubernetes Events (Warnings & Errors)
  - Failed HTTP Requests (5xx Errors)
  - Database Connection Issues
  - WebSocket Connection Issues
  - Authentication Events
  - Message Activity

#### Kubernetes Infrastructure Logs
- **File:** `grafana-dashboards/kubernetes-infrastructure-logs.json`
- **Panels:**
  - Kubernetes Events (Critical)
  - Kubernetes Events Rate
  - Kubernetes API Server Errors
  - Systemd Service Failures
  - Monitoring Stack Issues
  - Kubernetes System Issues
  - Container Issues Rate
  - Infrastructure Errors Rate
  - Container Runtime Errors

### LogQL Query Examples

#### Basic Log Queries
```logql
# All logs from chat-app namespace
{namespace_name="chat-app"}

# Error logs from backend
{namespace_name="chat-app", container_name="chat-app-backend"} |= "ERROR"

# HTTP 5xx errors
{namespace_name="chat-app"} |= "status" |= "500"

# Database connection issues
{namespace_name="chat-app"} |= "database" |= "error"
```

#### Advanced Log Queries
```logql
# Error rate over time
sum(rate({namespace_name="chat-app", container_name="chat-app-backend"} |= "ERROR" [5m])) by (pod_name)

# Top error messages
topk(10, sum(count_over_time({namespace_name="chat-app"} |= "ERROR" [1h])) by (log))

# Log volume by container
sum(rate({namespace_name="chat-app"}[5m])) by (container_name)

# Failed HTTP requests with status codes
{namespace_name="chat-app"} |~ "status.*[5-9][0-9][0-9]"
```

#### Kubernetes Event Queries
```logql
# Warnings and errors
{job="kubernetes-events"} |~ "Warning|Error|Failed"

# Pod restart events
{job="kubernetes-events"} |~ "Restarted|CrashLoopBackOff|OOMKilled"

# Image pull issues
{job="kubernetes-events"} |~ "ImagePullBackOff|ErrImagePull"
```

## 🗄️ Log Retention Configuration

### Retention Policies

**Default Configuration:**
```yaml
limits_config:
  retention_period: 30d
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32
  per_stream_rate_limit: 16MB
  per_stream_rate_limit_burst: 32MB
```

**Custom Retention by Label:**
```yaml
limits_config:
  retention_period: 30d
  stream_retention:
    - selector: '{namespace_name="kube-system"}'
      period: 7d
    - selector: '{namespace_name="monitoring"}'
      period: 14d
    - selector: '{namespace_name="chat-app"}'
      period: 30d
```

### Storage Management

**Index Configuration:**
```yaml
schema_config:
  configs:
  - from: 2020-10-24
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h
```

**Compaction Settings:**
```yaml
compactor:
  retention_enabled: true
  delete_request_cancel_period: 24h
  retention_delete_delay: 2h
```

## 🚨 Log Alerting

### Alert Rules

**File:** `alerting-rules.yaml`

**Available Alerts:**

#### Application Alerts
- **ChatAppHighErrorLogs:** High error log rate (>10 lines/sec)
- **ChatAppNoLogs:** No logs detected for 5 minutes
- **DatabaseConnectionErrors:** Database connection failures
- **WebSocketConnectionErrors:** WebSocket connection issues

#### Infrastructure Alerts
- **LokiHighIngestionRate:** High log ingestion rate (>10k samples/sec)
- **LokiHighMemoryUsage:** Loki memory usage >80%
- **ContainerRuntimeErrors:** Container runtime failures
- **KubernetesSystemErrors:** Kubernetes system errors

### Alert Configuration

**Example Alert Rule:**
```yaml
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
```

## 🔧 Configuration Files

| File | Purpose | Key Settings |
|------|---------|--------------|
| `loki-stack-values.yaml` | Helm values for Loki stack | Resource limits, retention, storage |
| `deploy-loki-stack.sh` | Loki stack deployment script | Automated setup and verification |
| `deploy-all-logging.sh` | Complete logging deployment | All components integration |
| `grafana-dashboards/` | Pre-built dashboards | Application and infrastructure views |
| `alerting-rules.yaml` | Log alert definitions | Thresholds, severity levels |

## 📱 Log Collection Patterns

### Structured Logging

**Backend Application Logs:**
```json
{
  "timestamp": "2024-03-17T12:00:00.000Z",
  "level": "info",
  "message": "User login successful",
  "userId": "123",
  "action": "login",
  "service": "chat-app-backend",
  "requestId": "req-abc123",
  "duration": "150ms"
}
```

**Frontend Application Logs:**
```json
{
  "timestamp": "2024-03-17T12:00:00.000Z",
  "level": "error",
  "message": "API request failed",
  "error": "NetworkError",
  "url": "/api/messages",
  "service": "chat-app-frontend",
  "userId": "123"
}
```

### Log Labels

**Automatic Labels:**
- `namespace_name`: Kubernetes namespace
- `pod_name`: Pod name
- `container_name`: Container name
- `stream`: Log stream (stdout/stderr)
- `job`: Promtail job name

**Custom Labels:**
- `service`: Application service name
- `level`: Log level (info, warn, error)
- `action`: Business action (login, message, etc.)
- `userId`: User identifier

## 🛠️ Troubleshooting

### Common Issues

#### 1. Logs Not Appearing
**Symptoms:** No logs in Grafana/Loki
**Causes:** Promtail configuration, pod labels, permissions
**Solutions:**
```bash
# Check Promtail status
kubectl get pods -n logging -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n logging -l app.kubernetes.io/name=promtail

# Verify log paths
kubectl exec -it promtail-pod -- ls /var/log/containers/
```

#### 2. High Memory Usage in Loki
**Symptoms:** Loki OOM kills, performance issues
**Causes:** High log volume, insufficient limits
**Solutions:**
- Increase memory limits in values.yaml
- Review retention policies
- Check for high-cardinality labels
- Monitor ingestion rates

#### 3. Slow Log Queries
**Symptoms:** Queries taking too long
**Causes:** Large time ranges, complex queries
**Solutions:**
- Use specific time ranges
- Add more specific label filters
- Consider query optimization
- Check Loki performance metrics

#### 4. Log Parsing Issues
**Symptoms:** Incorrect labels, missing fields
**Causes:** Pipeline configuration, log format
**Solutions:**
```bash
# Test Promtail configuration
kubectl exec -it promtail-pod -- promtail --config.file=/etc/promtail/config.yml --dry-run

# Check log format
kubectl logs chat-app-backend-pod | head -10
```

### Debug Commands

```bash
# Check all logging components
kubectl get all -n logging

# Check Loki health
kubectl port-forward svc/logging-loki -n logging 3100:3100
curl http://localhost:3100/ready

# Check Promtail targets
kubectl logs -n logging -l app.kubernetes.io/name=promtail | grep "targets"

# Query Loki directly
curl -G -s 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace_name="chat-app"}'

# Check log ingestion metrics
curl http://localhost:3100/metrics | grep loki_distributor
```

## 📚 Advanced Features

### Log Forwarding

**External Systems Integration:**
```yaml
# Forward to Elasticsearch
elasticsearch:
  enabled: true
  hosts: ["elasticsearch:9200"]
  index: "chat-app-logs"
  username: "elastic"
  password: "changeme"

# Forward to Splunk
splunk:
  enabled: true
  host: "splunk.example.com"
  port: 8088
  token: "your-splunk-hec-token"
  index: "chat_app"
```

### Log Transformation

**Advanced Pipeline Stages:**
```yaml
pipeline_stages:
- json:
  expressions:
    level: level
    message: message
    timestamp: time
- regex:
  expression: '(?P<ip>\d+\.\d+\.\d+\.\d+)'
- template:
  source: message
  template: '{{.ip}} - {{.message}}'
- output:
  source: output
```

### Multi-Tenant Configuration

**Tenant Isolation:**
```yaml
auth_enabled: true
auth_type: jwt

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

ingester:
  lifecycler:
    ring:
      kvstore:
        store: consul
```

## 🔄 Maintenance

### Regular Tasks

1. **Daily:**
   - Monitor log ingestion rates
   - Check alert effectiveness
   - Review error patterns

2. **Weekly:**
   - Review storage usage
   - Update dashboards as needed
   - Analyze log patterns

3. **Monthly:**
   - Update retention policies
   - Review performance metrics
   - Backup critical configurations

### Backup and Recovery

```bash
# Backup Loki data
kubectl exec -it deployment/logging-loki -- tar czf /tmp/loki-backup.tar.gz /loki

# Backup configuration
kubectl get configmaps -n logging -o yaml > logging-config-backup.yaml

# Restore procedure documented in troubleshooting section
```

## 🎯 Best Practices

### 1. Log Design
- Use structured JSON logging
- Include relevant context (requestId, userId)
- Use consistent log levels
- Avoid sensitive information in logs

### 2. Performance
- Monitor ingestion rates
- Use appropriate retention periods
- Optimize label cardinality
- Regular maintenance of storage

### 3. Security
- Enable authentication for Loki
- Use network policies
- Regular security updates
- Audit log access patterns

### 4. Monitoring
- Set up log-based alerts
- Monitor Loki performance metrics
- Track storage usage
- Regular dashboard reviews

---

## 🎯 Conclusion

This centralized logging solution provides comprehensive log collection, storage, and analysis capabilities for your Chat Application. The combination of Loki, Promtail, and Grafana offers:

- **Complete log visibility** across all application components
- **Efficient log storage** with configurable retention
- **Powerful query capabilities** with LogQL
- **Rich visualizations** in Grafana dashboards
- **Proactive alerting** on log patterns
- **Scalable architecture** for enterprise workloads

For questions or support, refer to the troubleshooting section or consult the additional resources provided.
