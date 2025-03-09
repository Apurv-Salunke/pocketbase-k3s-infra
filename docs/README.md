# K3s Production Deployment Documentation

This folder contains comprehensive documentation for deploying our production backend using k3s on AWS EC2.

## Deployment Phases

### Phase 1: Infrastructure Setup

1. [EC2 Instance Provisioning](01-ec2-instance-provisioning.md)
2. [K3s Installation](02-k3s-installation.md)
3. [Storage Configuration](03-storage-configuration.md)
4. [Networking Setup](04-networking-setup.md)

### Phase 2: Kubernetes Resource Definition

1. [Namespace Creation](05-namespace-creation.md)
2. [Deployment Manifests](06-deployment-manifests.md)
3. [Service Definitions](07-service-definitions.md)
4. [Ingress Configuration](08-ingress-configuration.md)
5. [ConfigMaps and Secrets](09-configmaps-secrets.md)

### Phase 3: CI/CD Integration

1. [ECR Integration](10-ecr-integration.md)
2. [Deployment Automation](11-deployment-automation.md)

### Phase 4: Monitoring and Maintenance

1. Monitoring Setup (Coming soon)
2. Backup Strategy (Coming soon)
3. Update Strategy (Coming soon)

## Reference Architecture

Our deployment is based on the following services:
- Go Server (Main backend)
- Helper Server (Handles specific API endpoints)
- Traefik (Ingress controller and reverse proxy)

Each documentation file includes detailed instructions, commands, and configuration examples to help with the deployment process. 