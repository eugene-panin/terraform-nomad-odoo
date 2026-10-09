# Changelog

## v0.1.0

- Odoo and its PostgreSQL on a Nomad platform, in one job group: Odoo in the
  main task, PostgreSQL as a prestart sidecar, a prestart task that waits for
  the database before Odoo starts.
- The filestore and the PostgreSQL data live each in its own dynamic host
  volume, so the platform's backup copies them by name.
- The database password and the Odoo master password are generated and kept in
  Vault; the job reads them through its workload identity.
- Traefik publishes the host name on the public HTTPS entrypoint, with a second
  router sending `/websocket` to the longpolling port. Odoo binds only the
  internal host network.
- `postgres.mode` switches between a bundled PostgreSQL (the default) and an
  external one shared with other apps.
