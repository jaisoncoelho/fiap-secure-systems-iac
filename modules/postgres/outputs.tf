output "postgres_public_ip" {
  description = "Public IP address of the Postgres server"
  value       = hcloud_server.postgres.ipv4_address
}

output "postgres_private_ip" {
  description = "Private IP address of the Postgres server"
  value       = one(hcloud_server.postgres.network[*].ip)
}

output "postgres_id" {
  description = "ID of the Postgres server"
  value       = hcloud_server.postgres.id
}

output "postgres_name" {
  description = "Name of the Postgres server"
  value       = hcloud_server.postgres.name
}
