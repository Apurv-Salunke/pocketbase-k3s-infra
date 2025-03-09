# Application Deployment Testing Guide

This guide outlines the testing procedures for deploying the core application components.

## Prerequisites

1. Successful completion of infrastructure setup
2. Access to the k3s cluster
3. kubectl configured with cluster access
4. Docker images pushed to registry

## Testing Steps

### 1. Initial Verification

1. Check cluster access:
```bash
kubectl cluster-info
kubectl get nodes
```

2. Verify namespaces:
```bash
kubectl get namespaces
kubectl config set-context --current --namespace=backend
```

### 2. Storage Setup Testing

1. Verify storage class:
```bash
kubectl get storageclass
kubectl describe storageclass local-path
```

2. Test PVC creation:
```bash
kubectl apply -f kubernetes/deployments/go-server.yaml
kubectl get pvc -n backend
kubectl describe pvc go-server-data -n backend
```

### 3. Application Deployment Testing

1. Deploy Go Server:
```bash
# Update image in go-server.yaml with your registry
kubectl apply -f kubernetes/deployments/go-server.yaml

# Verify deployment
kubectl get deployments -n backend
kubectl get pods -n backend -l app=go-server
kubectl get svc -n backend go-server
```

2. Deploy Helper Server:
```bash
# Update image in helper-server.yaml with your registry
kubectl apply -f kubernetes/deployments/helper-server.yaml

# Verify deployment
kubectl get deployments -n backend
kubectl get pods -n backend -l app=helper-server
kubectl get svc -n backend helper-server
```

3. Verify pod logs and health:
```bash
# Check Go Server logs
kubectl logs -n backend -l app=go-server

# Check Helper Server logs
kubectl logs -n backend -l app=helper-server

# Check pod health
kubectl describe pods -n backend -l app=go-server
kubectl describe pods -n backend -l app=helper-server
```

### 4. Ingress Setup Testing

1. Install NGINX Ingress Controller:
```bash
kubectl apply -f kubernetes/ingress/nginx-ingress.yaml
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc
```

2. Configure DNS:
```bash
# Get LoadBalancer IP/hostname
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update your DNS records accordingly
```

3. Deploy and test ingress rules:
```bash
# Update domain in ingress configuration
kubectl apply -f kubernetes/ingress/backend-ingress.yaml

# Verify ingress
kubectl get ingress -n backend
kubectl describe ingress -n backend backend-ingress
```

4. Test endpoints:
```bash
# Test main endpoint
curl -v https://api.yourdomain.com/health

# Test helper endpoint
curl -v https://api.yourdomain.com/api/import-trades/health
```

## Expected Results

### Application Deployments

1. Go Server:
   - [ ] Deployment shows 2/2 ready replicas
   - [ ] Pods are in Running state
   - [ ] Health checks passing
   - [ ] Service is created
   - [ ] PVC is bound

2. Helper Server:
   - [ ] Deployment shows 2/2 ready replicas
   - [ ] Pods are in Running state
   - [ ] Health checks passing
   - [ ] Service is created

### Networking

1. Ingress Controller:
   - [ ] Running on all nodes
   - [ ] LoadBalancer service created
   - [ ] SSL termination working

2. Ingress Rules:
   - [ ] Rules properly configured
   - [ ] Path-based routing working
   - [ ] TLS enabled
   - [ ] Services accessible

## Troubleshooting

### Common Issues

1. Pod Startup Issues:
```bash
# Check pod status
kubectl get pods -n backend
kubectl describe pod <pod-name> -n backend
kubectl logs <pod-name> -n backend
```

2. Storage Issues:
```bash
# Check PVC status
kubectl get pvc -n backend
kubectl describe pvc go-server-data -n backend

# Check PV status
kubectl get pv
kubectl describe pv <pv-name>
```

3. Ingress Issues:
```bash
# Check ingress controller
kubectl -n ingress-nginx logs -l app.kubernetes.io/name=ingress-nginx

# Check ingress status
kubectl describe ingress backend-ingress -n backend

# Test from within cluster
kubectl run curl --image=curlimages/curl -i --tty -- sh
```

## Validation Tests

### 1. Load Testing

```bash
# Install hey for load testing
go install github.com/rakyll/hey@latest

# Run load test
hey -n 1000 -c 50 https://api.yourdomain.com/health
```

### 2. Failover Testing

```bash
# Test pod failover
kubectl delete pod -n backend -l app=go-server --wait=false
watch kubectl get pods -n backend

# Test node failover (if multiple nodes)
kubectl drain <node-name> --ignore-daemonsets
```

### 3. Scaling Testing

```bash
# Test scaling
kubectl scale deployment go-server -n backend --replicas=4
kubectl get pods -n backend -w
```

## Next Steps

After successful testing:

1. Document any configuration changes made
2. Update image versions in manifests
3. Configure monitoring (next phase)
4. Setup CI/CD pipelines 