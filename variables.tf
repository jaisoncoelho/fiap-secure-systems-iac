variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "network_name" {
  description = "Name of the private network for the secure-systems cluster"
  type        = string
  default     = "secure-systems-network"
}

variable "github_username" {
  description = "GitHub username for container registry"
  type        = string
  default     = "ejklock"
}

variable "github_pat" {
  description = "GitHub Personal Access Token with read:packages scope"
  type        = string
  sensitive   = true
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to add to authorized_keys on all nodes"
  type        = list(string)
  default     = []
}

variable "ssh_private_key" {
  description = "SSH private key for accessing nodes (used for provisioning if needed)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_user" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "fiap"
}

variable "postgres_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "database_names" {
  description = "List of database names to create on the Postgres server"
  type        = list(string)
  default     = ["fiap_upload", "fiap_processing", "fiap_report"]
}

variable "rabbitmq_user" {
  description = "RabbitMQ admin username"
  type        = string
  default     = "admin"
}

variable "rabbitmq_pass" {
  description = "RabbitMQ admin password"
  type        = string
  sensitive   = true
}
