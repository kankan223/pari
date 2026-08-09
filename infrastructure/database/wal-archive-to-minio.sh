#!/usr/bin/env bash
# Civic Commons — WAL archiving to MinIO (Task 4.5)
# ==================================================
# archive_command for PostgreSQL: pushes each finished WAL segment to the
# MinIO bucket so Point-in-Time Recovery can replay from any point in time.
#
# Requires the `wal-g` binary (MinIO-compatible S3) — install once:
#   curl -L https://github.com/wal-g/wal-g/releases/download/v3.0.0/wal-g.linux-amd64.tar.gz | tar -xz -C /usr/local/bin wal-g
#
# Environment (supplied by the deployment / ESO):
#   WALG_S3_PREFIX            s3://civic-db-backups/wal
#   AWS_ENDPOINT              http://10.0.1.XX:9000   (MinIO cluster)
#   AWS_ACCESS_KEY_ID         (from Vault)
#   AWS_SECRET_ACCESS_KEY     (from Vault)
#   AWS_S3_FORCE_PATH_STYLE   true   (required for MinIO)
#
# Usage (from postgresql-primary.conf):
#   archive_command = '/usr/local/bin/wal-archive-to-minio.sh %p %f'
#
# For environments without wal-g, an `mc` fallback is provided below.

set -euo pipefail

WAL_PATH="$1"
WAL_NAME="$2"

if command -v wal-g >/dev/null 2>&1; then
    exec wal-g wal-push "$WAL_PATH"
fi

# Fallback: MinIO client (mc).
if command -v mc >/dev/null 2>&1; then
    export MC_HOST_civic="${AWS_ENDPOINT:-http://minio:9000}"
    exec mc cp "$WAL_PATH" "civic/civic-db-backups/wal/${WAL_NAME}"
fi

echo "wal-archive: no wal-g or mc available; WAL ${WAL_NAME} NOT archived" >&2
exit 1
