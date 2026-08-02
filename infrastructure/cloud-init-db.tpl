#!/bin/bash
# Cloud-init script for database nodes

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Configure PostgreSQL for replication
cat >> /etc/postgresql/14/main/postgresql.conf <<EOF
listen_addresses = '10.0.1.${10 + node_index}'
max_connections = 200
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 5242kB
min_wal_size = 1GB
max_wal_size = 4GB
wal_level = replica
hot_standby = on
max_wal_senders = 3
max_replication_slots = 3
synchronous_commit = on
EOF

# Configure pg_hba.conf for replication
cat >> /etc/postgresql/14/main/pg_hba.conf <<EOF
host    replication    replicator    10.0.1.0/24    scram-sha-256
host    all            all           10.0.0.0/16     scram-sha-256
EOF

# Restart PostgreSQL
systemctl restart postgresql

# Install PostGIS extension
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;"

echo "Database node initialized successfully"
