variable "hostname" {
  description = "Fully qualified host name Odoo is served on, such as odoo.example.com. Traefik gets its certificate and routes it."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a lowercase fully qualified domain name."
  }
}

variable "vault_kv_path" {
  description = "Path of the Vault KV v2 engine the job keeps its secrets in; the platform gives it."
  type        = string
}

variable "namespace" {
  description = "Nomad namespace the job runs in."
  type        = string
  default     = "default"
}

variable "job_name" {
  description = "Name of the Nomad job, the Consul service and the Traefik routers."
  type        = string
  default     = "odoo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.job_name))
    error_message = "job_name must be lowercase letters, digits and -, starting with a letter."
  }
}

variable "datacenters" {
  description = "Nomad datacenters the job may run in."
  type        = list(string)
  default     = ["*"]
}

variable "odoo_image" {
  description = "Base Odoo container image, pinned by a fixed tag or a digest. No addons are baked in: they are delivered separately into the addons volume mounted at /mnt/extra-addons."
  type        = string
  default     = "odoo:19.0"
}

variable "postgres" {
  description = <<-EOT
    How Odoo gets its database.
    mode "bundled" (the default) runs a PostgreSQL task inside the Odoo job, with
    its data in a host volume; image applies and host/port are ignored.
    mode "external" runs no PostgreSQL: Odoo connects to one reachable at
    host:port and, on start, creates its own "odoo" role and database there, using
    the superuser credential at admin_secret (a Vault KV name under vault_kv_path,
    holding {username, password}). Use this when more than one app shares one
    PostgreSQL — a shared PostgreSQL app (damstack-postgres) gives host, port and
    admin_secret.
  EOT
  type = object({
    mode         = optional(string, "bundled")
    image        = optional(string, "postgres:16.10")
    host         = optional(string, null)
    port         = optional(number, 5432)
    admin_secret = optional(string, null)
  })
  default = {}
  validation {
    condition     = contains(["bundled", "external"], var.postgres.mode)
    error_message = "postgres.mode must be bundled or external."
  }
  validation {
    condition     = var.postgres.mode == "bundled" || var.postgres.host != null
    error_message = "postgres.mode external needs postgres.host, the address of the shared PostgreSQL."
  }
  validation {
    condition     = var.postgres.mode == "bundled" || var.postgres.admin_secret != null
    error_message = "postgres.mode external needs postgres.admin_secret, the Vault name of the superuser credential that creates Odoo's role and database."
  }
}

variable "db_name" {
  description = "Name of the Odoo database. dbfilter pins Odoo to exactly this one."
  type        = string
  default     = "odoo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must be lowercase letters, digits and _, starting with a letter."
  }
}

variable "admin_password" {
  description = "Odoo master password (admin_passwd), for the database manager. Null generates one, returned by the admin_password output."
  type        = string
  default     = null
  sensitive   = true
}

variable "workers" {
  description = "Number of Odoo HTTP workers. Above zero turns on the gevent worker that serves websockets on the longpolling port."
  type        = number
  default     = 2
  validation {
    condition     = var.workers >= 0
    error_message = "workers must be zero or more."
  }
}

variable "demo" {
  description = "Load Odoo demo data when the database is first initialised."
  type        = bool
  default     = false
}

variable "internal_host_network" {
  description = "Nomad host network the HTTP and longpolling ports bind to; Traefik reaches them there. Never the public network: Odoo faces the internet only through Traefik."
  type        = string
  default     = "default"
}

variable "traefik" {
  description = "Traefik entrypoint Odoo is published on and the certificate resolver that entrypoint uses. The defaults are the public HTTPS entrypoint of the hashi platform."
  type = object({
    entrypoint   = optional(string, "public-https")
    certresolver = optional(string, "http")
  })
  default = {}
}

variable "odoo_resources" {
  description = "CPU (MHz) and memory (MB) for the Odoo task."
  type = object({
    cpu    = optional(number, 1000)
    memory = optional(number, 2048)
  })
  default = {}
}

variable "postgres_resources" {
  description = "CPU (MHz) and memory (MB) for the PostgreSQL task."
  type = object({
    cpu    = optional(number, 500)
    memory = optional(number, 1024)
  })
  default = {}
}
