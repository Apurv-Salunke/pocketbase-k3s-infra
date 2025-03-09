# Networking Setup for K3s

This document outlines the process of configuring networking for our k3s-based production backend deployment, focusing on setting up NGINX Ingress Controller and configuring TLS.

## Prerequisites

- EC2 instance with K3s installed as described in [K3s Installation](02-k3s-installation.md)
- Domain name pointing to your EC2 instance's Elastic IP
- Storage configured as described in [Storage Configuration](03-storage-configuration.md)

## Installing NGINX Ingress Controller

Since we disabled the built-in Traefik during K3s installation, we'll install NGINX Ingress Controller. We'll use Helm for this installation.

### 1. Install Helm

```bash
# Download and install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### 2. Add NGINX Ingress Helm Repository

```bash
# Add the NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### 3. Create NGINX Values File

Create a file named `nginx-values.yaml` with the following content:

```yaml
# NGINX Ingress Controller configuration
controller:
  kind: DaemonSet  # Use DaemonSet for single-node setup
  resources:
    requests:
      cpu: 100m
      memory: 90Mi
    limits:
      cpu: 200m
      memory: 180Mi
  
  config:
    use-forwarded-headers: "true"
    proxy-body-size: "50m"
    proxy-buffer-size: "16k"
    client-header-buffer-size: "1k"
    
  service:
    enabled: true
    type: LoadBalancer
    externalTrafficPolicy: Local
    
  metrics:
    enabled: true
    
  admissionWebhooks:
    enabled: false  # Disable for reduced resource usage

  # Reduce replica count since we're using vertical scaling
  replicaCount: 1
  
  # Configure default SSL certificate
  extraArgs:
    default-ssl-certificate: "default/tls-secret"
```

### 4. Install NGINX Ingress Controller

```bash
# Install NGINX Ingress Controller using Helm
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f nginx-values.yaml
```

### 5. Set Up TLS Certificate Management

We'll use cert-manager for automatic TLS certificate management:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## Configuring DNS and TLS

### 1. Verify NGINX Service

```bash
# Check if NGINX Ingress Controller is running
kubectl get pods -n ingress-nginx

# Get the external IP/hostname
kubectl get svc -n ingress-nginx
```

### 2. Create Ingress Resources for Your Services

Create a file named `ingress.yaml` with the following content:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  tls:
  - hosts:
    - api.yourdomain.com
    secretName: api-tls
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: go-server
            port:
              number: 9000
      - path: /api/import-trades
        pathType: Prefix
        backend:
          service:
            name: helper-server
            port:
              number: 8080
```

Apply the ingress configuration:

```bash
kubectl apply -f ingress.yaml
```

## Network Policies

For added security, let's create network policies to restrict traffic between pods:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-go-server
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: go-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 9000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-helper-server
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: helper-server
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: go-server
    ports:
    - protocol: TCP
      port: 9000
```

Apply the network policies:

```bash
kubectl apply -f network-policy.yaml
```

## Performance Monitoring

Monitor NGINX Ingress Controller performance:

```bash
# Check NGINX metrics
kubectl get pods -n ingress-nginx
kubectl port-forward -n ingress-nginx <nginx-controller-pod> 9113:9113

# In another terminal:
curl localhost:9113/metrics

# Monitor access logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --follow

# Check resource usage
kubectl top pods -n ingress-nginx
```

## Troubleshooting

### Common Issues

1. **Certificate Issues**:
   ```bash
   # Check cert-manager logs
   kubectl logs -n cert-manager -l app=cert-manager
   
   # Check certificate status
   kubectl get certificates,certificaterequests
   ```

2. **Ingress Not Working**:
   ```bash
   # Check NGINX Ingress Controller logs
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
   
   # Check ingress status
   kubectl describe ingress backend-ingress
   ```

3. **Network Policy Issues**:
   ```bash
   # Temporarily disable network policies to test
   kubectl delete networkpolicy --all
   
   # Check pod labels
   kubectl get pods --show-labels
   ```

## Resource Usage Optimization

NGINX Ingress Controller is configured with minimal resource requirements:
- Initial CPU request: 100m (0.1 core)
- Initial memory request: 90Mi
- CPU limit: 200m (0.2 core)
- Memory limit: 180Mi

Monitor these values and adjust based on actual usage:

```bash
# Monitor resource usage
kubectl top pods -n ingress-nginx
```

## Next Steps

After setting up networking, proceed to [Namespace Creation](05-namespace-creation.md) to organize your Kubernetes resources. 