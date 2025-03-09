# ECR Integration

This document outlines the process of integrating Amazon Elastic Container Registry (ECR) with our k3s cluster for container image management.

## Prerequisites

- AWS CLI installed and configured
- AWS IAM permissions for ECR
- kubectl configured with cluster access
- Docker installed for local testing

## ECR Repository Setup

### 1. Create ECR Repositories

Create repositories for both services:

```bash
# Create repository for go-server
aws ecr create-repository \
    --repository-name go-server \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

# Create repository for helper-server
aws ecr create-repository \
    --repository-name helper-server \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256
```

### 2. Set Repository Policies

Create `ecr-policy.json`:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPullPush",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/k3s-node-role"
            },
            "Action": [
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:CompleteLayerUpload",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage"
            ]
        }
    ]
}
```

Apply the policy:

```bash
# Apply policy to go-server repository
aws ecr set-repository-policy \
    --repository-name go-server \
    --policy-text file://ecr-policy.json

# Apply policy to helper-server repository
aws ecr set-repository-policy \
    --repository-name helper-server \
    --policy-text file://ecr-policy.json
```

## Kubernetes Authentication Setup

### 1. Create ECR Secret Helper

Create `ecr-secret-helper.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-credential-helper
  namespace: backend
spec:
  schedule: "*/6 * * * *"  # Every 6 hours
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-helper
          containers:
          - name: ecr-helper
            image: amazon/aws-cli
            command:
            - /bin/sh
            - -c
            - |
              TOKEN=$(aws ecr get-login-password --region <AWS_REGION>)
              kubectl delete secret --ignore-not-found docker-registry-ecr
              kubectl create secret docker-registry docker-registry-ecr \
                --docker-server=<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com \
                --docker-username=AWS \
                --docker-password="${TOKEN}"
          restartPolicy: OnFailure
```

### 2. Create Service Account for ECR Helper

Create `ecr-helper-rbac.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-helper
  namespace: backend
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ecr-helper
  namespace: backend
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["create", "delete", "get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ecr-helper
  namespace: backend
subjects:
- kind: ServiceAccount
  name: ecr-helper
  namespace: backend
roleRef:
  kind: Role
  name: ecr-helper
  apiGroup: rbac.authorization.k8s.io
```

## Image Management

### 1. Configure Image Lifecycle Policy

Create `lifecycle-policy.json`:

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 30 production images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["prod-"],
                "countType": "imageCountMoreThan",
                "countNumber": 30
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Expire untagged images older than 14 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 14
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
```

Apply the lifecycle policy:

```bash
# Apply to go-server repository
aws ecr put-lifecycle-policy \
    --repository-name go-server \
    --lifecycle-policy-text file://lifecycle-policy.json

# Apply to helper-server repository
aws ecr put-lifecycle-policy \
    --repository-name helper-server \
    --lifecycle-policy-text file://lifecycle-policy.json
```

### 2. Configure Image Scanning

Enable vulnerability scanning:

```bash
# Enable scanning for go-server
aws ecr put-image-scanning-configuration \
    --repository-name go-server \
    --image-scanning-configuration scanOnPush=true

# Enable scanning for helper-server
aws ecr put-image-scanning-configuration \
    --repository-name helper-server \
    --image-scanning-configuration scanOnPush=true
```

## Local Development Setup

### 1. Create ECR Login Helper Script

Create `ecr-login.sh`:

```bash
#!/bin/bash

AWS_REGION="<your-region>"
AWS_ACCOUNT_ID="<your-account-id>"

# Get ECR login token
aws ecr get-login-password --region ${AWS_REGION} | \
docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Set environment variables
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export GO_SERVER_REPO="${ECR_REGISTRY}/go-server"
export HELPER_SERVER_REPO="${ECR_REGISTRY}/helper-server"
```

### 2. Create Docker Build Scripts

Create `build-and-push.sh`:

```bash
#!/bin/bash

# Source ECR login script
source ./ecr-login.sh

# Build and push go-server
docker build -t ${GO_SERVER_REPO}:latest ../go-server
docker push ${GO_SERVER_REPO}:latest

# Build and push helper-server
docker build -t ${HELPER_SERVER_REPO}:latest ../helper-server
docker push ${HELPER_SERVER_REPO}:latest
```

## Deployment Integration

### 1. Update Deployment Manifests

Update the image pull secrets in deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
spec:
  template:
    spec:
      imagePullSecrets:
      - name: docker-registry-ecr
```

### 2. Create Image Pull Secret Test

Create `test-ecr-pull.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ecr-test
  namespace: backend
spec:
  containers:
  - name: test
    image: <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/go-server:latest
  imagePullSecrets:
  - name: docker-registry-ecr
```

## Verification and Testing

### 1. Test ECR Authentication

```bash
# Test ECR login
aws ecr get-login-password --region <AWS_REGION> | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com

# Verify repositories
aws ecr describe-repositories

# List images
aws ecr list-images --repository-name go-server
```

### 2. Test Image Pulling

```bash
# Create test pod
kubectl apply -f test-ecr-pull.yaml

# Check pod status
kubectl get pod ecr-test -n backend

# Check pull events
kubectl describe pod ecr-test -n backend
```

### 3. Verify Credentials Rotation

```bash
# Check CronJob status
kubectl get cronjob ecr-credential-helper -n backend

# Check latest job logs
kubectl logs -l job-name=ecr-credential-helper -n backend --tail=100

# Verify secret creation
kubectl get secret docker-registry-ecr -n backend
```

## Troubleshooting

### Common Issues

1. **Authentication Failures**:
   ```bash
   # Check ECR credentials
   kubectl get secret docker-registry-ecr -n backend -o yaml
   
   # Verify AWS credentials
   aws sts get-caller-identity
   ```

2. **Image Pull Issues**:
   ```bash
   # Check pod events
   kubectl describe pod <pod-name> -n backend
   
   # Verify image exists
   aws ecr describe-images --repository-name go-server --image-ids imageTag=latest
   ```

3. **Permission Issues**:
   ```bash
   # Check IAM role
   aws iam get-role --role-name k3s-node-role
   
   # Verify repository policy
   aws ecr get-repository-policy --repository-name go-server
   ```

## Best Practices

1. **Image Management**:
   - Use semantic versioning for image tags
   - Implement automated vulnerability scanning
   - Regular cleanup of unused images
   - Document image build process

2. **Security**:
   - Rotate ECR credentials regularly
   - Implement least privilege access
   - Enable image scanning
   - Use private repositories

3. **CI/CD Integration**:
   - Automate image builds
   - Implement automated testing
   - Use consistent tagging strategy
   - Document deployment process

## Next Steps

After setting up ECR integration, proceed to [Deployment Automation](11-deployment-automation.md) to configure automated deployments. 