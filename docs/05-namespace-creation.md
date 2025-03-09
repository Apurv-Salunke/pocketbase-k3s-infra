# Namespace Creation and Organization

This document outlines how we'll organize our Kubernetes resources using namespaces for our production backend deployment.

## Overview

We'll create separate namespaces to logically isolate different components of our application:

1. `backend` - For our main application services (go-server and helper-server)
2. `monitoring` - For monitoring tools
3. `ingress-nginx` - Already created for NGINX Ingress Controller
4. `cert-manager` - Already created for certificate management

## Creating Namespaces

### 1. Create the Namespace Manifests

Create a file named `namespaces.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: backend
  labels:
    name: backend
    environment: production
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
    environment: production
```

### 2. Apply the Namespaces

```bash
kubectl apply -f namespaces.yaml
```

## Resource Quotas

Let's set resource quotas for our namespaces to ensure proper resource allocation.

### 1. Create Resource Quotas

Create a file named `resource-quotas.yaml`:

```yaml
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: backend-quota
  namespace: backend
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 2Gi
    limits.cpu: "2"
    limits.memory: 4Gi
    pods: "10"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: monitoring-quota
  namespace: monitoring
spec:
  hard:
    requests.cpu: "500m"
    requests.memory: 1Gi
    limits.cpu: "1"
    limits.memory: 2Gi
    pods: "5"
```

### 2. Apply Resource Quotas

```bash
kubectl apply -f resource-quotas.yaml
```

## LimitRanges

Set default resource limits for pods in each namespace.

### 1. Create LimitRange Manifests

Create a file named `limit-ranges.yaml`:

```yaml
---
apiVersion: v1
kind: LimitRange
metadata:
  name: backend-limits
  namespace: backend
spec:
  limits:
  - default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
---
apiVersion: v1
kind: LimitRange
metadata:
  name: monitoring-limits
  namespace: monitoring
spec:
  limits:
  - default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

### 2. Apply LimitRanges

```bash
kubectl apply -f limit-ranges.yaml
```

## Network Policies

Update network policies to work with our new namespace structure.

### 1. Create Network Policies

Create a file named `namespace-network-policies.yaml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
```

### 2. Apply Network Policies

```bash
kubectl apply -f namespace-network-policies.yaml
```

## Service Accounts

Create service accounts for each namespace.

### 1. Create Service Account Manifests

Create a file named `service-accounts.yaml`:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: backend
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-sa
  namespace: monitoring
```

### 2. Apply Service Accounts

```bash
kubectl apply -f service-accounts.yaml
```

## Verification and Monitoring

### 1. Verify Namespace Creation

```bash
# List all namespaces
kubectl get namespaces

# View namespace details
kubectl describe namespace backend
kubectl describe namespace monitoring
```

### 2. Check Resource Quotas

```bash
# View resource quotas
kubectl get resourcequota -A
kubectl describe resourcequota backend-quota -n backend
```

### 3. Check LimitRanges

```bash
# View limit ranges
kubectl get limitrange -A
kubectl describe limitrange backend-limits -n backend
```

### 4. Verify Network Policies

```bash
# View network policies
kubectl get networkpolicy -A
```

## Best Practices

1. **Namespace Naming**:
   - Use clear, descriptive names
   - Add environment labels (production, staging, etc.)
   - Use consistent naming conventions

2. **Resource Management**:
   - Regularly monitor resource usage
   - Adjust quotas based on actual usage
   - Set appropriate limits for your workload

3. **Security**:
   - Use network policies to restrict communication
   - Create separate service accounts for different components
   - Follow principle of least privilege

## Troubleshooting

### Common Issues

1. **Resource Quota Exceeded**:
   ```bash
   # Check current resource usage
   kubectl describe namespace backend
   kubectl top pods -n backend
   ```

2. **Network Policy Issues**:
   ```bash
   # Test communication between namespaces
   kubectl run test-pod -n backend --image=busybox -- sleep 3600
   kubectl exec -it test-pod -n backend -- wget -qO- http://service.monitoring
   ```

3. **Service Account Issues**:
   ```bash
   # Verify service account
   kubectl get serviceaccount -n backend
   kubectl describe serviceaccount backend-sa -n backend
   ```

## Next Steps

After setting up namespaces, proceed to [Deployment Manifests](06-deployment-manifests.md) to create the actual deployment configurations for our services. 