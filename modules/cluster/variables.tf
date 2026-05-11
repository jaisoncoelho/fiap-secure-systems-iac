variable "private_network_id" {
  type = string
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
  description = "List of SSH public keys to add to authorized_keys"
  type        = list(string)
  default     = []
}

variable "ssh_private_key" {
  description = "SSH private key for node-to-node communication"
  type        = string
  sensitive   = true
  default     = ""
}
