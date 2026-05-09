# Enterprise-Grade Kubernetes Monitoring Guide

## 📋 Overview

This guide provides comprehensive documentation for the enterprise-grade Kubernetes monitoring solution implemented for the Chat Application using Prometheus, Grafana, and AlertManager.

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
└─────────────────────────┼─────────────────────────────────────┘
                          │
┌─────────────────────────┼─────────────────────────────────────┐
│                 Monitoring Stack                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ Prometheus   │  │   Grafana   │  │AlertManager │           │
│  │  (Metrics)  │  │(Dashboards) │  │ (Alerting)  │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
│         │               │               │                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │Node Exporter│  │kube-state   │  │ServiceMon   │           │
│  │ (Node Met)  │  │Metrics      │  │ (App Met)   │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Deploy Complete Monitoring Stack

```bash
cd monitoring
chmod +x deploy-all-monitoring.sh
./deploy-all-monitoring.sh
```

### 2. Access Services

**Grafana:**
```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# URL: http://localhost:3000
# Username: admin, Password: admin123
```

**Prometheus:**
```bash
kubectl port-forward svc/monitoring-prometheus -n monitoring 9090:9090
# URL: http://localhost:9090
```

**AlertManager:**
```bash
kubectl port-forward svc/monitoring-alertmanager -n monitoring 9093:9093
# URL: http://localhost:9093
```

## 📊 Monitoring Components

### 1. Prometheus Configuration

**File:** `kube-prometheus-stack-values.yaml`

**Key Features:**
- 15-day data retention with 50GB storage
- High resource allocation (4CPU, 8GB RAM)
- Comprehensive service discovery
- External labels for cluster identification
- Remote write support for long-term storage

**Resource Requirements:**
- Prometheus: 4CPU, 8GB RAM, 50GB storage
- Grafana: 1CPU, 2GB RAM, 10GB storage
- AlertManager: 1CPU, 2GB RAM, 10GB storage

### 2. ServiceMonitors

**File:** `backend-servicemonitor.yaml`

**Monitored Services:**
- Chat Application Backend (port 3000)
- Chat Application Frontend (if metrics enabled)
- MongoDB (if metrics exporter deployed)
- Kubernetes components

**Metrics Collected:**
- HTTP requests and response times
- WebSocket connections
- Database connections
- Application-specific metrics
- Container resource usage

### 3. Grafana Dashboards

**Available Dashboards:**

#### Chat Application Overview
- **File:** `grafana-dashboards/chat-app-overview.json`
- **Panels:**
  - API Request Rate (by method and status)
  - Request Latency (50th, 95th percentile)
  - CPU Usage (by pod)
  - Memory Usage (by pod)
  - Pod Restarts
  - Chat Activity (messages, WebSocket connections)
  - Key Statistics (request rate, latency, error rate, connections)

#### Kubernetes Infrastructure
- **File:** `grafana-dashboards/kubernetes-infrastructure.json`
- **Panels:**
  - Node CPU, Memory, Disk Usage
  - Network Traffic
  - Pod Restarts by Namespace
  - Pod Count by Namespace
  - Cluster-wide Statistics

### 4. Alerting Rules

**File:** `alerting-rules.yaml`

**Alert Categories:**

#### Application Alerts
- **High CPU Usage:** Warning at 80%, Critical at 95%
- **High Memory Usage:** Warning at 80%, Critical at 95%
- **High Latency:** Warning at 1s, Critical at 2s (95th percentile)
- **High Error Rate:** Warning at 10%, Critical at 20%
- **No Requests:** Alert when no traffic for 2 minutes

#### Infrastructure Alerts
- **Pod Failures:** Restarts, crash loops, not ready
- **Container Crashes:** Error termination, OOM kills
- **Node Issues:** High CPU, memory, disk usage
- **Kubernetes API:** Server down, high latency

#### Business Logic Alerts
- **WebSocket Connections:** Alert when > 1000 connections
- **Database Connections:** Alert when > 80 connections

## 📈 Metrics Reference

### Application Metrics

