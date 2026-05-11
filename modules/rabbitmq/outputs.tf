output "rabbitmq_public_ip" {
  description = "Public IP address of the RabbitMQ server"
  value       = hcloud_server.rabbitmq.ipv4_address
}

output "rabbitmq_private_ip" {
  description = "Private IP address of the RabbitMQ server"
  value       = one(hcloud_server.rabbitmq.network[*].ip)
}

output "rabbitmq_id" {
  description = "ID of the RabbitMQ server"
  value       = hcloud_server.rabbitmq.id
}

output "rabbitmq_name" {
  description = "Name of the RabbitMQ server"
  value       = hcloud_server.rabbitmq.name
}
