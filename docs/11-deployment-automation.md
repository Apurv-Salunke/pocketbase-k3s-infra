# Deployment Automation

This document outlines the setup and configuration of automated deployments using GitHub Actions for our k3s production environment.

## Prerequisites

- GitHub repository with application code
- ECR repositories configured (see [ECR Integration](10-ecr-integration.md))
- AWS IAM user with ECR permissions
- kubectl configured with cluster access
- GitHub Actions secrets configured

## GitHub Actions Setup

### 1. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

- `AWS_ACCESS_KEY_ID`: AWS access key for ECR access
- `AWS_SECRET_ACCESS_KEY`: AWS secret key for ECR access
- `AWS_REGION`: AWS region where ECR is located
- `KUBECONFIG_BASE64`: Base64 encoded kubeconfig file
- `PROD_NAMESPACE`: Production namespace (e.g., "backend")

### 2. Create Deployment Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches:
      - main
    paths:
      - 'go-server/**'
      - 'helper-server/**'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:

env:
  AWS_REGION: ${{ secrets.AWS_REGION }}
  ECR_GO_SERVER: go-server
  ECR_HELPER_SERVER: helper-server

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build and push Go Server
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        working-directory: ./go-server
        run: |
          docker build -t $ECR_REGISTRY/$ECR_GO_SERVER:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_GO_SERVER:$IMAGE_TAG
          echo "::set-output name=go_image::$ECR_REGISTRY/$ECR_GO_SERVER:$IMAGE_TAG"

      - name: Build and push Helper Server
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        working-directory: ./helper-server
        run: |
          docker build -t $ECR_REGISTRY/$ECR_HELPER_SERVER:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_HELPER_SERVER:$IMAGE_TAG
          echo "::set-output name=helper_image::$ECR_REGISTRY/$ECR_HELPER_SERVER:$IMAGE_TAG"

      - name: Setup Kubernetes config
        run: |
          mkdir -p ~/.kube
          echo ${{ secrets.KUBECONFIG_BASE64 }} | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config

      - name: Update deployments
        env:
          NAMESPACE: ${{ secrets.PROD_NAMESPACE }}
          GO_IMAGE: ${{ steps.login-ecr.outputs.go_image }}
          HELPER_IMAGE: ${{ steps.login-ecr.outputs.helper_image }}
        run: |
          # Update Go Server deployment
          kubectl set image deployment/go-server \
            go-server=$GO_IMAGE \
            -n $NAMESPACE

          # Update Helper Server deployment
          kubectl set image deployment/helper-server \
            helper-server=$HELPER_IMAGE \
            -n $NAMESPACE

      - name: Verify deployments
        env:
          NAMESPACE: ${{ secrets.PROD_NAMESPACE }}
        run: |
          kubectl rollout status deployment/go-server -n $NAMESPACE
          kubectl rollout status deployment/helper-server -n $NAMESPACE
```

## Deployment Strategy Configuration

### 1. Update Deployment Manifests

Update your deployment manifests to include rolling update strategy:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
  namespace: backend
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  minReadySeconds: 5
```

### 2. Configure Health Checks

Add readiness and liveness probes to ensure smooth rollouts:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
spec:
  template:
    spec:
      containers:
      - name: go-server
        livenessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 10
```

## Automated Testing

### 1. Create Pre-deployment Tests

Add test job to the workflow:

```yaml
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Go
        uses: actions/setup-go@v3
        with:
          go-version: '1.20'

      - name: Run Go tests
        working-directory: ./go-server
        run: go test -v ./...

      - name: Run Helper tests
        working-directory: ./helper-server
        run: go test -v ./...
```

### 2. Configure Integration Tests

Create integration test workflow:

```yaml
name: Integration Tests

on:
  pull_request:
    branches:
      - main

jobs:
  integration:
    runs-on: ubuntu-latest
    services:
      # Add required services for testing
      redis:
        image: redis
        ports:
          - 6379:6379
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Run integration tests
        run: |
          # Add integration test commands
          go test -tags=integration ./...
```

## Rollback Strategy

### 1. Create Rollback Script

Create `scripts/rollback.sh`:

```bash
#!/bin/bash

DEPLOYMENT=$1
NAMESPACE=$2
REVISION=$3

if [ -z "$REVISION" ]; then
  # Rollback to previous version
  kubectl rollout undo deployment/$DEPLOYMENT -n $NAMESPACE
else
  # Rollback to specific revision
  kubectl rollout undo deployment/$DEPLOYMENT -n $NAMESPACE --to-revision=$REVISION
fi

# Wait for rollback to complete
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE
```

### 2. Configure Automated Rollback

Add rollback step to workflow:

```yaml
      - name: Rollback on failure
        if: failure()
        env:
          NAMESPACE: ${{ secrets.PROD_NAMESPACE }}
        run: |
          kubectl rollout undo deployment/go-server -n $NAMESPACE
          kubectl rollout undo deployment/helper-server -n $NAMESPACE
```

## Monitoring and Notifications

### 1. Configure Slack Notifications

Add Slack notification step:

```yaml
      - name: Notify Slack
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          fields: repo,message,commit,author,action,eventName,ref,workflow
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
        if: always()
```

### 2. Add Deployment Metrics

Create monitoring configuration:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: deployment-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: go-server
  endpoints:
  - port: metrics
```

## Best Practices

1. **Deployment Safety**:
   - Use rolling updates
   - Implement health checks
   - Configure resource limits
   - Set up monitoring alerts

2. **CI/CD Pipeline**:
   - Automate testing
   - Implement code quality checks
   - Use semantic versioning
   - Configure automated rollbacks

3. **Security**:
   - Rotate credentials regularly
   - Scan containers for vulnerabilities
   - Use least privilege principle
   - Implement audit logging

4. **Monitoring**:
   - Track deployment success rates
   - Monitor application health
   - Set up alerting
   - Log deployment events

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   ```bash
   # Check deployment status
   kubectl rollout status deployment/go-server -n backend
   
   # Check pod events
   kubectl describe pod -l app=go-server -n backend
   ```

2. **Image Pull Issues**:
   ```bash
   # Verify ECR authentication
   kubectl get secret docker-registry-ecr -n backend
   
   # Check pod events
   kubectl get events -n backend --sort-by='.lastTimestamp'
   ```

3. **Health Check Failures**:
   ```bash
   # Check pod logs
   kubectl logs -l app=go-server -n backend
   
   # Describe pod for health check status
   kubectl describe pod -l app=go-server -n backend
   ```

## Next Steps

After setting up deployment automation, proceed to [Monitoring Setup](12-monitoring-setup.md) to configure comprehensive monitoring for your production environment. 