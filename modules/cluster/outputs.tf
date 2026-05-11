output "master_node_public_ip" {
  description = "Public IP address of the master node"
  value       = hcloud_server.master-node.ipv4_address
}
