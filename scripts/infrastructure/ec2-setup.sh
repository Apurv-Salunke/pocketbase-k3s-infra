#!/bin/bash

# EC2 Instance Setup Script for K3s Deployment
# This script creates the necessary AWS infrastructure for k3s deployment

set -e

# Configuration
INSTANCE_TYPE="t3.medium"  # Minimum 2 CPU, 4GB RAM recommended for k3s
VOLUME_SIZE="30"          # GB
AMI_ID="ami-0a3c3a20c09d6f377"  # Ubuntu 22.04 LTS in us-east-1
KEY_NAME="k3s-key"
SECURITY_GROUP_NAME="k3s-sg"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
INSTANCE_NAME="k3s-server"
AWS_REGION="us-east-1"

# Set AWS region
aws configure set default.region $AWS_REGION

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=k3s-vpc}]" \
    --query 'Vpc.VpcId' \
    --output text)

# Enable DNS hostname for the VPC
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames '{"Value":true}'

echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=k3s-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID

echo "Creating Subnet..."
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET_CIDR \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=k3s-subnet}]" \
    --query 'Subnet.SubnetId' \
    --output text)

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_ID \
    --map-public-ip-on-launch

echo "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=k3s-rt}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

# Create route to Internet Gateway
aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

# Associate route table with subnet
aws ec2 associate-route-table \
    --route-table-id $ROUTE_TABLE_ID \
    --subnet-id $SUBNET_ID

echo "Creating Security Group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name $SECURITY_GROUP_NAME \
    --description "Security group for k3s server" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

# Tag security group
aws ec2 create-tags \
    --resources $SECURITY_GROUP_ID \
    --tags "Key=Name,Value=k3s-sg"

# Add security group rules
echo "Configuring Security Group Rules..."

# SSH access
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# HTTP access
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

# HTTPS access
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

# Kubernetes API server
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 6443 \
    --cidr 0.0.0.0/0

# Create key pair if it doesn't exist
if ! aws ec2 describe-key-pairs --key-names $KEY_NAME >/dev/null 2>&1; then
    echo "Creating new key pair..."
    aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --query 'KeyMaterial' \
        --output text > ${KEY_NAME}.pem
    chmod 400 ${KEY_NAME}.pem
fi

echo "Launching EC2 Instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --subnet-id $SUBNET_ID \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get instance public IP
INSTANCE_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Creating Elastic IP..."
ELASTIC_IP=$(aws ec2 allocate-address \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=k3s-eip}]" \
    --query 'AllocationId' \
    --output text)

# Associate Elastic IP with instance
aws ec2 associate-address \
    --allocation-id $ELASTIC_IP \
    --instance-id $INSTANCE_ID

# Get the new Elastic IP address
ELASTIC_IP_ADDRESS=$(aws ec2 describe-addresses \
    --allocation-ids $ELASTIC_IP \
    --query 'Addresses[0].PublicIp' \
    --output text)

# Output important information
echo "Infrastructure setup completed!"
echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID"
echo "Security Group ID: $SECURITY_GROUP_ID"
echo "Instance ID: $INSTANCE_ID"
echo "Elastic IP: $ELASTIC_IP_ADDRESS"
echo "Key Pair: $KEY_NAME"
echo ""
echo "You can connect to your instance using:"
echo "ssh -i ${KEY_NAME}.pem ubuntu@$ELASTIC_IP_ADDRESS"

# Save configuration for future use
cat > k3s-infrastructure.conf << EOF
VPC_ID=$VPC_ID
SUBNET_ID=$SUBNET_ID
SECURITY_GROUP_ID=$SECURITY_GROUP_ID
INSTANCE_ID=$INSTANCE_ID
ELASTIC_IP=$ELASTIC_IP
ELASTIC_IP_ADDRESS=$ELASTIC_IP_ADDRESS
KEY_NAME=$KEY_NAME
EOF 