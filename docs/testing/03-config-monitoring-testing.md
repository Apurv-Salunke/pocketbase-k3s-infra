# Configuration and Monitoring Testing Guide

This guide outlines the testing procedures for configuration management and monitoring setup.

## Prerequisites

1. Successful completion of application deployment
2. Access to the k3s cluster
3. kubectl configured with cluster access
4. Helm installed

## Testing Steps

### 1. Configuration Testing

1. Apply ConfigMaps:
```bash
# Create ConfigMaps
kubectl apply -f kubernetes/config/app-config.yaml

# Verify ConfigMaps
kubectl get configmaps -n backend
kubectl describe configmap go-server-config -n backend
kubectl describe configmap helper-server-config -n backend
```

2. Create and verify secrets:
```bash
# First, create a script to generate secure values
cat > generate-secrets.sh << 'EOF'
#!/bin/bash
echo "API_KEY=$(openssl rand -base64 32)"
echo "ADMIN_TOKEN=$(openssl rand -base64 32)"
echo "ENCRYPTION_KEY=$(openssl rand -base64 32)"
echo "GRAFANA_PASSWORD=$(openssl rand -base64 16)"
EOF

chmod +x generate-secrets.sh
source <(./generate-secrets.sh)

# Create secrets using generated values
envsubst < kubernetes/config/secrets.yaml | kubectl apply -f -

# Verify secrets
kubectl get secrets -n backend
kubectl get secrets -n monitoring
```

### 2. Monitoring Setup Testing

1. Install Prometheus Operator:
```bash
# Apply Prometheus configuration
kubectl apply -f kubernetes/monitoring/prometheus-operator.yaml

# Verify installation
kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
```

2. Verify Grafana setup:
```bash
# Get Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Access Grafana UI at http://localhost:3000
```

3. Check dashboards:
```bash
# Verify dashboard configuration
kubectl get configmaps -n monitoring -l grafana_dashboard=1

# Check if dashboards are loaded in Grafana UI
# Navigate to http://localhost:3000/dashboards
```

### 3. Alert Testing

1. Test alert rules:
```bash
# Apply alert rules
kubectl apply -f kubernetes/monitoring/alerts.yaml

# Verify rules
kubectl get prometheusrules -n monitoring
kubectl describe prometheusrule application-alerts -n monitoring
```

2. Simulate alert conditions:
```bash
# Generate high error rate
kubectl run load-test --image=busybox -- /bin/sh -c 'while true; do wget -O- http://go-server/nonexistent; sleep 0.1; done'

# Check alert status in Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/alerts
```

## Validation Tests

### 1. Configuration Validation

1. Test ConfigMap updates:
```bash
# Update a ConfigMap value
kubectl edit configmap go-server-config -n backend

# Verify changes are reflected
kubectl get pods -n backend -w  # Watch for pod restarts
```

2. Test secret rotation:
```bash
# Generate new secrets
source <(./generate-secrets.sh)

# Update secrets
envsubst < kubernetes/config/secrets.yaml | kubectl apply -f -

# Verify applications still work
curl -v https://api.yourdomain.com/health
```

### 2. Monitoring Validation

1. Metrics collection:
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets

# Verify metrics are being collected
curl -s http://localhost:9090/api/v1/query?query=up
```

2. Dashboard functionality:
```bash
# Check dashboard data
# Visit http://localhost:3000/d/app-overview/application-overview
# Visit http://localhost:3000/d/system-overview/system-overview

# Verify metrics are updating
```

### 3. Alert Validation

1. Test alert notifications:
```bash
# Create a test alert
kubectl run memory-hog --image=busybox -- /bin/sh -c 'while true; do :; done'

# Verify alert is triggered
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093
# Visit http://localhost:9093/#/alerts
```

## Expected Results

### Configuration Management

1. ConfigMaps:
   - [ ] All ConfigMaps created successfully
   - [ ] Applications can read configuration
   - [ ] Configuration updates trigger pod restarts

2. Secrets:
   - [ ] All secrets created successfully
   - [ ] Applications can access secrets
   - [ ] Secret rotation works without issues

### Monitoring System

1. Prometheus:
   - [ ] All targets are up
   - [ ] Metrics are being collected
   - [ ] Alert rules are loaded

2. Grafana:
   - [ ] Dashboards are available
   - [ ] Metrics are displayed correctly
   - [ ] Graphs are updating

3. Alerting:
   - [ ] Alert rules are active
   - [ ] Notifications are working
   - [ ] Alert conditions trigger correctly

## Troubleshooting

### Common Issues

1. Configuration Issues:
```bash
# Check pod environment variables
kubectl exec -n backend deploy/go-server -- env

# Check mounted configs
kubectl exec -n backend deploy/go-server -- cat /etc/config/app-config.yaml
```

2. Monitoring Issues:
```bash
# Check Prometheus logs
kubectl logs -n monitoring -l app=prometheus

# Check Grafana logs
kubectl logs -n monitoring -l app=grafana
```

3. Alert Issues:
```bash
# Check AlertManager
kubectl logs -n monitoring -l app=alertmanager

# Verify alert rules
kubectl get prometheusrules -n monitoring -o yaml
```

## Next Steps

After successful testing:

1. Document any configuration changes
2. Update alert thresholds if needed
3. Add custom dashboards as required
4. Proceed to CI/CD setup 