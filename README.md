# terraform-nomad-odoo

Odoo with its own PostgreSQL on a Nomad platform that has Consul, Vault and
Traefik — such as [hashi](https://github.com/eugene-panin/damstack-hashi). The
[damstack-odoo](https://github.com/eugene-panin/damstack-odoo) stack wires it.

## What it deploys

One Nomad job, one group, three tasks sharing the group's network namespace:

- **odoo** — the main task, the Odoo image with your custom addons baked in. It
  reads `/local/odoo.conf`, rendered from Vault. Served by Traefik.
- **postgres** — a prestart sidecar, PostgreSQL for Odoo, reachable at
  `127.0.0.1:5432` within the group.
- **wait-db** — a prestart task that blocks until PostgreSQL answers, so Odoo
  never starts against a database that is not up.

The filestore (`/var/lib/odoo`) and the database (`/var/lib/postgresql/data`)
each live in a dynamic host volume, named `<job_name>-filestore` and
`<job_name>-pgdata`, so the platform's backup copies them by name. The job sets
`meta.backup = "stop"`, so it is stopped while its volumes are copied.

The database password and the Odoo master password are generated and kept in
Vault at `<vault_kv_path>/<namespace>/<job_name>/config`; the job reads them
through its Nomad workload identity.

## Ingress

Traefik publishes `hostname` on the public HTTPS entrypoint (`public-https`,
certificate through HTTP-01 by default). A second router sends `/websocket` to
the longpolling port so Odoo's bus works. Odoo binds only the internal host
network — it faces the internet only through Traefik.

## Images

Both images must be pinned by a fixed tag or a digest; the platform policy
refuses `latest` or an untagged image. The Odoo image carries the custom addons
in `/mnt/extra-addons` (see
[docker-odoo](https://github.com/eugene-panin/docker-odoo)).

## Database

`postgres.mode` chooses where the database lives:

- **`bundled`** (default) — a PostgreSQL task runs in the Odoo job, its data in
  the `<job_name>-pgdata` host volume, reachable at `127.0.0.1:5432`. The role and
  database are created by the container on first start. Use this for an app with
  its own dedicated database.
- **`external`** — no PostgreSQL task or volume. Odoo connects to one at
  `postgres.host:postgres.port` and, in a prestart task, creates its own `odoo`
  role and database there, idempotently, using the superuser credential at
  `postgres.admin_secret` (a Vault KV name under `vault_kv_path` holding
  `{username, password}`). A shared PostgreSQL app (e.g. `damstack-postgres`)
  gives host, port and admin_secret, and knows nothing about Odoo's database. Use
  this when several apps share one PostgreSQL.

damstack has no app-to-app dependency, so `external` mode is wired by convention,
not enforced: deploy the PostgreSQL app first, then Odoo.

## Data

The module provisions empty volumes. A fresh database is initialised by Odoo on
first run (`without_demo` follows `demo`). To bring an existing Odoo over,
restore its `pg_dump` into the PostgreSQL volume and its filestore into the
filestore volume before or on first start — the damstack-odoo stack does this in
its restore step.

## Usage

```hcl
module "odoo" {
  source = "git::https://github.com/eugene-panin/terraform-nomad-odoo.git?ref=v0.1.0"

  hostname      = "odoo.example.com"
  odoo_image    = "ghcr.io/example/odoo:19.0.1"
  vault_kv_path = var.vault_kv_path
}
```

## Inputs

| Name | Default | What |
| --- | --- | --- |
| `hostname` | — | FQDN Odoo is served on |
| `vault_kv_path` | — | Vault KV v2 mount the platform gives |
| `odoo_image` | — | Odoo image with the addons, pinned |
| `postgres` | `{mode="bundled"}` | `bundled` (runs PostgreSQL in the job, `image`) or `external` (`host`, `port`, `admin_secret`) — see Database |
| `job_name` | `odoo` | Nomad job, Consul service, Traefik routers |
| `namespace` | `default` | Nomad namespace |
| `datacenters` | `["*"]` | Nomad datacenters |
| `db_name` | `odoo` | database name; `dbfilter` pins Odoo to it |
| `admin_password` | generated | Odoo master password |
| `workers` | `2` | Odoo HTTP workers (above zero serves websockets) |
| `demo` | `false` | load demo data on first init |
| `internal_host_network` | `default` | host network the ports bind to |
| `traefik` | public HTTPS | `{entrypoint, certresolver}` |
| `odoo_resources` | `{1000, 2048}` | Odoo `{cpu, memory}` |
| `postgres_resources` | `{500, 1024}` | PostgreSQL `{cpu, memory}` |

## Outputs

`job_id`, `url`, `filestore_volume`, `pgdata_volume`, `admin_password` (sensitive).

## Development

```sh
make lint          # tofu fmt -check and tflint
make module-tests  # tofu test, mocked providers
```
