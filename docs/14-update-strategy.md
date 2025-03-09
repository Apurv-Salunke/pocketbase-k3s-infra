# Update Strategy

This document outlines the procedures for safely updating our k3s cluster, applications, and dependencies while maintaining system stability and minimizing downtime.

## Prerequisites

- Access to cluster with administrative privileges
- Backup strategy implemented (see [Backup Strategy](13-backup-strategy.md))
- Monitoring system operational (see [Monitoring Setup](12-monitoring-setup.md))
- Staging environment for testing updates

## Update Components

### 1. K3s Version Updates

Create `k3s-update.sh`:

```bash
#!/bin/bash

# Get current version
CURRENT_VERSION=$(k3s --version)
echo "Current K3s version: $CURRENT_VERSION"

# Check available versions
curl -s https://api.github.com/repos/k3s-io/k3s/releases | grep tag_name

# Stop k3s service
systemctl stop k3s

# Download and install new version
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.x sh -

# Start k3s service
systemctl start k3s

# Verify update
kubectl get nodes
kubectl get pods -A
```

### 2. Node Updates

Create `node-update.sh`:

```bash
#!/bin/bash

# Update system packages
apt-get update
apt-get upgrade -y

# Check for required reboots
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required. Proceeding with controlled reboot..."
    
    # Drain the node
    kubectl drain $(hostname) --ignore-daemonsets
    
    # Reboot
    reboot
fi
```

## Application Updates

### 1. Rolling Update Configuration

Update deployment manifests to include rolling update strategy:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  minReadySeconds: 30
  revisionHistoryLimit: 5
```

### 2. Canary Deployments

Create `canary-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: go-server
      track: canary
  template:
    metadata:
      labels:
        app: go-server
        track: canary
    spec:
      containers:
      - name: go-server
        image: your-registry/go-server:new-version
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
```

Create canary service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: go-server-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "20"
spec:
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: go-server-canary
            port:
              number: 80
```

## Dependency Updates

### 1. Container Image Updates

Create `update-images.sh`:

```bash
#!/bin/bash

# Update base images
docker pull alpine:latest
docker pull golang:1.20-alpine

# Rebuild application images
docker build -t your-registry/go-server:new .
docker build -t your-registry/helper-server:new .

# Push updated images
docker push your-registry/go-server:new
docker push your-registry/helper-server:new
```

### 2. Application Dependencies

Create `update-dependencies.sh`:

```bash
#!/bin/bash

# Update Go dependencies
go get -u ./...
go mod tidy

# Check for security vulnerabilities
go list -json -m all | nancy sleuth

# Run tests
go test ./...

# Update container dependencies
docker run --rm -v "$PWD":/app -w /app alpine:latest apk update
```

## Update Procedures

### 1. Pre-update Checklist

Create `pre-update-checklist.sh`:

```bash
#!/bin/bash

# Check cluster health
kubectl get nodes
kubectl get pods -A

# Verify backups
velero backup create pre-update-backup --wait

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Verify monitoring
curl -s http://prometheus:9090/-/healthy
curl -s http://grafana:3000/api/health
```

### 2. Update Process

Create `perform-update.sh`:

```bash
#!/bin/bash

# Set maintenance window
kubectl annotate namespace backend maintenance="true"

# Scale down non-critical services
kubectl scale deployment helper-server --replicas=0

# Apply updates
kubectl apply -f new-deployment.yaml

# Monitor rollout
kubectl rollout status deployment/go-server

# Verify functionality
./run-smoke-tests.sh

# Scale up services
kubectl scale deployment helper-server --replicas=2

# Remove maintenance annotation
kubectl annotate namespace backend maintenance-
```

## Monitoring During Updates

### 1. Update Monitoring Rules

Create `update-monitoring.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: update-alerts
  namespace: monitoring
spec:
  groups:
  - name: updates
    rules:
    - alert: UpdateFailure
      expr: |
        kube_deployment_status_observed_generation{namespace="backend"}
        != kube_deployment_metadata_generation{namespace="backend"}
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: Deployment update failed
        description: Deployment {{ $labels.deployment }} failed to update

    - alert: PodRestartDuringUpdate
      expr: |
        increase(kube_pod_container_status_restarts_total{namespace="backend"}[5m]) > 0
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: Pod restarts during update
        description: Pod {{ $labels.pod }} has restarted during the update
```

