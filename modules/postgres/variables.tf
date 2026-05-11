variable "private_network_id" {
  description = "ID of the private network"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public keys"
  type        = list(string)
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
  description = "List of database names to create"
  type        = list(string)
  default     = ["fiap_upload", "fiap_processing", "fiap_report"]
}
