locals {
  bundled           = var.postgres.mode == "bundled"
  db_host           = local.bundled ? "127.0.0.1" : var.postgres.host
  db_port           = local.bundled ? 5432 : var.postgres.port
  admin_secret_path = local.bundled ? "" : "${var.vault_kv_path}/data/${var.postgres.admin_secret}"
  secret_name       = "${var.namespace}/${var.job_name}/config"
  filestore_volume  = "${var.job_name}-filestore"
  pgdata_volume     = "${var.job_name}-pgdata"
  admin_password    = coalesce(var.admin_password, random_password.admin.result)

  config = {
    db_password    = random_password.db.result
    admin_password = local.admin_password
  }
  # Bumps whenever a secret changes, so the write-only secret is written again
  # and the job picks up the new config_version.
  config_version = parseint(substr(sha256(jsonencode(local.config)), 0, 8), 16)
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
    pgdata_volume      = local.bundled ? nomad_dynamic_host_volume.pgdata[0].name : ""
    bundled            = local.bundled
    db_host            = local.db_host
    db_port            = local.db_port
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
