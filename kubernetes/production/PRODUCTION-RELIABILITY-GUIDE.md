# Production-Grade Kubernetes Reliability Guide

## 📋 Overview

This guide provides comprehensive documentation for implementing production-grade reliability and scalability best practices for the MERN Chat Application.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Production Kubernetes Cluster                │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │   Frontend  │  │   Backend   │  │  MongoDB    │           │
│  │ (React App) │  │ (Node.js)   │  │ (StatefulSet)│           │
│  │   HPA Ready │  │  HPA Ready  │  │  3 Replicas  │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
│         │               │               │                     │
│         └───────────────┼───────────────┘                     │
│                         │                                     │
│              ┌─────────────────────────────────┐                │
│              │    Ingress Controller        │                │
│              │  (TLS + Rate Limiting)     │                │
│              └─────────────────────────────────┘                │
│                         │                                     │
└─────────────────────────┼─────────────────────────────────────┘
                          │
┌─────────────────────────┼─────────────────────────────────────┐
│                 Monitoring & Observability                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ Prometheus  │  │   Jaeger    │  │   Grafana   │           │
│  │ (Metrics)   │  │ (Tracing)   │  │(Dashboards) │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Deploy Production Stack

```bash
cd kubernetes/production
kubectl apply -f .
```

### 2. Verify Deployment

```bash
# Check all components
kubectl get all -n chat-app

# Check pod status
kubectl get pods -n chat-app -w

# Check HPA status
kubectl get hpa -n chat-app

# Check ingress status
kubectl get ingress -n chat-app
```

## 🔧 Health Probes

### 1. Probe Types

#### Liveness Probe
**Purpose:** Detect if container is still running
**Configuration:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
    scheme: HTTP
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3
```

#### Readiness Probe
**Purpose:** Determine if container is ready to serve traffic
**Configuration:**
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: http
    scheme: HTTP
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3
```

#### Startup Probe
**Purpose:** Check if container has started successfully
**Configuration:**
```yaml
startupProbe:
  httpGet:
    path: /health
    port: http
    scheme: HTTP
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 30
```

### 2. Health Endpoints

#### Backend Health Endpoints
```javascript
// /health endpoint
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    const dbStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
    
    // Check external dependencies
    const externalServices = await checkExternalServices();
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      database: dbStatus,
      external_services: externalServices,
      uptime: process.uptime(),
      version: process.env.npm_package_version
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

// /ready endpoint
app.get('/ready', async (req, res) => {
  try {
    // Check if all dependencies are ready
    const dbReady = mongoose.connection.readyState === 1;
    const cacheReady = await checkCacheConnection();
    const servicesReady = await checkServiceHealth();
    
    const isReady = dbReady && cacheReady && servicesReady;
    
    res.status(isReady ? 200 : 503).json({
      ready: isReady,
      checks: {
        database: dbReady,
        cache: cacheReady,
        services: servicesReady
      }
    });
  } catch (error) {
    res.status(503).json({
      ready: false,
      error: error.message
    });
  }
});
```

#### Frontend Health Endpoint
```javascript
// Frontend health check
const HealthCheck = () => {
  const [health, setHealth] = useState({
    status: 'loading',
    checks: {}
  });

  useEffect(() => {
    const performHealthCheck = async () => {
      try {
        // Check API connectivity
        const apiResponse = await fetch('/api/health');
        const apiStatus = apiResponse.ok;
        
        // Check WebSocket connectivity
        const wsStatus = checkWebSocketConnection();
        
        setHealth({
          status: apiStatus && wsStatus ? 'healthy' : 'unhealthy',
          checks: {
            api: apiStatus,
            websocket: wsStatus
          },
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        setHealth({
          status: 'unhealthy',
          error: error.message
        });
      }
    };

    performHealthCheck();
    const interval = setInterval(performHealthCheck, 30000);
    return () => clearInterval(interval);
  }, []);

  return health.status === 'healthy' ? children : <ErrorPage />;
};
```

## 📈 Horizontal Pod Autoscaling

### 1. HPA Configuration

#### Backend HPA
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: chat-app-backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: chat-app-backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

#### HPA Behavior Configuration
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
    - type: Percent
      value: 10
      periodSeconds: 60
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
    - type: Percent
      value: 50
      periodSeconds: 60
    selectPolicy: Max
