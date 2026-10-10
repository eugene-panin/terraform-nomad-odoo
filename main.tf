locals {
  bundled           = var.postgres.mode == "bundled"
  db_host           = local.bundled ? "127.0.0.1" : var.postgres.host
  db_port           = local.bundled ? 5432 : var.postgres.port
  admin_secret_path = local.bundled ? "" : "${var.vault_kv_path}/data/${var.postgres.admin_secret}"
  secret_name       = "${var.namespace}/${var.job_name}/config"
  filestore_volume  = "${var.job_name}-filestore"
  addons_volume     = "${var.job_name}-addons"
  pgdata_volume     = "${var.job_name}-pgdata"
  admin_password    = coalesce(var.admin_password, random_password.admin.result)

  # In external mode the shared PostgreSQL's superuser credential is read here, at
  # apply, and kept in Odoo's own secret — so the create-db task reads it from a
  # path Odoo's workload identity may read, not the postgres app's (which it may not).
  config = merge(
    {
      db_password    = random_password.db.result
      admin_password = local.admin_password
    },
    local.bundled ? {} : {
      pg_admin_username = data.vault_kv_secret_v2.pg_admin[0].data["username"]
      pg_admin_password = data.vault_kv_secret_v2.pg_admin[0].data["password"]
    },
  )
  # Bumps whenever a secret changes, so the write-only secret is written again
  # and the job picks up the new config_version.
  config_version = parseint(substr(sha256(jsonencode(local.config)), 0, 8), 16)
}

data "vault_kv_secret_v2" "pg_admin" {
  count = local.bundled ? 0 : 1
  mount = var.vault_kv_path
  name  = var.postgres.admin_secret
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "config" {
  mount                = var.vault_kv_path
  name                 = local.secret_name
  data_json_wo         = jsonencode(local.config)
  data_json_wo_version = local.config_version
}

resource "nomad_dynamic_host_volume" "filestore" {
  name      = local.filestore_volume
  namespace = var.namespace
  plugin_id = "mkdir"

  parameters = {
    mode = "0700"
    uid  = "101"
    gid  = "101"
  }

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

# Addons are delivered separately into this volume, mounted at /mnt/extra-addons,
# not baked into the image: a client installs Odoo, then adds modules later.
resource "nomad_dynamic_host_volume" "addons" {
  name      = local.addons_volume
  namespace = var.namespace
  plugin_id = "mkdir"

  parameters = {
    mode = "0755"
    uid  = "101"
    gid  = "101"
  }

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

resource "nomad_dynamic_host_volume" "pgdata" {
  count = local.bundled ? 1 : 0

  name      = local.pgdata_volume
  namespace = var.namespace
  plugin_id = "mkdir"

  parameters = {
    mode = "0700"
    uid  = "999"
    gid  = "999"
  }

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

resource "nomad_job" "odoo" {
  jobspec = templatefile("${path.module}/templates/odoo.nomad.hcl.tftpl", {
    job_name           = var.job_name
    namespace          = var.namespace
    datacenters        = var.datacenters
    filestore_volume   = nomad_dynamic_host_volume.filestore.name
    addons_volume      = nomad_dynamic_host_volume.addons.name
    pgdata_volume      = local.bundled ? nomad_dynamic_host_volume.pgdata[0].name : ""
    bundled            = local.bundled
    db_host            = local.db_host
    db_port            = local.db_port
    dns_servers        = var.dns_servers
    mesh               = var.mesh
    admin_secret_path  = local.admin_secret_path
    secret_path        = "${var.vault_kv_path}/data/${local.secret_name}"
    config_version     = local.config_version
    internal_network   = var.internal_host_network
    traefik            = var.traefik
    hostname           = var.hostname
    odoo_image         = var.odoo_image
    postgres_image     = var.postgres.image
    db_name            = var.db_name
    workers            = var.workers
    demo               = var.demo
    odoo_resources     = var.odoo_resources
    postgres_resources = var.postgres_resources
  })

  purge_on_destroy = true

  depends_on = [vault_kv_secret_v2.config]
}

# In the mesh: what Consul's L7 features see, and who may connect (intentions;
# the platform's ACLs deny any other). Traefik reaches Odoo outside the mesh.
resource "consul_config_entry" "defaults" {
  count = var.mesh.enabled ? 1 : 0

  kind = "service-defaults"
  name = var.job_name
  config_json = jsonencode({
    # As Consul stores it (with the empty blocks it fills in), so a plan sees no drift.
    Protocol         = var.mesh.protocol
    Expose           = {}
    MeshGateway      = {}
    TransparentProxy = {}
  })
}

# Only when some service is allowed: Consul takes no intentions without a source,
# and with none the platform's default deny already stands.
resource "consul_config_entry" "intentions" {
  count = var.mesh.enabled && length(var.mesh.allow) > 0 ? 1 : 0

  kind = "service-intentions"
  name = var.job_name
  config_json = jsonencode({
    # As Consul stores it: Type consul, and Precedence 9 for an exact source and an
    # exact destination; so a plan sees no drift.
    Sources = [for s in var.mesh.allow : { Name = s, Action = "allow", Precedence = 9, Type = "consul" }]
  })
}
