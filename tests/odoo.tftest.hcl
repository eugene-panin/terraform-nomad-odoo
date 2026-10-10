mock_provider "nomad" {}
mock_provider "random" {}
mock_provider "vault" {}

variables {
  hostname      = "odoo.example.com"
  vault_kv_path = "secret"
  odoo_image    = "ghcr.io/example/odoo-newo:19.0.1"
}

run "it_serves_on_the_hostname" {
  command = apply

  assert {
    condition     = output.url == "https://odoo.example.com"
    error_message = "Odoo is not served on its hostname."
  }
}

run "the_volumes_are_named_after_the_job" {
  command = apply

  variables {
    job_name = "crm"
  }

  assert {
    condition     = output.filestore_volume == "crm-filestore"
    error_message = "The filestore volume is not named after the job."
  }

  assert {
    condition     = output.pgdata_volume == "crm-pgdata"
    error_message = "The PostgreSQL volume is not named after the job."
  }
}

run "external_postgres_runs_no_database_task" {
  command = apply

  variables {
    postgres = {
      mode         = "external"
      host         = "10.77.0.1"
      port         = 5432
      admin_secret = "default/postgres/admin"
    }
  }

  override_data {
    target = data.vault_kv_secret_v2.pg_admin
    values = {
      data = { username = "postgres", password = "secret" }
    }
  }

  assert {
    condition     = output.pgdata_volume == null
    error_message = "External mode must not create a PostgreSQL host volume."
  }

  assert {
    condition     = !strcontains(nomad_job.odoo.jobspec, "task \"postgres\"")
    error_message = "External mode must not run a PostgreSQL task."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "task \"create-db\"")
    error_message = "External mode must create its own role and database."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "db_host = 10.77.0.1")
    error_message = "External mode must point Odoo at the external database host."
  }

  assert {
    condition     = !strcontains(nomad_job.odoo.jobspec, "dns {")
    error_message = "Without dns_servers the job keeps the node's resolvers."
  }
}

run "external_postgres_by_its_consul_name" {
  command = apply

  variables {
    postgres = {
      mode         = "external"
      host         = "postgres.service.consul"
      admin_secret = "default/postgres/admin"
    }
    dns_servers = ["10.77.0.1"]
  }

  override_data {
    target = data.vault_kv_secret_v2.pg_admin
    values = {
      data = { username = "postgres", password = "secret" }
    }
  }

  assert {
    condition = (
      strcontains(nomad_job.odoo.jobspec, "servers = [\"10.77.0.1\"]")
      && strcontains(nomad_job.odoo.jobspec, "db_host = postgres.service.consul")
      && strcontains(nomad_job.odoo.jobspec, "pg_isready -h postgres.service.consul")
    )
    error_message = "Odoo must resolve through the given DNS and reach PostgreSQL by its Consul name."
  }
}

run "the_job_renders" {
  command = apply

  assert {
    condition     = can(nomad_job.odoo.jobspec)
    error_message = "The Nomad job template did not render."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "task \"postgres\"")
    error_message = "Bundled mode must run a PostgreSQL task."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "destination = \"/mnt/extra-addons\"")
    error_message = "Addons are delivered through a volume at /mnt/extra-addons, not baked into the image."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "Host(`odoo.example.com`)")
    error_message = "The Traefik router does not route the hostname."
  }

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "host_network = \"default\"")
    error_message = "The ports are not on the internal host network."
  }

  assert {
    condition     = !strcontains(nomad_job.odoo.jobspec, "host_network = \"public\"")
    error_message = "Odoo must never bind the public host network; it faces the internet only through Traefik."
  }
}

run "memory_is_reserved_by_use_and_may_grow" {
  command = apply

  assert {
    condition     = strcontains(nomad_job.odoo.jobspec, "memory     = 512\n        memory_max = 2048") && strcontains(nomad_job.odoo.jobspec, "memory     = 768\n        memory_max = 2048")
    error_message = "Odoo and its bundled PostgreSQL must reserve their usual memory and be allowed to grow to memory_max."
  }
}
