# Infrastructure Testing Guide

This guide outlines the testing procedures for the infrastructure setup scripts.

## Prerequisites

1. AWS CLI installed and configured with appropriate permissions
2. AWS account with permissions to create:
   - VPC
   - Subnets
   - Security Groups
   - EC2 Instances
   - Elastic IPs
3. Bash shell environment

## Testing Steps

### 1. Initial Setup

1. Make scripts executable:
```bash
chmod +x scripts/infrastructure/ec2-setup.sh
chmod +x scripts/infrastructure/cleanup.sh
```

2. Verify AWS CLI configuration:
```bash
aws configure list
aws sts get-caller-identity
```

### 2. EC2 Setup Testing

1. Run the setup script:
```bash
./scripts/infrastructure/ec2-setup.sh
```

2. Verify resources created:
   - Check EC2 Dashboard for instance
   - Verify VPC and networking components
   - Ensure security group rules are correct
   - Test SSH access to instance

3. Validation checklist:
   - [ ] Instance is running
   - [ ] Can SSH into instance
   - [ ] Security group has required ports (22, 80, 443, 6443)
   - [ ] Elastic IP is assigned
   - [ ] Instance has internet access

### 3. Connectivity Testing

1. SSH into the instance:
```bash
ssh -i k3s-key.pem ubuntu@<ELASTIC_IP_ADDRESS>
```

2. Test internet connectivity:
```bash
ping -c 4 google.com
curl -v https://google.com
```

3. Verify system resources:
```bash
df -h  # Check disk space
free -m  # Check memory
nproc  # Check CPU cores
```

### 4. Cleanup Testing

1. Run the cleanup script:
```bash
./scripts/infrastructure/cleanup.sh
```

2. Verify resource deletion:
   - [ ] EC2 instance terminated
   - [ ] Elastic IP released
   - [ ] Security group deleted
   - [ ] Subnet deleted
   - [ ] VPC deleted
   - [ ] Key pair removed

3. Check AWS Console to ensure no resources remain

## Expected Results

### After Setup

1. EC2 Instance:
   - Status: Running
   - Type: t3.medium
   - Volume: 30GB gp3
   - Public IP: Elastic IP assigned

2. Networking:
   - VPC with DNS hostnames enabled
   - Public subnet with auto-assign public IP
   - Internet Gateway attached
   - Route table with internet access

3. Security:
   - Security group with required ports
   - SSH key pair created
   - Instance accessible via SSH

### After Cleanup

1. All resources should be deleted
2. No charges should continue to accrue
3. Configuration file removed

## Troubleshooting

### Common Issues

1. Permission Errors:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify IAM permissions
aws iam get-user
aws iam list-attached-user-policies
```

2. Resource Limits:
```bash
# Check VPC limits
aws ec2 describe-account-attributes --attribute-names vpc-max-security-groups-per-vpc

# Check EC2 limits
aws ec2 describe-account-attributes --attribute-names max-instances
```

3. Network Issues:
```bash
# Check VPC configuration
aws ec2 describe-vpcs

# Verify route table
aws ec2 describe-route-tables

# Test security group
aws ec2 describe-security-groups
```

## Reporting Issues

When reporting issues, please include:

1. Script output
2. AWS region
3. Error messages
4. Resource IDs (if applicable)
5. Steps to reproduce

## Next Steps

After successful testing:

1. Document any configuration changes needed
2. Update AMI ID if necessary
3. Proceed to k3s installation
4. Save successful configuration 