```

### 2. Scaling Metrics

#### Key Metrics to Monitor
- **CPU Utilization:** Target 70%
- **Memory Utilization:** Target 80%
- **Request Rate:** Scale based on RPS
- **Response Time:** Scale if p95 > 1s
- **Error Rate:** Scale if error rate > 5%

#### Custom Metrics Scaling
```yaml
# Custom metrics for HPA (requires Metrics Server)
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-hpa-metrics
data:
  metrics.yaml: |
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: 100
    - type: Pods
      pods:
        metric:
          name: response_time_p95
        target:
          type: AverageValue
          averageValue: 1000
```

## 🔄 Resource Management

### 1. Resource Requests and Limits

#### Backend Resources
```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

#### Frontend Resources
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

#### MongoDB Resources
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### 2. Resource Optimization

#### CPU Optimization
- **Requests:** Set to 50% of typical usage
- **Limits:** Set to 2x requests for burst handling
- **Monitoring:** Track CPU throttling events

#### Memory Optimization
- **Requests:** Set to 50% of typical usage
- **Limits:** Set to 2x requests for memory spikes
- **Monitoring:** Track OOM events

#### Storage Optimization
- **Fast SSD:** Use high-performance storage class
- **IOPS:** Configure appropriate IOPS for database
- **Monitoring:** Track disk latency and throughput

## 🚨 Rolling Updates and Deployments

### 1. Rolling Update Strategy

#### Configuration
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
    progressDeadlineSeconds: 600
```

#### Update Process
1. **New Replica Set:** Created with new pod template
2. **Scaling Up:** Create new pods up to maxSurge
3. **Health Checks:** Wait for new pods to be ready
4. **Termination:** Terminate old pods gracefully
5. **Cleanup:** Remove old Replica Set

### 2. Zero-Downtime Deployment

#### Blue-Green Deployment
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: chat-app-backend
spec:
  replicas: 3
  strategy:
    blueGreen:
      activeService: chat-app-backend-active
      previewService: chat-app-backend-preview
      autoPromotionEnabled: true
      scaleDownDelaySeconds: 30
      prePromotionAnalysisSeconds: 60
  selector:
    matchLabels:
      app: chat-app-backend
  template:
    metadata:
      labels:
        app: chat-app-backend
    spec:
      # ... pod template
```

#### Canary Deployment
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: chat-app-backend
spec:
  replicas: 3
  strategy:
    canary:
      steps:
      - setWeight: 20
      - setWeight: 40
      - setWeight: 60
      - setWeight: 80
      - setWeight: 100
      trafficRouting:
        managedRoutes:
        - primary
      analysis:
        templates:
        - templateName: success-rate
          templateName: latency
        args:
        - name: service-name
          value: chat-app-backend
        - name: stable-service
          value: chat-app-backend
```

## 🎯 Affinity and Anti-Affinity Rules

### 1. Pod Anti-Affinity

#### Backend Anti-Affinity
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - chat-app-backend
        topologyKey: kubernetes.io/hostname
    - weight: 50
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: component
            operator: In
            values:
            - backend
        topologyKey: kubernetes.io/hostname
```

#### MongoDB Anti-Affinity
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - mongodb
        topologyKey: kubernetes.io/hostname
```

### 2. Pod Affinity

#### Database Affinity
```yaml
affinity:
  podAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: component
            operator: In
            values:
            - backend
        topologyKey: kubernetes.io/hostname
```

### 3. Node Affinity

#### Application Nodes
```yaml
nodeSelector:
  kubernetes.io/os: linux
  node-type: application
```

#### Database Nodes
```yaml
nodeSelector:
  kubernetes.io/os: linux
  node-type: database
```

## 🗄️ MongoDB Reliability

### 1. StatefulSet Configuration

#### MongoDB StatefulSet
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
spec:
  serviceName: mongodb-headless
  replicas: 3
  podManagementPolicy: OrderedReady
  template:
    spec:
      containers:
      - name: mongodb
        # ... container spec
      - name: mongodb-backup
        # ... backup sidecar
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "fast-ssd"
      resources:
        requests:
          storage: 20Gi
```

### 2. Replica Set Configuration

#### MongoDB Replica Set
```javascript
// MongoDB replica set initialization
const initReplicaSet = async () => {
  const replicaSetConfig = {
    _id: 'mongodb-rs',
    members: [
      { _id: 0, host: 'mongodb-0.mongodb-headless.chat-app.svc.cluster.local:27017' },
      { _id: 1, host: 'mongodb-1.mongodb-headless.chat-app.svc.cluster.local:27017' },
      { _id: 2, host: 'mongodb-2.mongodb-headless.chat-app.svc.cluster.local:27017' }
    ],
    settings: {
      chainingAllowed: false,
      heartbeatIntervalMillis: 2000,
      heartbeatTimeoutSecs: 10,
      electionTimeoutMillis: 10000,
      catchUpTimeoutMillis: 20000,
      catchUpIntervalMillis: 2000
    }
  };

  await mongoShell.eval(`rs.initiate(${JSON.stringify(replicaSetConfig)})`);
};
```

