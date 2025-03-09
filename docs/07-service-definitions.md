# Service Definitions and Configuration

This document provides detailed service configurations for our backend services in the k3s cluster, expanding on the basic service definitions from our deployment manifests.

## Prerequisites

- Deployments created as described in [Deployment Manifests](06-deployment-manifests.md)
- NGINX Ingress Controller installed as described in [Networking Setup](04-networking-setup.md)
- Namespaces and network policies configured

## Service Architecture

Our service architecture consists of:

1. Internal Services:
   - Go Server (Main backend)
   - Helper Server (Import trades handler)

2. External Access:
   - NGINX Ingress Controller
   - TLS termination
   - Load balancing

## Enhanced Service Definitions

### Go Server Service

Create `go-server-service-enhanced.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: go-server
  namespace: backend
  labels:
    app: go-server
    service: main-backend
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9000"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  sessionAffinity: ClientIP  # Maintain session affinity
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800  # 3 hours
  ports:
  - name: http
    port: 9000
    targetPort: http
    protocol: TCP
  - name: metrics
    port: 9100
    targetPort: metrics
    protocol: TCP
  selector:
    app: go-server
```

### Helper Server Service

Create `helper-server-service-enhanced.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: helper-server
  namespace: backend
  labels:
    app: helper-server
    service: import-handler
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8080
    targetPort: http
    protocol: TCP
  - name: metrics
    port: 9100
    targetPort: metrics
    protocol: TCP
  selector:
    app: helper-server
```

## Service Endpoints Configuration

### 1. Create Endpoints Health Check

Create `service-healthcheck.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: service-healthcheck
  namespace: backend
data:
  check-endpoints.sh: |
    #!/bin/sh
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://go-server:9000/health)
    if [ "$http_code" -ne 200 ]; then
      exit 1
    fi
```

### 2. Create Service Monitor

Create `service-monitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-services
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      service: main-backend
  namespaceSelector:
    matchNames:
      - backend
  endpoints:
  - port: metrics
    interval: 15s
```

## Service Mesh Integration (Optional)

If you decide to add service mesh capabilities later, here's the configuration:

### 1. Create Service Policy

Create `service-policy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: service-communication
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: helper-server
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: go-server
    ports:
    - protocol: TCP
      port: 9000
```

## Service Discovery and DNS

### 1. Configure CoreDNS Custom Entries

Create `coredns-custom.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  server.override: |
    backend.svc.cluster.local:53 {
        errors
        cache 30
        forward . /etc/resolv.conf
        reload
    }
```

## Load Balancing Configuration

### 1. Internal Load Balancing

The ClusterIP services automatically provide internal load balancing. For advanced configuration:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: go-server-lb
  namespace: backend
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 9000
    targetPort: http
  selector:
    app: go-server
```

## Applying the Configurations

```bash
# Apply enhanced service definitions
kubectl apply -f go-server-service-enhanced.yaml
kubectl apply -f helper-server-service-enhanced.yaml

# Apply health checks
kubectl apply -f service-healthcheck.yaml

# Apply service monitor
kubectl apply -f service-monitor.yaml

# Apply network policies
kubectl apply -f service-policy.yaml

# Apply CoreDNS configuration
kubectl apply -f coredns-custom.yaml
```

## Service Verification

### 1. Check Service Status

```bash
# Check service endpoints
kubectl get endpoints -n backend

# Verify service DNS resolution
kubectl run -n backend test-dns --image=busybox -i --rm --restart=Never -- nslookup go-server.backend.svc.cluster.local

# Test service connectivity
kubectl run -n backend test-curl --image=curlimages/curl -i --rm --restart=Never -- curl -v http://go-server:9000/health
```

### 2. Monitor Service Health

```bash
# Check service metrics
kubectl port-forward -n backend svc/go-server 9100:9100

# In another terminal
curl localhost:9100/metrics
```

### 3. Test Load Balancing

```bash
# Watch service endpoints
kubectl get endpoints -n backend -w

# Test load distribution
for i in $(seq 1 10); do
  kubectl run -n backend test-$i --image=curlimages/curl -i --rm --restart=Never -- \
    curl -s http://go-server:9000/health
done
```

## Troubleshooting

### Common Issues

1. **Service Discovery Issues**:
   ```bash
   # Check DNS resolution
   kubectl run -n backend debug --image=busybox -it --rm -- nslookup go-server

   # Check service endpoints
   kubectl describe endpoints -n backend go-server
   ```

2. **Load Balancing Issues**:
   ```bash
   # Check service configuration
   kubectl describe service -n backend go-server

   # Check endpoint distribution
   kubectl get endpoints -n backend go-server -o yaml
   ```

3. **Network Policy Issues**:
   ```bash
   # Test inter-service communication
   kubectl run -n backend test --image=curlimages/curl -i --rm -- \
     curl -v http://helper-server:8080/health
   ```

## Best Practices

1. **Service Naming and Labels**:
   - Use consistent naming conventions
   - Apply meaningful labels for service discovery
   - Document service dependencies

2. **Health Checks**:
   - Implement comprehensive health checks
   - Set appropriate timeouts and intervals
   - Monitor service health metrics

3. **Load Balancing**:
   - Configure appropriate session affinity
   - Set reasonable timeouts
   - Monitor load distribution

4. **Security**:
   - Restrict service access using network policies
   - Use TLS for sensitive communications
   - Regularly audit service access patterns

## Next Steps

After configuring services, proceed to [Ingress Configuration](08-ingress-configuration.md) to set up external access to your services. 