#### HTTP Metrics
```promql
# Request rate by method and status
sum(rate(chat_app_http_requests_total[5m])) by (method, status)

# Request latency percentiles
histogram_quantile(0.95, sum(rate(chat_app_http_request_duration_seconds_bucket[5m])) by (le, method, path))
histogram_quantile(0.50, sum(rate(chat_app_http_request_duration_seconds_bucket[5m])) by (le, method, path))

# Error rate
sum(rate(chat_app_http_requests_total{status=~"5.."}[5m])) / sum(rate(chat_app_http_requests_total[5m]))
```

#### WebSocket Metrics
```promql
# Active connections
sum(chat_app_websocket_active_connections)

# Message throughput
sum(rate(chat_app_messages_total[5m])) by (direction)
```

#### Database Metrics
```promql
# Active connections
sum(chat_app_database_connections_active)

# User activity
sum(rate(chat_app_user_registrations_total[5m]))
sum(rate(chat_app_user_logins_total[5m]))
```

### Infrastructure Metrics

#### Container Resources
```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{pod=~"chat-app.*"}[5m])) by (pod)

# Memory usage by pod
sum(container_memory_working_set_bytes{pod=~"chat-app.*"}) by (pod)

# Pod restarts
sum(rate(kube_pod_container_status_restarts_total{pod=~"chat-app.*"}[5m])) by (pod)
```

#### Node Resources
```promql
# Node CPU usage
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (node) / sum(machine_cpu_cores) by (node)

# Node memory usage
sum(container_memory_working_set_bytes{container!=""}) by (node) / sum(machine_memory_bytes) by (node)

# Node disk usage
(sum(node_filesystem_size_bytes{fstype!="tmpfs"}) by (node) - sum(node_filesystem_avail_bytes{fstype!="tmpfs"}) by (node)) / sum(node_filesystem_size_bytes{fstype!="tmpfs"}) by (node)
```

## 🚨 Alert Management

### Alert Severity Levels

1. **Critical:** Immediate action required
   - Service down
   - Critical resource exhaustion (>95%)
   - Container crashes
   - High error rates (>20%)

2. **Warning:** Attention required
   - High resource usage (>80%)
   - Elevated error rates (>10%)
   - Performance degradation

### Alert Configuration

**AlertManager Configuration** (in `kube-prometheus-stack-values.yaml`):
```yaml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: 'critical-alerts'
  - match:
      severity: warning
    receiver: 'warning-alerts'
```

### Setting Up Notification Channels

1. **Email Notifications:**
   ```yaml
   global:
     smtp_smarthost: 'smtp.example.com:587'
     smtp_from: 'alerts@example.com'
   ```

2. **Slack Integration:**
   ```yaml
   receivers:
   - name: 'slack-notifications'
     slack_configs:
     - api_url: 'YOUR_SLACK_WEBHOOK_URL'
       channel: '#alerts'
       title: 'Chat App Alert'
   ```

3. **PagerDuty Integration:**
   ```yaml
   receivers:
   - name: 'pagerduty-notifications'
     pagerduty_configs:
     - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
   ```

## 🔧 Configuration Files

| File | Purpose | Key Settings |
|------|---------|--------------|
| `kube-prometheus-stack-values.yaml` | Helm values for Prometheus stack | Resource limits, retention, storage |
| `backend-servicemonitor.yaml` | Service discovery for metrics | Scrape intervals, metric relabeling |
| `alerting-rules.yaml` | Alert definitions | Thresholds, severity levels |
| `grafana-dashboards/` | Pre-built dashboards | Application and infrastructure views |
| `deploy-all-monitoring.sh` | Deployment script | Automated setup and verification |

## 📱 Best Practices

### 1. Performance Optimization
- Use recording rules for complex queries
- Set appropriate scrape intervals (30s for most metrics)
- Configure proper retention periods based on storage capacity
- Use metric relabeling to reduce cardinality

### 2. Alert Management
- Set meaningful thresholds based on baselines
- Use runbooks for consistent response procedures
- Implement escalation policies for critical alerts
- Regularly review and tune alert rules

### 3. Dashboard Design
- Include both overview and detailed views
- Use consistent color schemes and units
- Add annotations for deployments and incidents
- Create separate dashboards for different audiences