### 3. Backup Strategy

#### Automated Backups
```yaml
# CronJob for daily backups
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup-cronjob
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: mongodb-backup
            image: mongo:7.0
            command:
            - sh
            - -c
            - |
              BACKUP_FILE="/backup/chatapp-backup-$(date +%Y%m%d-%H%M%S).gz"
              mongodump --host mongodb-0.mongodb-headless.chat-app.svc.cluster.local \
                        --port 27017 \
                        --username $MONGO_INITDB_ROOT_USERNAME \
                        --password $MONGO_INITDB_ROOT_PASSWORD \
                        --authenticationDatabase admin \
                        --db chatapp \
                        --out $BACKUP_FILE \
                        --gzip
              
              # Upload to S3
              if [ -n "$AWS_S3_BUCKET" ]; then
                aws s3 cp $BACKUP_FILE s3://$AWS_S3_BUCKET/mongodb-backups/
              fi
```

#### Backup Retention Policy
```yaml
# Backup retention configuration
backup:
  retention:
    daily: 30    # Keep 30 daily backups
    weekly: 12    # Keep 12 weekly backups
    monthly: 12   # Keep 12 monthly backups
    yearly: 5     # Keep 5 yearly backups
  compression: gzip
  encryption: true
```

## 🔒 Ingress Best Practices

### 1. TLS Configuration

#### Certificate Management
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: chat-app-tls-cert
spec:
  secretName: chat-app-tls-secret
  dnsNames:
  - chatapp.com
  - api.chatapp.com
  - "*.chatapp.com"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days before expiration
```

#### TLS Configuration
```yaml
spec:
  tls:
  - hosts:
    - chatapp.com
    - api.chatapp.com
    secretName: chat-app-tls-secret
```

### 2. Rate Limiting

#### Nginx Rate Limiting
```yaml
annotations:
  nginx.ingress.kubernetes.io/rate-limit: "100"
  nginx.ingress.kubernetes.io/rate-limit-window: "1m"
  nginx.ingress.kubernetes.io/rate-limit-burst: "200"
  nginx.ingress.kubernetes.io/rate-limit-connections: "50"
  nginx.ingress.kubernetes.io/rate-limit-connections-per-ip: "10"
```

#### Advanced Rate Limiting
```nginx
# Custom rate limiting configuration
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=upload:10m rate=2r/m;

server {
  # API rate limiting
  location /api/ {
    limit_req zone=api burst=20 nodelay;
  }
  
  # Login endpoint stricter limiting
  location /api/auth/login {
    limit_req zone=login burst=10 nodelay;
  }
  
  # File upload limiting
  location /api/upload {
    limit_req zone=upload burst=5 nodelay;
  }
}
```

### 3. Security Headers

#### Security Headers Configuration
```yaml
annotations:
  nginx.ingress.kubernetes.io/configuration-snippet: |
    more_set_headers "X-Frame-Options: DENY";
    more_set_headers "X-Content-Type-Options: nosniff";
    more_set_headers "X-XSS-Protection: 1; mode=block";
    more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
    more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
    more_set_headers "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self'; img-src 'self' data: https:;
```

### 4. WebSocket Support

#### WebSocket Configuration
```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
  nginx.ingress.kubernetes.io/affinity: "cookie"
  nginx.ingress.kubernetes.io/session-cookie-name: "chatapp-session"
  nginx.ingress.kubernetes.io/session-cookie-hash: "sha1"
  nginx.ingress.kubernetes.io/session-cookie-max-age: "3600"
```

## 📊 Monitoring and Alerting

### 1. Key Metrics

#### Application Metrics
- **Request Rate:** HTTP requests per second
- **Response Time:** 50th, 95th, 99th percentiles
- **Error Rate:** HTTP 5xx errors percentage
- **Throughput:** Messages per second
- **Active Users:** Concurrent WebSocket connections

#### Infrastructure Metrics
- **Pod Health:** Liveness and readiness probe status
- **Resource Usage:** CPU, memory, storage utilization
- **Network Traffic:** Ingress/egress bandwidth
- **Database Performance:** Connection count, query latency

### 2. Alerting Rules

#### Application Alerts
```yaml
- alert: HighErrorRate
  expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
  for: 2m
  labels:
    severity: warning
    service: chat-app-backend
  annotations:
    summary: "High error rate detected"
    description: "Error rate is {{ $value | humanizePercentage }}"

