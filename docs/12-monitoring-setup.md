# Monitoring Setup

This document outlines the setup and configuration of monitoring infrastructure for our k3s production environment using Prometheus and Grafana.

## Prerequisites

- k3s cluster running
- kubectl configured with cluster access
- Helm package manager installed
- Sufficient cluster resources for monitoring stack

## Monitoring Stack Installation

### 1. Create Monitoring Namespace

```bash
kubectl create namespace monitoring
```

### 2. Install Prometheus Operator

Create `prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  persistence:
    enabled: true
    size: 10Gi
  adminPassword: "your-secure-password"
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards

alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['job']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'slack'
    receivers:
    - name: 'slack'
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/your-webhook-url'
        channel: '#alerts'
        send_resolved: true
```

Install using Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml
```

## Application Monitoring

### 1. Configure Service Monitors

Create `go-server-monitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: go-server
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: go-server
  namespaceSelector:
    matchNames:
      - backend
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

Create `helper-server-monitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: helper-server
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: helper-server
  namespaceSelector:
    matchNames:
      - backend
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

Apply configurations:

```bash
kubectl apply -f go-server-monitor.yaml
kubectl apply -f helper-server-monitor.yaml
```

### 2. Add Application Metrics

Update your Go applications to expose Prometheus metrics:

```go
package main

import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    httpRequestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "endpoint", "status"},
    )

    httpRequestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "endpoint"},
    )
)

func init() {
    prometheus.MustRegister(httpRequestsTotal)
    prometheus.MustRegister(httpRequestDuration)
}

func main() {
    // ... other setup code ...

    // Expose metrics endpoint
    http.Handle("/metrics", promhttp.Handler())
}
```

## Grafana Dashboard Setup

### 1. Create Application Dashboard

Create `app-dashboard.json`:

```json
{
  "dashboard": {
    "title": "Application Overview",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{endpoint}}"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])",
            "legendFormat": "{{method}} {{endpoint}}"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5.*\"}[5m])",
            "legendFormat": "{{method}} {{endpoint}}"
          }
        ]
      }
    ]
  }
}
```

### 2. Configure System Dashboard

Create `system-dashboard.json`:

```json
{
  "dashboard": {
    "title": "System Overview",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"backend\"}[5m])) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(container_memory_usage_bytes{namespace=\"backend\"}) by (pod)",
            "legendFormat": "{{pod}}"
          }
        ]
      },
      {
        "title": "Network Traffic",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(container_network_receive_bytes_total{namespace=\"backend\"}[5m])) by (pod)",
            "legendFormat": "{{pod}} Receive"
          },
          {
            "expr": "sum(rate(container_network_transmit_bytes_total{namespace=\"backend\"}[5m])) by (pod)",
            "legendFormat": "{{pod}} Transmit"
          }
        ]
      }
    ]
  }
}
```

## Alert Configuration

### 1. Configure Alert Rules

Create `alert-rules.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: application-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
  - name: application
    rules:
    - alert: HighErrorRate
      expr: rate(http_requests_total{status=~"5.*"}[5m]) > 0.1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: High error rate detected
        description: "Error rate is {{ $value }} for the last 5 minutes"

    - alert: SlowResponses
      expr: rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m]) > 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: Slow response times detected
        description: "Average response time is {{ $value }}s for the last 5 minutes"

    - alert: HighMemoryUsage
      expr: container_memory_usage_bytes{namespace="backend"} > 1.5e9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: High memory usage detected
        description: "Pod {{ $labels.pod }} is using {{ $value }} bytes of memory"
```

Apply the rules:

```bash
kubectl apply -f alert-rules.yaml
```

### 2. Configure Alert Notifications

Update Alertmanager configuration:

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: alert-config
  namespace: monitoring
spec:
  route:
    receiver: 'slack'
    group_by: ['alertname', 'severity']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
  receivers:
  - name: 'slack'
    slack_configs:
    - api_url: 'https://hooks.slack.com/services/your-webhook-url'
      channel: '#alerts'
      send_resolved: true
      title: '{{ template "slack.default.title" . }}'
      text: '{{ template "slack.default.text" . }}'
```

## Log Aggregation

### 1. Install Loki

Create `loki-values.yaml`:

```yaml
loki:
  persistence:
    enabled: true
    size: 50Gi
  config:
    table_manager:
      retention_deletes_enabled: true
      retention_period: 336h

promtail:
  config:
    snippets:
      extraScrapeConfigs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            target_label: app
```

Install Loki:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --values loki-values.yaml
```

### 2. Configure Log Dashboard

Create `logs-dashboard.json`:

```json
{
  "dashboard": {
    "title": "Application Logs",
    "panels": [
      {
        "title": "Application Logs",
        "type": "logs",
        "targets": [
          {
            "expr": "{namespace=\"backend\"}"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate({namespace=\"backend\"} |= \"error\"[5m])) by (app)"
          }
        ]
      }
    ]
  }
}
```

## Best Practices

1. **Resource Management**:
   - Set appropriate resource limits
   - Configure retention policies
   - Monitor storage usage
   - Implement log rotation

2. **Alert Configuration**:
   - Define meaningful thresholds
   - Avoid alert fatigue
   - Group related alerts
   - Include actionable information

3. **Dashboard Organization**:
   - Create role-specific views
   - Use consistent naming
   - Include documentation
   - Regular dashboard reviews

4. **Security**:
   - Secure metrics endpoints
   - Implement authentication
   - Use TLS where possible
   - Regular security audits

## Troubleshooting

### Common Issues

1. **Prometheus Issues**:
   ```bash
   # Check Prometheus pods
   kubectl get pods -n monitoring -l app=prometheus
   
   # View Prometheus logs
   kubectl logs -n monitoring -l app=prometheus
   
   # Check targets
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
   ```

2. **Grafana Issues**:
   ```bash
   # Check Grafana status
   kubectl get pods -n monitoring -l app=grafana
   
   # Reset admin password
   kubectl exec -n monitoring $(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}') -- grafana-cli admin reset-admin-password newpassword
   ```

3. **Alert Manager Issues**:
   ```bash
   # Check alert manager
   kubectl get pods -n monitoring -l app=alertmanager
   
   # View alert manager config
   kubectl get secret -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
   ```

## Next Steps

After setting up monitoring, proceed to [Backup Strategy](13-backup-strategy.md) to configure data backup and recovery procedures. 