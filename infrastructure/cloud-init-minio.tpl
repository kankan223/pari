#!/bin/bash
# Cloud-init script for MinIO storage nodes

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget

# Download and install MinIO
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
mv minio /usr/local/bin/

# Create MinIO user and directories
useradd -r minio-user -s /sbin/nologin
mkdir -p /mnt/data{1..${drives_count}}
chown -R minio-user:minio-user /mnt/data*

# Configure MinIO for distributed mode
cat > /etc/default/minio <<EOF
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
MINIO_VOLUMES="/mnt/data1 /mnt/data2"
MINIO_OPTS="--address :9000 --console-address :9001"
EOF

# Create systemd service
cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=minio-user
Group=minio-user
EnvironmentFile=-/etc/default/minio
ExecStart=/usr/local/bin/minio server \$MINIO_OPTS \$MINIO_VOLUMES
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start MinIO
systemctl daemon-reload
systemctl enable minio
systemctl start minio

echo "MinIO node initialized successfully"
