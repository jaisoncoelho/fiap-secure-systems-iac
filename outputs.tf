output "master_node_ip" {
  description = "Public IP of the K3s master node"
  value       = module.cluster.master_node_public_ip
}

output "kubeconfig_instructions" {
  description = "Instructions to get the kubeconfig file"
  value       = "SSH into the master node and copy /etc/rancher/k3s/k3s.yaml"
}

output "postgres_private_ip" {
  description = "Private IP of the Postgres node"
  value       = module.postgres.postgres_private_ip
}

output "postgres_public_ip" {
  description = "Public IP of the Postgres node"
  value       = module.postgres.postgres_public_ip
}

output "rabbitmq_private_ip" {
  description = "Private IP of the RabbitMQ node"
  value       = module.rabbitmq.rabbitmq_private_ip
}

output "rabbitmq_public_ip" {
  description = "Public IP of the RabbitMQ node"
  value       = module.rabbitmq.rabbitmq_public_ip
}

output "rabbitmq_amqp_url" {
  description = "AMQP connection URL for RabbitMQ (from private network)"
  value       = "amqp://${var.rabbitmq_user}:${var.rabbitmq_pass}@${module.rabbitmq.rabbitmq_private_ip}:5672"
  sensitive   = true
}

output "postgres_connection_string" {
  description = "PostgreSQL connection host and port"
  value       = "postgresql://${var.postgres_user}@${module.postgres.postgres_private_ip}:5432"
  sensitive   = true
}
