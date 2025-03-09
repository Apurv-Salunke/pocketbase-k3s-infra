#!/bin/bash

# K3s Installation Script
# This script installs and configures k3s on the EC2 instance

set -e

# Configuration
K3S_VERSION="v1.28.4+k3s2"  # Specify k3s version
INSTALL_K3S_EXEC="server"    # Run as server
KUBECONFIG_DIR="/etc/rancher/k3s"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/k3s.yaml"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Installing required packages..."
apt-get update
apt-get install -y curl unzip jq

echo "Installing k3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - \
    --disable traefik \
    --write-kubeconfig-mode 644 \
    --tls-san $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
until kubectl get nodes | grep -q "Ready"; do
    sleep 5
    echo "Still waiting..."
done

echo "Configuring k3s..."

# Create namespaces
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -

# Configure containerd
cat > /etc/rancher/k3s/registries.yaml << EOF
mirrors:
  docker.io:
    endpoint:
      - "https://registry-1.docker.io"
configs:
  "docker.io":
    auth:
      username: ""  # Add your Docker Hub username if needed
      password: ""  # Add your Docker Hub password if needed
EOF

# Restart k3s to apply containerd config
systemctl restart k3s

# Install helm
echo "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Save cluster information
echo "Saving cluster information..."
mkdir -p /root/.kube
cp ${KUBECONFIG_FILE} /root/.kube/config
chmod 600 /root/.kube/config

# Get cluster info
echo "Cluster Information:"
kubectl cluster-info
kubectl get nodes -o wide

# Create test deployment
echo "Creating test deployment..."
kubectl create deployment nginx-test --image=nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment nginx-test --port=80 --dry-run=client -o yaml | kubectl apply -f -

# Wait for test deployment
echo "Waiting for test deployment..."
kubectl rollout status deployment/nginx-test

# Verify test deployment
echo "Verifying test deployment..."
kubectl get pods -l app=nginx-test
kubectl get svc nginx-test

# Clean up test deployment
echo "Cleaning up test deployment..."
kubectl delete deployment nginx-test
kubectl delete svc nginx-test

echo "K3s installation completed successfully!"
echo "Cluster is ready for use"

# Save cluster configuration for external access
echo "Saving cluster configuration..."
cat > k3s-cluster.conf << EOF
K3S_VERSION=${K3S_VERSION}
KUBECONFIG=${KUBECONFIG_FILE}
SERVER_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
NODE_NAME=$(hostname)
EOF

# Output important information
echo "==============================================="
echo "K3s Cluster Information:"
echo "Version: ${K3S_VERSION}"
echo "Server IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Kubeconfig: ${KUBECONFIG_FILE}"
echo "To use kubectl externally, copy the kubeconfig file and update the server IP"
echo "===============================================" 