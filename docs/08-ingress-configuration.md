# Ingress Configuration

This document outlines the configuration of ingress resources for external access to our backend services using NGINX Ingress Controller.

## Prerequisites

- NGINX Ingress Controller installed as described in [Networking Setup](04-networking-setup.md)
- Services configured as described in [Service Definitions](07-service-definitions.md)
- TLS certificates managed by cert-manager
- Domain name configured to point to your EC2 instance

## Ingress Architecture

Our ingress configuration will:
1. Route traffic to appropriate backend services
2. Handle TLS termination
3. Implement path-based routing
4. Configure rate limiting and security headers

## Base Ingress Configuration

### 1. Create TLS Secret

First, ensure cert-manager has created the TLS secret:

```bash
# Check if certificate is ready
kubectl get certificate -n backend

# Check if secret exists
kubectl get secret -n backend api-tls
```

### 2. Create Main Ingress Configuration

Create `backend-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
  namespace: backend
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    
    # Security headers
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    
    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
    
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-rpm: "100"
    
    # Enable CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
    
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

### 3. Create Rate Limiting Configuration

Create `rate-limit.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-rate-limit
  namespace: ingress-nginx
data:
  proxy-connect-timeout: "10"
  proxy-read-timeout: "120"
  proxy-send-timeout: "120"
  limit-req-status-code: "429"
  limit-conn-status-code: "429"
  custom-http-errors: "429,503"
```

### 4. Create Custom Error Pages

Create `custom-errors.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-custom-errors
  namespace: ingress-nginx
data:
  429.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Rate Limit Exceeded</title></head>
    <body>
      <h1>Too Many Requests</h1>
      <p>Please try again later.</p>
    </body>
    </html>
  503.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Service Temporarily Unavailable</title></head>
    <body>
      <h1>Service Unavailable</h1>
      <p>Please try again later.</p>
    </body>
    </html>
```

## Advanced Configurations

### 1. Create IP Whitelist for Admin Endpoints

Create `admin-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: admin-ingress
  namespace: backend
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/whitelist-source-range: "YOUR_OFFICE_IP/32,YOUR_VPN_IP/32"
spec:
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /admin
        pathType: Prefix
        backend:
          service:
            name: go-server
            port:
              number: 9000
```

### 2. Configure Sticky Sessions (If Needed)

Create `sticky-session-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sticky-session-ingress
  namespace: backend
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "SERVERID"
    nginx.ingress.kubernetes.io/session-cookie-expires: "172800"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"
spec:
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /sticky
        pathType: Prefix
        backend:
          service:
            name: go-server
            port:
              number: 9000
```

## Applying the Configurations

```bash
# Apply main ingress configuration
kubectl apply -f backend-ingress.yaml

# Apply rate limiting configuration
kubectl apply -f rate-limit.yaml

# Apply custom error pages
kubectl apply -f custom-errors.yaml

# Apply admin ingress (if needed)
kubectl apply -f admin-ingress.yaml

# Apply sticky session configuration (if needed)
kubectl apply -f sticky-session-ingress.yaml
```

## Verification

### 1. Check Ingress Status

```bash
# Check ingress status
kubectl get ingress -n backend

# Check detailed configuration
kubectl describe ingress backend-ingress -n backend

# Check TLS certificate
kubectl get certificate -n backend
```

### 2. Test External Access

```bash
# Test main endpoint
curl -v https://api.yourdomain.com/health

# Test import trades endpoint
curl -v https://api.yourdomain.com/api/import-trades

# Test rate limiting
for i in $(seq 1 20); do
  curl -v https://api.yourdomain.com/health
done
```

### 3. Monitor Ingress Logs

```bash
# Get NGINX Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Monitor real-time logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

## Troubleshooting

### Common Issues

1. **Certificate Issues**:
   ```bash
   # Check cert-manager logs
   kubectl logs -n cert-manager -l app=cert-manager
   
   # Check certificate status
   kubectl describe certificate -n backend api-tls
   ```

2. **Routing Issues**:
   ```bash
   # Check NGINX configuration
   kubectl exec -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -- nginx -T
   
   # Test internal service access
   kubectl run -n backend test-curl --image=curlimages/curl -i --rm -- curl http://go-server:9000/health
   ```

3. **Rate Limiting Issues**:
   ```bash
   # Check rate limit configuration
   kubectl get configmap -n ingress-nginx nginx-rate-limit -o yaml
   
   # Monitor rate limit metrics
   kubectl exec -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -- wget -qO- http://localhost:10254/metrics
   ```

## Best Practices

1. **Security**:
   - Always use TLS
   - Implement appropriate rate limiting
   - Use secure headers
   - Whitelist admin endpoints

2. **Performance**:
   - Configure appropriate timeouts
   - Monitor resource usage
   - Use caching when appropriate

3. **Monitoring**:
   - Monitor ingress logs
   - Set up alerts for certificate expiration
   - Track rate limiting metrics

## Next Steps

After configuring ingress, proceed to [ConfigMaps and Secrets](09-configmaps-secrets.md) to manage application configuration and sensitive data. 