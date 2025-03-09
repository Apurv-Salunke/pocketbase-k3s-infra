# ConfigMaps and Secrets Management

This document outlines the management of configuration data and sensitive information for our k3s production deployment using ConfigMaps and Secrets.

## Prerequisites

- Kubernetes cluster set up as described in previous documents
- `kubectl` configured with appropriate access
- AWS CLI configured (for ECR secrets)

## Configuration Categories

We'll organize our configurations into:

1. Application Configuration (ConfigMaps)
2. Sensitive Data (Secrets)
3. External Service Credentials
4. TLS Certificates

## Application Configuration (ConfigMaps)

### 1. Go Server Configuration

Create `go-server-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: go-server-config
  namespace: backend
data:
  # Server Configuration
  SERVER_PORT: "9000"
  LOG_LEVEL: "info"
  ENVIRONMENT: "production"
  
  # Application Settings
  MAX_REQUEST_SIZE: "50mb"
  REQUEST_TIMEOUT: "30s"
  
  # Database Configuration
  DB_PATH: "/app/pb_data"
  
  # CORS Configuration
  ALLOWED_ORIGINS: "https://api.yourdomain.com"
  
  # Custom Application Settings
  app-config.yaml: |
    logging:
      format: json
      level: info
    metrics:
      enabled: true
      path: /metrics
    health:
      enabled: true
      path: /health
```

### 2. Helper Server Configuration

Create `helper-server-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: helper-server-config
  namespace: backend
data:
  # Server Configuration
  PORT: "8080"
  LOG_LEVEL: "info"
  ENVIRONMENT: "production"
  
  # Main Server Connection
  MAIN_SERVER_URL: "http://go-server:9000"
  
  # Import Configuration
  MAX_IMPORT_SIZE: "10mb"
  IMPORT_TIMEOUT: "5m"
  
  # Feature Flags
  ENABLE_VALIDATION: "true"
  ENABLE_PREPROCESSING: "true"
```

## Sensitive Data Management (Secrets)

### 1. Application Secrets

Create `app-secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: backend
type: Opaque
stringData:
  API_KEY: "your-api-key"
  ADMIN_TOKEN: "your-admin-token"
  ENCRYPTION_KEY: "your-encryption-key"
```

### 2. External Service Credentials

Create `external-services.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: external-services
  namespace: backend
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "your-access-key"
  AWS_SECRET_ACCESS_KEY: "your-secret-key"
  AWS_REGION: "your-region"
```

### 3. Database Credentials (if needed)

Create `db-credentials.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: backend
type: Opaque
stringData:
  DB_USER: "your-db-user"
  DB_PASSWORD: "your-db-password"
  DB_CONNECTION_STRING: "your-connection-string"
```

## Secure Secret Management

### 1. Create a Script for Secret Generation

Create `generate-secrets.sh`:

```bash
#!/bin/bash

# Generate random keys
API_KEY=$(openssl rand -base64 32)
ADMIN_TOKEN=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Create secret yaml
cat <<EOF > app-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: backend
type: Opaque
stringData:
  API_KEY: "${API_KEY}"
  ADMIN_TOKEN: "${ADMIN_TOKEN}"
  ENCRYPTION_KEY: "${ENCRYPTION_KEY}"
EOF
```

### 2. Set Up AWS Secrets Manager Integration (Optional)

Create `aws-secrets-sync.yaml`:

```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: aws-secrets-sync
  namespace: backend
spec:
  schedule: "0 0 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: aws-secrets-sync
            image: amazon/aws-cli
            command:
            - /bin/sh
            - -c
            - |
              aws secretsmanager get-secret-value --secret-id prod/app-secrets \
                --query SecretString --output text | \
              kubectl create secret generic app-secrets \
                --namespace=backend --from-file=secrets.json=/dev/stdin \
                --dry-run=client -o yaml | \
              kubectl apply -f -
          serviceAccountName: aws-secrets-manager
          restartPolicy: OnFailure
```

## Using ConfigMaps and Secrets in Deployments

