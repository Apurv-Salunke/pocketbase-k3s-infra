# K3s Installation on EC2

This document outlines the process of installing and configuring K3s on the EC2 instance for our production backend deployment.

## Prerequisites

- EC2 instance provisioned as described in [EC2 Instance Provisioning](01-ec2-instance-provisioning.md)
- SSH access to the EC2 instance
- Proper security groups configured

## Installation Steps

### 1. Basic K3s Installation

K3s can be installed with a simple one-line command. For a single-node setup (which is what we're using for vertical scaling):

```bash
# Install K3s as a server
curl -sfL https://get.k3s.io | sh -

# Check the status of K3s
sudo systemctl status k3s

# Verify the node is ready
sudo kubectl get nodes
```

### 2. Configuration Options

For our production environment, we'll want to customize the K3s installation. Create a configuration file:

```bash
sudo mkdir -p /etc/rancher/k3s
sudo vim /etc/rancher/k3s/config.yaml
```

Add the following configuration:

```yaml
# K3s configuration
write-kubeconfig-mode: "0644"
tls-san:
  - "<YOUR_DOMAIN_NAME>"
  - "<YOUR_EC2_PUBLIC_IP>"
disable:
  - traefik  # We'll install NGINX Ingress Controller later
  - servicelb # We'll use a different load balancer
node-label:
  - "node-role.kubernetes.io/master=true"
```

### 3. Install K3s with Custom Configuration

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--config=/etc/rancher/k3s/config.yaml" sh -
```

### 4. Set Up kubectl Access

```bash
# Copy the kubeconfig file to your local machine
mkdir -p ~/.kube
scp user@<EC2_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update the server address in the kubeconfig
sed -i '' "s/127.0.0.1/<EC2_PUBLIC_IP>/g" ~/.kube/config

# Test the connection
kubectl get nodes
```

## Containerd Configuration

K3s uses containerd as its container runtime. To configure it to work with ECR:

```bash
# Create the containerd config directory
sudo mkdir -p /etc/rancher/k3s/containerd

# Create a configuration file
sudo vim /etc/rancher/k3s/containerd/config.toml
```

Add the following configuration:

```toml
[plugins.cri.registry.mirrors]
  [plugins.cri.registry.mirrors."<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com"]
    endpoint = ["https://<AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com"]
```

Restart K3s to apply the changes:

```bash
sudo systemctl restart k3s
```

## Authentication and Access Control

### 1. Create a Service Account for CI/CD

```bash
# Create a service account
kubectl create serviceaccount cicd

# Create a cluster role binding
kubectl create clusterrolebinding cicd-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=default:cicd

# Get the token
kubectl create token cicd --duration=8760h
```

Save this token securely for use in your CI/CD pipeline.

### 2. Set Up AWS ECR Authentication

Create a Kubernetes secret for ECR authentication:

```bash
# Install AWS CLI if not already installed
sudo apt-get install -y awscli

# Configure AWS credentials
aws configure

# Create a script to refresh ECR credentials
cat > /usr/local/bin/ecr-login.sh << 'EOF'
#!/bin/bash
aws ecr get-login-password --region <AWS_REGION> | \
kubectl create secret docker-registry ecr-secret \
  --docker-server=<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region <AWS_REGION>) \
  --dry-run=client -o yaml | kubectl apply -f -
EOF

# Make the script executable
chmod +x /usr/local/bin/ecr-login.sh

# Run the script
/usr/local/bin/ecr-login.sh

# Set up a cron job to refresh the credentials
(crontab -l 2>/dev/null; echo "0 */6 * * * /usr/local/bin/ecr-login.sh") | crontab -
```

## Verification

Verify that K3s is running correctly:

```bash
# Check the status of K3s
sudo systemctl status k3s

# Check the nodes
kubectl get nodes

# Check the pods in all namespaces
kubectl get pods --all-namespaces
```

## Troubleshooting

### Common Issues

1. **K3s fails to start**:
   - Check the logs: `sudo journalctl -u k3s`
   - Verify system resources: `free -m` and `df -h`

2. **Cannot connect to the Kubernetes API**:
   - Check if the API server is running: `sudo netstat -tulpn | grep 6443`
   - Verify security group rules allow access to port 6443

3. **Container images cannot be pulled**:
   - Check ECR authentication: `