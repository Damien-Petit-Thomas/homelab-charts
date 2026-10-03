# 0001. The Vaultwarden chart supports SQLite only

**Status:** Accepted

## Context
Vaultwarden supports SQLite, PostgreSQL and MySQL. The homelab runs one
instance for a handful of users; its database is a few megabytes. A
PostgreSQL backend would mean an operator (CloudNativePG), one to three
database pods, an object store for its backups, and a data migration.

## Decision
- The chart supports SQLite only, on a `ReadWriteOnce` volume.
- One replica, `Recreate` strategy: two pods must never open the same
  database file.
- The engineering effort goes to what SQLite needs: consistent backups
  (`sqlite3 .backup`, never a file copy of a live database) and a restore
  procedure tested in CI.

## Consequences
- No database code path that production never runs.
- No horizontal scaling and no zero-downtime rollout: acceptable for this
  load, stated in the chart README.
- The pod follows its volume: with `local-path` storage it is bound to one
  node.

## Rejected alternatives
- **PostgreSQL through CloudNativePG**: point-in-time recovery and node
  independence, at the cost of an operator, extra pods, an object store and
  a migration, for a database this size.
- **Both backends, selected by a value**: doubles the test matrix to support
  a backend nobody here would run.
