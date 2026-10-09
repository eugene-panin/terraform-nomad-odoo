output "job_id" {
  description = "ID of the Odoo job in Nomad."
  value       = nomad_job.odoo.id
}

output "url" {
  description = "URL Odoo is served on."
  value       = "https://${var.hostname}"
}

output "filestore_volume" {
  description = "Name of the dynamic host volume holding the Odoo filestore."
  value       = nomad_dynamic_host_volume.filestore.name
}

output "pgdata_volume" {
  description = "Name of the dynamic host volume holding the PostgreSQL data; null when an external database is used."
  value       = local.bundled ? nomad_dynamic_host_volume.pgdata[0].name : null
}

output "admin_password" {
  description = "Odoo master password (admin_passwd) for the database manager."
  value       = local.admin_password
  sensitive   = true
}
