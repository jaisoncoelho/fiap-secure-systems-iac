output "network_id" {
  description = "ID of the private network"
  value       = hcloud_network.private_network.id
}
