#!/bin/bash
# Cloud-init script for database nodes
#
# Node 0 (10.0.1.10) is the primary; nodes 1-2 (10.0.1.11/12) become the
# streaming standbys (bootstrap them per infrastructure/database/README.md).
# The authoritative PostgreSQL settings live in infrastructure/database/;
# this script installs PostgreSQL, applies the primary settings, installs the
# extensions, and bootstraps the application/replication roles.

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install PostgreSQL + PostGIS + wal-g (WAL archiving to MinIO)
apt-get install -y postgresql postgresql-contrib postgis
if [ ! -x /usr/local/bin/wal-g ]; then
  curl -fsSL https://github.com/wal-g/wal-g/releases/download/v3.0.0/wal-g.linux-amd64.tar.gz \
    | tar -xz -C /usr/local/bin wal-g
  chmod +x /usr/local/bin/wal-g
fi

# Configure PostgreSQL for replication + WAL archiving (primary settings;
# standbys override with postgresql-standby.conf after pg_basebackup)
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
wal_keep_size = 1GB
synchronous_commit = on
synchronous_standby_names = 'ANY 1 (civic_standby_1, civic_standby_2)'
archive_mode = on
archive_command = '/usr/local/bin/wal-archive-to-minio.sh %p %f'
archive_timeout = 300
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
EOF

# Configure pg_hba.conf for replication + application roles
cat >> /etc/postgresql/14/main/pg_hba.conf <<EOF
host    replication    replicator    10.0.1.0/24    scram-sha-256
host    all            civic_app     10.0.1.0/24    scram-sha-256
host    all            all           10.0.0.0/16    scram-sha-256
EOF

# Restart PostgreSQL
systemctl restart postgresql

# Install extensions
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"

# Bootstrap roles (idempotent; passwords activated from Vault post-provision —
# see schema migration 0001 for the NOLOGIN defaults).
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_app') THEN
        CREATE ROLE civic_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_replicator') THEN
        CREATE ROLE civic_replicator NOLOGIN REPLICATION;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_backup') THEN
        CREATE ROLE civic_backup NOLOGIN;
    END IF;
END
$$;
SQL

echo "Database node initialized successfully"
