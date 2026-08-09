-- Civic Commons schema migration 0001 — rollback (Task 4.5).
--
-- Drops the application tables in dependency order. Extensions and roles are
-- intentionally left in place: they are cluster-scoped and additive, and
-- dropping PostGIS/pgcrypto could break other schemas sharing the instance.

DROP TABLE IF EXISTS connection_requests;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS usernames;
DROP TABLE IF EXISTS users;