### 4. Security
- Enable authentication for Grafana and Prometheus
- Use network policies to restrict access
- Regularly update monitoring components
- Implement audit logging

## 🛠️ Troubleshooting

### Common Issues

#### 1. Metrics Not Appearing
**Symptoms:** No data in Grafana dashboards
**Causes:** ServiceMonitor configuration, pod labels
**Solutions:**
```bash
# Check ServiceMonitor status
kubectl get servicemonitors -n monitoring

# Check Prometheus targets
kubectl port-forward svc/monitoring-prometheus -n monitoring 9090:9090
# Visit: http://localhost:9090/targets

# Verify pod labels
kubectl get pods --show-labels
```

#### 2. High Memory Usage in Prometheus
**Symptoms:** Prometheus OOM kills
**Causes:** High cardinality metrics, insufficient limits
**Solutions:**
- Increase memory limits in values.yaml
- Review metric relabeling rules
- Check for high-cardinality labels

#### 3. Alerts Not Firing
**Symptoms:** Expected alerts not triggered
**Causes:** Incorrect rule syntax, wrong thresholds
**Solutions:**
```bash
# Check rule syntax
kubectl get prometheusrules -n monitoring -o yaml

# Test queries in Prometheus
kubectl port-forward svc/monitoring-prometheus -n monitoring 9090:9090
# Test alert expressions in the UI
```

#### 4. Grafana Dashboard Issues
**Symptoms:** Dashboards not loading, data source errors
**Causes:** ConfigMap issues, data source configuration
**Solutions:**
```bash
# Check dashboard ConfigMaps
kubectl get configmaps -n monitoring | grep grafana

# Verify data source configuration
kubectl get datasources -n monitoring -o yaml
```

### Debug Commands

```bash
# Check all monitoring components
kubectl get all -n monitoring

# Check pod logs
kubectl logs -n monitoring deployment/monitoring-prometheus
kubectl logs -n monitoring deployment/monitoring-grafana
kubectl logs -n monitoring deployment/monitoring-alertmanager

# Check resource usage
kubectl top pods -n monitoring
kubectl top nodes

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

## 📚 Additional Resources

### Documentation
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Monitoring](https://kubernetes.io/docs/tasks/debug-application-cluster/resource-usage-monitoring/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

### Community
- [Prometheus Users Mailing List](https://groups.google.com/group/prometheus-users)
- [Grafana Community](https://community.grafana.com/)
- [Kubernetes Slack](https://kubernetes.slack.com/)

### Tools and Utilities
- [PromLens](https://promlens.com/) - PromQL query builder
- [Grafana Tanka](https://grafana.com/docs/grafana/latest/features-datasources/tanka/) - Jsonnet as a DSL
- [Cortex](https://cortexmetrics.io/) - Long-term Prometheus storage

## 🔄 Maintenance

### Regular Tasks

1. **Weekly:**
   - Review alert effectiveness
   - Check storage usage
   - Update dashboards as needed

2. **Monthly:**
   - Update monitoring components
   - Review performance baselines
   - Audit metric cardinality

3. **Quarterly:**
   - Review retention policies
   - Capacity planning
   - Security audit

### Backup and Recovery

```bash
# Backup Prometheus data
kubectl exec -n monitoring deployment/monitoring-prometheus -- tar czf /tmp/prometheus-backup.tar.gz /prometheus

# Backup Grafana dashboards
kubectl get configmaps -n monitoring -l grafana_dashboard=1 -o yaml > grafana-dashboards-backup.yaml

# Restore procedure documented in troubleshooting section
```

---

## 🎯 Conclusion

This enterprise-grade monitoring solution provides comprehensive visibility into your Chat Application's performance, reliability, and user experience. The combination of Prometheus, Grafana, and AlertManager offers:

- **Complete observability** across application and infrastructure layers
- **Proactive alerting** to prevent issues before they impact users
- **Rich visualizations** for quick understanding of system health
- **Scalable architecture** that grows with your application

For questions or support, refer to the troubleshooting section or consult the additional resources provided.
