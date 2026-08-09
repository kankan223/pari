# Civic Commons — PostgreSQL Replication & Backup (Task 4.5)

Declarative configuration for the 3-node PostgreSQL cluster: **one primary,
two standbys** with synchronous streaming replication, plus **WAL archiving to
MinIO** for Point-in-Time Recovery (PITR).

## Topology

| Node | IP (db private net) | Role |
|------|--------------------|------|
| `civic-db-0` | `10.0.1.10` | primary |
| `civic-db-1` | `10.0.1.11` | standby (civic_standby_1) |
| `civic-db-2` | `10.0.1.12` | standby (civic_standby_2) |

Nodes are provisioned by `kubernetes.tf` → `cloud-init-db.tpl`; the config
files here are the source of truth for the PostgreSQL settings applied on each
node.

## Files

- `postgresql-primary.conf` — primary: `wal_level=replica`, `max_wal_senders=3`,
  `max_replication_slots=3`, `synchronous_commit=on` with
  `synchronous_standby_names = 'ANY 1 (civic_standby_1, civic_standby_2)'`
  (zero data-loss window: a commit is acknowledged only after a standby durably
  holds it), and `archive_mode=on` → MinIO.
- `postgresql-standby.conf` — standby: `hot_standby=on`, `hot_standby_feedback`,
  replication source from the primary via `pg_basebackup -R` (writes
  `primary_conninfo` + `primary_slot_name`).
- `pg_hba.conf` — scram-sha-256 for `civic_app` (application) and
  `civic_replicator` (replication) from the database private network only;
  default-deny for everything else.
- `wal-archive-to-minio.sh` — the primary's `archive_command`; pushes every
  WAL segment to the `civic-db-backups` MinIO bucket via `wal-g`.
- `../security/postgres-wal-backup.yaml` — nightly base-backup CronJob
  (wal-g) so PITR always has a recent anchor.

## Roles (created by the schema migration, activated at bootstrap)

| Role | Purpose |
|------|---------|
| `civic_app` | application role; the only role with RLS policies (created NOLOGIN, then `ALTER ROLE ... LOGIN PASSWORD` from Vault) |
| `civic_replicator` | streaming replication (REPLICATION attribute, scram auth) |
| `civic_backup` | wal-g base backups |

## Standby bootstrap

```bash
# On each standby:
sudo -u postgres pg_basebackup -h 10.0.1.10 -U civic_replicator \
    -D /var/lib/postgresql/14/main -R -P -X stream
touch /var/lib/postgresql/14/main/standby.signal
systemctl restart postgresql
```

Create the replication slots on the primary once:

```sql
SELECT pg_create_physical_replication_slot('civic_standby_1');
SELECT pg_create_physical_replication_slot('civic_standby_2');
```

## Point-in-Time Recovery

1. `wal-g backup-fetch /var/lib/postgresql/14/main LATEST`
2. `wal-g wal-fetch ...` (or restore via `recovery_target_time`/`recovery_target_lsn`)
3. Start the node with `recovery_target_time = '<T>'` in `postgresql.conf`.

## Migrations

Schema migrations are embedded in the Go services and applied automatically at
startup (`internal/database` — forward + rollback, advisory-locked). No manual
SQL needed on deploy.

### Migration role vs runtime role (important)

Migrations require a bootstrap role (they `CREATE EXTENSION`, `CREATE ROLE`,
and `CREATE POLICY`). They run once at first boot as the bootstrap superuser
(the `cloud-init-db.tpl` provisioning), then record version 1 and never run
again.

**The runtime `POSTGRES_DSN` must connect as `civic_app`, never the
superuser** — superusers bypass Row-Level Security entirely, even with
`FORCE ROW LEVEL SECURITY`. RLS is only meaningful when the services talk to
the database as `civic_app` (the sole role with policies).
