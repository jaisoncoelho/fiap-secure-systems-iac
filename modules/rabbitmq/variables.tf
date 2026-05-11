variable "private_network_id" {
  description = "ID of the private network"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public keys"
  type        = list(string)
}

variable "rabbitmq_user" {
  description = "RabbitMQ admin username"
  type        = string
}

variable "rabbitmq_pass" {
  description = "RabbitMQ admin password"
  type        = string
  sensitive   = true
}
