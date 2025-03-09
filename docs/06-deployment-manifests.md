# Deployment Manifests

This document outlines the deployment configurations for our backend services in the k3s cluster.

## Prerequisites

- Namespaces created as described in [Namespace Creation](05-namespace-creation.md)
- ECR repositories set up for both services
- Storage configuration completed as described in [Storage Configuration](03-storage-configuration.md)

## Deployment Structure

We'll create separate deployment manifests for each service:
1. Go Server (Main backend)
2. Helper Server (Import trades handler)

## Go Server Deployment

### 1. Create ConfigMap for Go Server

Create `go-server-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: go-server-config
  namespace: backend
data:
  # Add any environment-specific configuration
  SERVER_PORT: "9000"
  # Add other configuration key-value pairs as needed
```

### 2. Create Go Server Deployment

Create `go-server-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
  namespace: backend
  labels:
    app: go-server
spec:
  replicas: 1  # Single replica for vertical scaling
  selector:
    matchLabels:
      app: go-server
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: go-server
    spec:
      serviceAccountName: backend-sa
      containers:
      - name: go-server
        image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/go-server:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 9000
          name: http
        envFrom:
        - configMapRef:
            name: go-server-config
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: data
          mountPath: /app/pb_data
        readinessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 15
          periodSeconds: 20
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: go-server-data
```

### 3. Create Go Server Service

Create `go-server-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: go-server
  namespace: backend
  labels:
    app: go-server
spec:
  type: ClusterIP
  ports:
  - port: 9000
    targetPort: 9000
    protocol: TCP
    name: http
  selector:
    app: go-server
```

## Helper Server Deployment

### 1. Create ConfigMap for Helper Server

Create `helper-server-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: helper-server-config
  namespace: backend
data:
  PORT: "8080"
  MAIN_SERVER_URL: "http://go-server:9000"
```

### 2. Create Helper Server Deployment

Create `helper-server-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helper-server
  namespace: backend
  labels:
    app: helper-server
spec:
  replicas: 1  # Single replica for vertical scaling
  selector:
    matchLabels:
      app: helper-server
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: helper-server
    spec:
      serviceAccountName: backend-sa
      containers:
      - name: helper-server
        image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/helper-server:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
        envFrom:
        - configMapRef:
            name: helper-server-config
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
```

### 3. Create Helper Server Service

Create `helper-server-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: helper-server
  namespace: backend
  labels:
    app: helper-server
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: helper-server
```

## Applying the Manifests

Apply the configurations in the following order:

```bash
# Apply ConfigMaps first
kubectl apply -f go-server-config.yaml
kubectl apply -f helper-server-config.yaml

# Apply Deployments
kubectl apply -f go-server-deployment.yaml
kubectl apply -f helper-server-deployment.yaml

# Apply Services
kubectl apply -f go-server-service.yaml
kubectl apply -f helper-server-service.yaml
```

## Verification

### 1. Check Deployments

```bash
# Check deployment status
kubectl get deployments -n backend

# Check pods
kubectl get pods -n backend

# Check pod logs
kubectl logs -n backend -l app=go-server
kubectl logs -n backend -l app=helper-server
```

### 2. Check Services

```bash
# Verify services
kubectl get services -n backend

# Test service DNS resolution
kubectl run -n backend test-dns --image=busybox -i --rm --restart=Never -- nslookup go-server
```

### 3. Check Resource Usage

```bash
# Check resource consumption
kubectl top pods -n backend

# View detailed pod information
kubectl describe pods -n backend -l app=go-server
kubectl describe pods -n backend -l app=helper-server
```

## Scaling Considerations

For vertical scaling:

1. **Resource Adjustment**:
   ```bash
   # Edit deployment to increase resources
   kubectl edit deployment -n backend go-server
   ```

2. **Node Capacity**:
   ```bash
   # Check node resource usage
   kubectl describe node
   kubectl top node
   ```

## Troubleshooting

### Common Issues

1. **Image Pull Errors**:
   ```bash
   # Check pod events
   kubectl describe pod -n backend <pod-name>
   
   # Verify ECR credentials
   kubectl get secret -n backend ecr-secret
   ```

2. **Resource Constraints**:
   ```bash
   # Check resource quotas
   kubectl describe resourcequota -n backend
   
   # Check current resource usage
   kubectl top pods -n backend
   ```

3. **Readiness/Liveness Probe Failures**:
   ```bash
   # Check pod events
   kubectl describe pod -n backend <pod-name>
   
   # Check pod logs
   kubectl logs -n backend <pod-name>
   ```

## Best Practices

1. **Resource Management**:
   - Set appropriate resource requests and limits
   - Monitor resource usage regularly
   - Plan for vertical scaling needs

2. **High Availability**:
   - Use readiness/liveness probes
   - Implement proper error handling
   - Set appropriate restart policies

3. **Security**:
   - Use specific service accounts
   - Implement network policies
   - Keep container images updated

## Next Steps

After setting up the deployments, proceed to [Service Definitions](07-service-definitions.md) for detailed service configuration. 