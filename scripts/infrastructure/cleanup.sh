#!/bin/bash

# Cleanup script for k3s infrastructure
# This script removes all resources created by ec2-setup.sh

set -e

# Load configuration
if [ -f k3s-infrastructure.conf ]; then
    source k3s-infrastructure.conf
else
    echo "Configuration file not found. Please ensure k3s-infrastructure.conf exists."
    exit 1
fi

echo "Starting cleanup process..."

# Disassociate and release Elastic IP
if [ ! -z "$ELASTIC_IP" ]; then
    echo "Releasing Elastic IP..."
    aws ec2 disassociate-address --allocation-id $ELASTIC_IP
    aws ec2 release-address --allocation-id $ELASTIC_IP
fi

# Terminate EC2 instance
if [ ! -z "$INSTANCE_ID" ]; then
    echo "Terminating EC2 instance..."
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID
    echo "Waiting for instance termination..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
fi

# Delete security group
if [ ! -z "$SECURITY_GROUP_ID" ]; then
    echo "Deleting security group..."
    aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID
fi

# Delete route table associations and routes
if [ ! -z "$SUBNET_ID" ]; then
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.subnet-id,Values=$SUBNET_ID" \
        --query 'RouteTables[0].RouteTableId' \
        --output text)
    
    if [ ! -z "$ROUTE_TABLE_ID" ] && [ "$ROUTE_TABLE_ID" != "None" ]; then
        echo "Deleting route table associations..."
        ASSOCIATION_ID=$(aws ec2 describe-route-tables \
            --route-table-id $ROUTE_TABLE_ID \
            --query 'RouteTables[0].Associations[0].RouteTableAssociationId' \
            --output text)
        
        if [ ! -z "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
            aws ec2 disassociate-route-table --association-id $ASSOCIATION_ID
        fi
        
        echo "Deleting route table..."
        aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID
    fi
fi

# Delete subnet
if [ ! -z "$SUBNET_ID" ]; then
    echo "Deleting subnet..."
    aws ec2 delete-subnet --subnet-id $SUBNET_ID
fi

# Detach and delete internet gateway
if [ ! -z "$VPC_ID" ]; then
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text)
    
    if [ ! -z "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
        echo "Detaching and deleting internet gateway..."
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
    fi
fi

# Delete VPC
if [ ! -z "$VPC_ID" ]; then
    echo "Deleting VPC..."
    aws ec2 delete-vpc --vpc-id $VPC_ID
fi

# Delete key pair
if [ ! -z "$KEY_NAME" ]; then
    echo "Deleting key pair..."
    aws ec2 delete-key-pair --key-name $KEY_NAME
    rm -f ${KEY_NAME}.pem
fi

# Remove configuration file
rm -f k3s-infrastructure.conf

echo "Cleanup completed successfully!" 