### 2. Update Dashboards

Create `update-dashboard.json`:

```json
{
  "dashboard": {
    "title": "Update Status",
    "panels": [
      {
        "title": "Deployment Progress",
        "type": "gauge",
        "targets": [
          {
            "expr": "kube_deployment_status_replicas_updated{namespace=\"backend\"} / kube_deployment_spec_replicas{namespace=\"backend\"}"
          }
        ]
      },
      {
        "title": "Pod Health During Update",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"backend\"}[5m])) by (pod)"
          }
        ]
      }
    ]
  }
}
```

## Rollback Procedures

### 1. Automated Rollback

Create `rollback.sh`:

```bash
#!/bin/bash

DEPLOYMENT=$1
NAMESPACE=$2
VERSION=$3

# Check deployment status
if ! kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE; then
    echo "Deployment failed, initiating rollback..."
    
    # Perform rollback
    kubectl rollout undo deployment/$DEPLOYMENT -n $NAMESPACE
    
    # Verify rollback
    kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE
    
    # Send notification
    curl -X POST $SLACK_WEBHOOK -H 'Content-type: application/json' \
        --data '{"text":"Rollback initiated for '$DEPLOYMENT'"}'
fi
```

### 2. Manual Rollback Steps

Create `manual-rollback.md`:

```markdown
1. Identify the issue:
   ```bash
   kubectl describe deployment <deployment-name>
   kubectl logs -l app=<app-name>
   ```

2. Stop the rollout:
   ```bash
   kubectl rollout pause deployment/<deployment-name>
   ```

3. Verify current state:
   ```bash
   kubectl get pods
   kubectl get events
   ```

4. Perform rollback:
   ```bash
   kubectl rollout undo deployment/<deployment-name>
   ```

5. Verify rollback:
   ```bash
   kubectl rollout status deployment/<deployment-name>
   kubectl get pods
   ```
```

## Best Practices

1. **Update Planning**:
   - Schedule updates during low-traffic periods
   - Document all changes and dependencies
   - Test updates in staging environment
   - Prepare rollback plans

2. **Testing**:
   - Automated testing before deployment
   - Canary deployments for major updates
   - Load testing after updates
   - Integration testing with dependencies

3. **Monitoring**:
   - Monitor system during updates
   - Track performance metrics
   - Set up alerts for failures
   - Document any issues

4. **Communication**:
   - Notify stakeholders before updates
   - Document downtime expectations
   - Maintain update changelog
   - Post-update status reports

## Troubleshooting

### Common Issues

1. **Failed Updates**:
   ```bash
   # Check deployment status
   kubectl rollout history deployment/<deployment-name>
   
   # View detailed events
   kubectl describe deployment/<deployment-name>
   
   # Check pod logs
   kubectl logs -l app=<app-name> --tail=100
   ```

2. **Performance Issues**:
   ```bash
   # Monitor resource usage
   kubectl top pods
   
   # Check node status
   kubectl describe node <node-name>
   
   # View metrics
   kubectl get --raw /metrics
   ```

3. **Dependency Conflicts**:
   ```bash
   # Check container image
   kubectl describe pod <pod-name>
   
   # Verify configurations
   kubectl get configmap <config-name> -o yaml
   
   # Test connectivity
   kubectl exec <pod-name> -- curl -v service-name
   ```

## Maintenance Schedule

Create `maintenance-schedule.yaml`:

```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: system-updates
  namespace: maintenance
spec:
  schedule: "0 1 * * 0"  # Weekly at 1 AM on Sunday
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: system-update
            image: your-registry/maintenance:latest
            command:
            - /bin/sh
            - -c
            - |
              ./pre-update-checklist.sh
              ./node-update.sh
              ./update-dependencies.sh
              ./perform-update.sh
          restartPolicy: OnFailure
```

## Next Steps

This completes the documentation for our k3s production deployment. Regular review and updates of these procedures are recommended to maintain system reliability and security. 