### 1. Update Go Server Deployment

Update the deployment to use the configurations:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
  namespace: backend
spec:
  template:
    spec:
      containers:
      - name: go-server
        envFrom:
        - configMapRef:
            name: go-server-config
        - secretRef:
            name: app-secrets
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: go-server-config
          items:
          - key: app-config.yaml
            path: config.yaml
```

### 2. Update Helper Server Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helper-server
  namespace: backend
spec:
  template:
    spec:
      containers:
      - name: helper-server
        envFrom:
        - configMapRef:
            name: helper-server-config
        - secretRef:
            name: app-secrets
```

## Secret Rotation and Management

### 1. Create Secret Rotation Script

Create `rotate-secrets.sh`:

```bash
#!/bin/bash

# Generate new secrets
NEW_API_KEY=$(openssl rand -base64 32)

# Update secret
kubectl create secret generic app-secrets \
  --namespace=backend \
  --from-literal=API_KEY="$NEW_API_KEY" \
  --dry-run=client -o yaml | \
kubectl apply -f -

# Restart deployments to pick up new secrets
kubectl rollout restart deployment/go-server -n backend
kubectl rollout restart deployment/helper-server -n backend
```

### 2. Set Up Secret Rotation Schedule

Create `secret-rotation-job.yaml`:

```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: secret-rotation
  namespace: backend
spec:
  schedule: "0 0 1 * *"  # Monthly rotation
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: secret-rotation
            image: bitnami/kubectl
            command:
            - /scripts/rotate-secrets.sh
            volumeMounts:
            - name: rotation-script
              mountPath: /scripts
              readOnly: true
          volumes:
          - name: rotation-script
            configMap:
              name: rotation-script
              defaultMode: 0755
          serviceAccountName: secret-rotation
          restartPolicy: OnFailure
```

## Verification and Monitoring

### 1. Verify ConfigMap and Secret Creation

```bash
# Check ConfigMaps
kubectl get configmaps -n backend
kubectl describe configmap go-server-config -n backend

# Check Secrets
kubectl get secrets -n backend
kubectl describe secret app-secrets -n backend
```

### 2. Verify Configuration Loading

```bash
# Check environment variables in pods
kubectl exec -n backend deploy/go-server -- env
kubectl exec -n backend deploy/helper-server -- env

# Check mounted configurations
kubectl exec -n backend deploy/go-server -- cat /app/config/config.yaml
```

### 3. Monitor Secret Usage

```bash
# Check secret access logs
kubectl logs -n backend deploy/go-server
kubectl logs -n backend deploy/helper-server

# Monitor secret rotation jobs
kubectl get cronjobs -n backend
kubectl get jobs -n backend
```

## Best Practices

1. **Security**:
   - Never commit secrets to version control
   - Use encryption at rest for secrets
   - Implement secret rotation
   - Use least privilege access

2. **Configuration Management**:
   - Version control ConfigMaps
   - Document all configuration options
   - Use meaningful naming conventions
   - Keep configurations environment-specific

3. **Monitoring and Maintenance**:
   - Monitor secret access
   - Audit configuration changes
   - Maintain backup of configurations
   - Document rotation procedures

## Troubleshooting

### Common Issues

1. **Secret Access Issues**:
   ```bash
   # Check secret permissions
   kubectl auth can-i get secrets -n backend
   
   # Verify secret exists
   kubectl get secret app-secrets -n backend
   ```

2. **Configuration Loading Issues**:
   ```bash
   # Check pod events
   kubectl describe pod -n backend -l app=go-server
   
   # Check mounted config
   kubectl exec -n backend deploy/go-server -- ls -la /app/config
   ```

3. **Secret Rotation Issues**:
   ```bash
   # Check rotation job logs
   kubectl logs -n backend job/secret-rotation-xxxxx
   
   # Check CronJob status
   kubectl describe cronjob -n backend secret-rotation
   ```

## Next Steps

After configuring ConfigMaps and Secrets, proceed to [ECR Integration](10-ecr-integration.md) to set up container image management. 