- alert: HighLatency
  expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 1
  for: 5m
  labels:
    severity: warning
    service: chat-app-backend
  annotations:
    summary: "High latency detected"
    description: "95th percentile latency is {{ $value }}s"
```

#### Infrastructure Alerts
```yaml
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Pod is crash looping"
    description: "Pod {{ $labels.pod }} is restarting frequently"

- alert: HighMemoryUsage
  expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High memory usage"
    description: "Memory usage is {{ $value | humanizePercentage }}"
```

## 🛠️ Operational Procedures

### 1. Deployment Checklist

#### Pre-Deployment
- [ ] Backup current deployment
- [ ] Review resource requirements
- [ ] Verify secrets and certificates
- [ ] Check node capacity
- [ ] Test rollback procedure

#### Post-Deployment
- [ ] Verify pod health
- [ ] Check HPA scaling
- [ ] Test application functionality
- [ ] Monitor error rates
- [ ] Validate TLS certificates

### 2. Troubleshooting Guide

#### Common Issues

**Pod Not Ready:**
```bash
# Check pod status
kubectl describe pod <pod-name> -n chat-app

# Check events
kubectl get events -n chat-app --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n chat-app
```

**HPA Not Scaling:**
```bash
# Check HPA status
kubectl describe hpa <hpa-name> -n chat-app

# Check metrics server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check resource utilization
kubectl top pods -n chat-app
```

**Ingress Issues:**
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress configuration
kubectl describe ingress <ingress-name> -n chat-app

# Test TLS certificate
openssl s_client -connect api.chatapp.com:443 -servername api.chatapp.com
```

### 3. Performance Tuning

#### Resource Optimization
- **CPU:** Monitor throttling, adjust limits accordingly
- **Memory:** Track OOM events, optimize garbage collection
- **I/O:** Use fast storage, monitor disk latency
- **Network:** Optimize packet size, enable compression

#### Scaling Optimization
- **HPA:** Adjust target utilization based on SLA
- **Cluster Autoscaler:** Enable node-level scaling
- **Pod Disruption Budget:** Ensure availability during updates

## 🔄 Disaster Recovery

### 1. Backup Strategy

#### Data Backup
- **MongoDB:** Daily automated backups with 30-day retention
- **Configuration:** Git version control for all manifests
- **Secrets:** Encrypted backup with rotation
- **Images:** Container registry with version tagging

#### Recovery Procedures
```bash
# Restore MongoDB from backup
kubectl exec -it mongodb-0 -- mongorestore --host localhost --port 27017 \
  --username $MONGO_INITDB_ROOT_USERNAME \
  --password $MONGO_INITDB_ROOT_PASSWORD \
  --authenticationDatabase admin \
  --db chatapp \
  /backup/backup-20240317-020000.gz

# Rollback deployment
kubectl rollout undo deployment/chat-app-backend -n chat-app
kubectl rollout status deployment/chat-app-backend -n chat-app
```

### 2. High Availability

#### Multi-Zone Deployment
```yaml
# Spread pods across availability zones
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: chat-app-backend
```

#### Cross-Region Replication
- **Database:** MongoDB replica set across zones
- **Application:** Multi-cluster deployment
- **CDN:** Global content delivery
- **DNS:** Geo-based routing

## 📚 Best Practices Summary

### 1. Security
- Use TLS for all external communications
- Implement rate limiting and DDoS protection
- Regular security updates and patching
- Network policies for least privilege
- Secrets management with rotation

### 2. Performance
- Right-size resources based on metrics
- Use appropriate storage classes
- Implement effective caching strategies
- Monitor and optimize database queries
- Enable compression for network traffic

### 3. Reliability
- Implement comprehensive health checks
- Use rolling updates for zero downtime
- Configure auto-scaling based on demand
- Set up proper backup and recovery
- Use pod disruption budgets

### 4. Observability
- Comprehensive logging and tracing
- Real-time metrics and alerting
- Performance monitoring and analysis
- Security monitoring and incident response
- Regular capacity planning

---

This production-grade reliability implementation provides enterprise-level scalability, security, and maintainability for your MERN Chat Application.
