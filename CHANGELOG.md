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

## v0.2.0

- Base Odoo image; addons are no longer baked in. They are delivered separately
  into the `<job_name>-addons` host volume, mounted at `/mnt/extra-addons`, so a
  client installs Odoo first and adds modules later without rebuilding the image.

## v0.2.1

- External mode: the shared PostgreSQL superuser credential is read at apply and
  kept in Odoo's own Vault secret, so the create-db task reads it from a path
  Odoo's workload identity may read (not the postgres app's, which it may not).

## v0.2.2

- create-db: set the role password by value, not a psql variable (which psql -c does
  not interpolate), fixing a syntax error on first start.

## v0.2.3

- Set the PASSWORD env from Vault, so the official image does not override the
  odoo.conf db_password with its default "odoo" and fail authentication.

## v0.2.4

- `dns_servers`: the job resolves through them, such as the platform's Consul
  DNS, so an external `postgres.host` can be a Consul service name
  (`postgres.service.consul`) and the shared PostgreSQL found wherever it runs.
