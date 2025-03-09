# CI/CD Testing Guide

This guide outlines the testing procedures for the CI/CD pipeline setup.

## Prerequisites

1. GitHub repository configured
2. AWS ECR repositories created
3. GitHub Actions secrets configured
4. Access to k3s cluster

## Required Secrets

Configure the following secrets in GitHub repository settings:

1. AWS Credentials:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION`

2. Kubernetes Configuration:
   - `KUBECONFIG_BASE64` (base64 encoded kubeconfig)

3. Notifications:
   - `SLACK_WEBHOOK_URL`

## Testing Steps

### 1. CI Pipeline Testing

1. Test the CI workflow:
```bash
# Make a test commit
git checkout -b test-ci
echo "# Test" >> README.md
git add README.md
git commit -m "test: CI pipeline"
git push origin test-ci

# Create pull request
# Check GitHub Actions tab for workflow status
```

2. Verify test job:
```bash
# Check test results in GitHub Actions
# Verify code coverage report
# Check security scan results
```

3. Test security scanning:
```bash
# Introduce a test vulnerability
echo "func vulnerable() { exec.Command(userInput) }" >> main.go
git commit -am "test: security scanning"
git push

# Verify security scan catches the issue
```

### 2. Build Process Testing

1. Test image building:
```bash
# Push to main branch
git checkout main
git merge test-ci
git push origin main

# Verify in GitHub Actions:
- Image build process
- ECR push success
```

2. Verify ECR images:
```bash
# List images in ECR
aws ecr describe-images \
    --repository-name go-server \
    --region $AWS_REGION

aws ecr describe-images \
    --repository-name helper-server \
    --region $AWS_REGION
```

### 3. CD Pipeline Testing

1. Test deployment process:
```bash
# Watch deployment status
kubectl get pods -n backend -w

# Verify new images
kubectl describe deployment/go-server -n backend
kubectl describe deployment/helper-server -n backend
```

2. Test rollback:
```bash
# Simulate failed deployment
kubectl set image deployment/go-server \
  go-server=nonexistent:latest -n backend

# Verify automatic rollback
kubectl rollout history deployment/go-server -n backend
```

3. Test smoke tests:
```bash
# Check service endpoints
kubectl get svc -n backend

# Test health endpoints
curl http://<service-ip>/health
```

## Validation Tests

### 1. End-to-End Pipeline Test

1. Make a complete change:
```bash
# Update application code
git checkout -b feature/test
# Make changes to application
git commit -am "feat: test pipeline"
git push origin feature/test

# Create and merge PR
# Watch entire pipeline execute
```

2. Verify deployment:
```bash
# Check deployment status
kubectl get deployments -n backend

# Verify application version
curl http://<service-ip>/version
```

### 2. Security Testing

1. Test secret handling:
```bash
# Verify secrets are not exposed
kubectl get pods -n backend -o yaml | grep -i secret

# Check ECR authentication
kubectl describe pods -n backend | grep -A 5 "Events:"
```

2. Test access controls:
```bash
# Verify RBAC settings
kubectl auth can-i get secrets -n backend
kubectl auth can-i update deployments -n backend
```

### 3. Monitoring Integration

1. Check deployment metrics:
```bash
# View deployment metrics in Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Visit Deployment dashboard
```

2. Verify alerts:
```bash
# Check alert status
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Visit AlertManager UI
```

## Expected Results

### CI Pipeline

1. Tests:
   - [ ] All tests pass
   - [ ] Coverage reports generated
   - [ ] Security scans complete

2. Build:
   - [ ] Images built successfully
   - [ ] Images pushed to ECR
   - [ ] Tags applied correctly

### CD Pipeline

1. Deployment:
   - [ ] Automatic deployment triggered
   - [ ] Rolling update successful
   - [ ] Health checks passing

2. Monitoring:
   - [ ] Deployment metrics recorded
   - [ ] Alerts configured
   - [ ] Notifications sent

## Troubleshooting

### Common Issues

1. CI Failures:
```bash
# Check GitHub Actions logs
# Verify test environment
# Check security scan configuration
```

2. Build Issues:
```bash
# Check ECR permissions
aws ecr get-login-password

# Verify Docker build
docker build -t test ./go-server
```

3. Deployment Issues:
```bash
# Check deployment logs
kubectl logs -n backend deploy/go-server

# Check events
kubectl get events -n backend
```

## Next Steps

After successful testing:

1. Document pipeline configuration
2. Set up branch protection rules
3. Configure automated cleanup
4. Set up monitoring alerts 