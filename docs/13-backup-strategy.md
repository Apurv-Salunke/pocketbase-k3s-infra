# Backup Strategy

This document outlines the backup and recovery procedures for our k3s production environment, ensuring data safety and business continuity.

## Prerequisites

- AWS CLI configured with appropriate permissions
- kubectl configured with cluster access
- Velero backup tool installed
- AWS S3 bucket for backup storage
- AWS IAM roles and policies configured

## Backup Components

### 1. Install Velero

Create `velero-values.yaml`:

```yaml
configuration:
  provider: aws
  backupStorageLocation:
    name: default
    bucket: your-backup-bucket
    config:
      region: <AWS_REGION>
  volumeSnapshotLocation:
    name: default
    config:
      region: <AWS_REGION>

credentials:
  useSecret: true
  secretContents:
    cloud: |
      [default]
      aws_access_key_id = <AWS_ACCESS_KEY_ID>
      aws_secret_access_key = <AWS_SECRET_ACCESS_KEY>

initContainers:
- name: velero-plugin-for-aws
  image: velero/velero-plugin-for-aws:v1.5.0
  volumeMounts:
  - mountPath: /target
    name: plugins

schedules:
  daily-backup:
    schedule: "0 1 * * *"
    template:
      includedNamespaces:
      - backend
      - monitoring
      ttl: "168h"
```

Install Velero using Helm:

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values velero-values.yaml
```

### 2. Configure Persistent Volume Backup

Create `volume-backup-config.yaml`:

```yaml
apiVersion: velero.io/v1
kind: VolumeSnapshotLocation
metadata:
  name: aws-default
  namespace: velero
spec:
  provider: aws
  config:
    region: <AWS_REGION>
```

Apply the configuration:

```bash
kubectl apply -f volume-backup-config.yaml
```

## Backup Procedures

### 1. Configure Scheduled Backups

Create `backup-schedule.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 1 * * *"  # Daily at 1 AM
  template:
    includedNamespaces:
    - backend
    - monitoring
    includedResources:
    - deployments
    - services
    - configmaps
    - secrets
    - persistentvolumeclaims
    - persistentvolumes
    labelSelector:
      matchLabels:
        backup: "true"
    storageLocation: default
    volumeSnapshotLocations:
    - aws-default
    ttl: "168h"  # 7 days retention
```

Apply the schedule:

```bash
kubectl apply -f backup-schedule.yaml
```

### 2. Configure Database Backup

Create `db-backup-job.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: backend
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine:latest
            command:
            - /bin/sh
            - -c
            - |
              # Backup database files
              tar -czf /backup/db-$(date +%Y%m%d).tar.gz /app/pb_data
              
              # Upload to S3
              aws s3 cp /backup/db-$(date +%Y%m%d).tar.gz s3://your-backup-bucket/database/
            volumeMounts:
            - name: db-data
              mountPath: /app/pb_data
              readOnly: true
            - name: backup
              mountPath: /backup
          volumes:
          - name: db-data
            persistentVolumeClaim:
              claimName: go-server-data
          - name: backup
            emptyDir: {}
          restartPolicy: OnFailure
```

Apply the backup job:

```bash
kubectl apply -f db-backup-job.yaml
```

## Recovery Procedures

### 1. Full Cluster Recovery

Create recovery script `restore-cluster.sh`:

```bash
#!/bin/bash

BACKUP_NAME=$1
NAMESPACE=$2

# Restore from backup
velero restore create --from-backup $BACKUP_NAME \
  --include-namespaces $NAMESPACE \
  --wait

# Verify restoration
kubectl get all -n $NAMESPACE

# Check persistent volumes
kubectl get pv,pvc -n $NAMESPACE
```

### 2. Database Recovery

Create `db-restore-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-restore
  namespace: backend
spec:
  template:
    spec:
      containers:
      - name: restore
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          # Download backup from S3
          aws s3 cp s3://your-backup-bucket/database/db-${BACKUP_DATE}.tar.gz /restore/
          
          # Restore database files
          tar -xzf /restore/db-${BACKUP_DATE}.tar.gz -C /
        env:
        - name: BACKUP_DATE
          value: "20240101"  # Replace with actual date
        volumeMounts:
        - name: db-data
          mountPath: /app/pb_data
        - name: restore
          mountPath: /restore
      volumes:
      - name: db-data
        persistentVolumeClaim:
          claimName: go-server-data
      - name: restore
        emptyDir: {}
      restartPolicy: OnFailure
```

## Verification and Testing

### 1. Backup Verification

Create `verify-backup.sh`:

```bash
#!/bin/bash

# Check backup status
velero backup get

# Verify backup contents
velero backup describe $1 --details

# Check S3 bucket
aws s3 ls s3://your-backup-bucket/backups/
```

### 2. Recovery Testing

Create `test-recovery.sh`:

```bash
#!/bin/bash

BACKUP_NAME=$1
TEST_NAMESPACE="backup-test"

# Create test namespace
kubectl create namespace $TEST_NAMESPACE

# Restore to test namespace
velero restore create --from-backup $BACKUP_NAME \
  --namespace-mappings backend:$TEST_NAMESPACE \
  --wait

# Verify restoration
kubectl get all -n $TEST_NAMESPACE
```

## Monitoring and Alerts

### 1. Configure Backup Monitoring

Create `backup-monitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: backup-alerts
  namespace: monitoring
spec:
  groups:
  - name: backup
    rules:
    - alert: BackupFailed
      expr: |
        velero_backup_failure_total > 0
      for: 1h
      labels:
        severity: critical
      annotations:
        summary: Backup failed
        description: Velero backup has failed

    - alert: BackupTooOld
      expr: |
        time() - velero_backup_last_successful_timestamp > 86400
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: Backup too old
        description: Last successful backup is more than 24 hours old
```

### 2. Configure Slack Notifications

Update Alertmanager configuration:

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: backup-alerts
  namespace: monitoring
spec:
  route:
    receiver: 'slack-backup'
    group_by: ['alertname']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
  receivers:
  - name: 'slack-backup'
    slack_configs:
    - api_url: 'https://hooks.slack.com/services/your-webhook-url'
      channel: '#backup-alerts'
      send_resolved: true
```

## Best Practices

1. **Backup Strategy**:
   - Regular backup schedule
   - Multiple backup locations
   - Encryption at rest
   - Retention policy enforcement

2. **Recovery Testing**:
   - Regular recovery drills
   - Document recovery procedures
   - Test in isolated environment
   - Verify data integrity

3. **Security**:
   - Encrypt backups
   - Secure access credentials
   - Audit backup access
   - Regular permission review

4. **Monitoring**:
   - Monitor backup success
   - Alert on failures
   - Track backup size
   - Monitor restore times

## Troubleshooting

### Common Issues

1. **Backup Failures**:
   ```bash
   # Check Velero logs
   kubectl logs -n velero deploy/velero
   
   # Check backup status
   velero backup describe <backup-name>
   
   # Check S3 permissions
   aws s3 ls s3://your-backup-bucket/
   ```

2. **Restore Failures**:
   ```bash
   # Check restore logs
   velero restore logs <restore-name>
   
   # Verify PVC status
   kubectl get pvc -n backend
   
   # Check pod events
   kubectl describe pod -n backend <pod-name>
   ```

3. **Storage Issues**:
   ```bash
   # Check PV status
   kubectl get pv
   
   # Verify S3 bucket
   aws s3api head-bucket --bucket your-backup-bucket
   ```

## Next Steps

After setting up the backup strategy, proceed to [Update Strategy](14-update-strategy.md) to configure procedures for updating the cluster and applications. 