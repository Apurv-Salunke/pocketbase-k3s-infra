# Storage Configuration for K3s

This document outlines the process of configuring persistent storage for our k3s-based production backend deployment.

## Prerequisites

- EC2 instance with K3s installed as described in [K3s Installation](02-k3s-installation.md)
- Data volume attached and mounted as described in [EC2 Instance Provisioning](01-ec2-instance-provisioning.md)

## Storage Classes

K3s comes with the Local Path Provisioner by default, which is suitable for single-node deployments. We'll use this for our vertical scaling approach.

### Verify Local Path Provisioner

```bash
# Check if the Local Path Provisioner is installed
kubectl get storageclass

# The output should include 'local-path' storage class
```

If it's not available, you can install it manually:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

### Set Local Path as Default Storage Class

```bash
# Set local-path as the default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify the default storage class
kubectl get storageclass
```

## Persistent Volumes for Our Applications

We need to create persistent volumes for our applications. Let's create the necessary PersistentVolumeClaim (PVC) manifests.

### Go Server PVC

Create a file named `go-server-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: go-server-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

Apply the PVC:

```bash
kubectl apply -f go-server-pvc.yaml
```

### Helper Server PVC (if needed)

If your helper server needs persistent storage, create a file named `helper-server-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: helper-server-data
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi
```

Apply the PVC:

```bash
kubectl apply -f helper-server-pvc.yaml
```

## Data Backup Configuration

It's important to set up regular backups of your persistent data. Here's a simple approach using a CronJob.

### Create a Backup Script

Create a file named `backup-script.sh` on your EC2 instance:

```bash
#!/bin/bash

# Set variables
BACKUP_DIR="/data/backups"
DATE=$(date +%Y%m%d-%H%M%S)
K8S_DATA_DIR="/var/lib/rancher/k3s/storage"

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Backup Kubernetes persistent volumes
tar -czf $BACKUP_DIR/k8s-data-$DATE.tar.gz $K8S_DATA_DIR

# Rotate backups (keep last 7 days)
find $BACKUP_DIR -name "k8s-data-*.tar.gz" -type f -mtime +7 -delete

# Optional: Upload to S3 or other remote storage
# aws s3 cp $BACKUP_DIR/k8s-data-$DATE.tar.gz s3://your-bucket/backups/
```

Make the script executable:

```bash
chmod +x backup-script.sh
```

### Set Up a Cron Job

Add a cron job to run the backup script daily:

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * /path/to/backup-script.sh") | crontab -
```

## Volume Mounting in Kubernetes Deployments

When creating deployment manifests, you'll need to mount these persistent volumes. Here's an example of how to do this for the Go Server:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-server
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: go-server
  template:
    metadata:
      labels:
        app: go-server
    spec:
      containers:
      - name: go-server
        image: <AWS_ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/go-server:latest
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: data
          mountPath: /app/pb_data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: go-server-data
```

## Monitoring Storage Usage

It's important to monitor storage usage to avoid running out of space:

```bash
# Check PVC status
kubectl get pvc

# Check PV status
kubectl get pv

# Check node disk usage
kubectl describe node | grep -A 5 "Allocated resources"

# Check actual disk usage on the EC2 instance
df -h
```

## Troubleshooting

### Common Issues

1. **PVC stuck in Pending state**:
   - Check if the storage class exists: `kubectl get sc`
   - Check if there's enough disk space: `df -h`
   - Check events: `kubectl describe pvc <pvc-name>`

2. **Permission issues with mounted volumes**:
   - Check the permissions on the host path: `ls -la /var/lib/rancher/k3s/storage/`
   - You may need to adjust permissions: `sudo chmod -R 777 /var/lib/rancher/k3s/storage/`

3. **Data not persisting after pod restart**:
   - Verify the volume mount in the pod: `kubectl describe pod <pod-name>`
   - Check if the PVC is correctly bound: `kubectl get pvc`

## Next Steps

After configuring storage, proceed to [Networking Setup](04-networking-setup.md). 