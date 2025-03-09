# EC2 Instance Provisioning for K3s Deployment

This document outlines the process of provisioning an EC2 instance for our k3s-based production backend deployment.

## Instance Selection

### Recommended Instance Type
- **Instance Type**: t3.large (2 vCPU, 8 GB RAM)
  - This provides a good balance of compute and memory for our workload
  - Can be upgraded to t3.xlarge if needed for vertical scaling

### Storage Configuration
- **Root Volume**: 30 GB gp3 SSD
- **Data Volume**: 100 GB gp3 SSD (for persistent data)
  - Mount point: `/var/lib/rancher/k3s` for k3s data
  - Mount point: `/data` for application data

## Security Configuration

### Security Groups
Create a security group with the following inbound rules:
- SSH (TCP 22) - Restricted to your IP address or VPN
- HTTP (TCP 80) - Open to all
- HTTPS (TCP 443) - Open to all
- K3s API (TCP 6443) - Restricted to your IP address or VPN

### IAM Role
Create an IAM role with the following permissions:
- AmazonEC2ContainerRegistryReadOnly (for pulling images from ECR)
- Custom policy for any additional AWS services you might need

## Network Configuration

### Elastic IP
- Allocate an Elastic IP and associate it with the EC2 instance
- This ensures a stable public IP address for your domain

### DNS Configuration
- Create an A record in your DNS provider pointing to the Elastic IP
- Consider setting up a subdomain specifically for your backend (e.g., api.yourdomain.com)

## Instance Setup Commands

```bash
# Update the system
sudo apt-get update && sudo apt-get upgrade -y

# Install necessary packages
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# Set up the data volume (assuming it's attached as /dev/xvdf)
sudo mkfs -t ext4 /dev/xvdf
sudo mkdir -p /data
sudo mount /dev/xvdf /data
echo '/dev/xvdf /data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Set up swap (optional, but recommended)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Security Hardening

- Disable password authentication for SSH
- Configure automatic security updates
- Install and configure fail2ban
- Set up a firewall using UFW or iptables

## Next Steps

After provisioning the EC2 instance, proceed to [K3s Installation](02-k3s-installation.md). 