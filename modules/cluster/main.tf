terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.52.0"
    }
  }
}

resource "hcloud_firewall" "master_node_firewall" {
  name = "secure-systems-master-node-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "1-65535"
    source_ips = [
      "10.0.0.0/8"
    ]
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "1-65535"
    source_ips = [
      "10.0.0.0/8"
    ]
  }
}

resource "hcloud_server" "master-node" {
  name         = "secure-systems-master-node"
  image        = "ubuntu-24.04"
  server_type  = "cx23"
  location     = "fsn1"
  firewall_ids = [hcloud_firewall.master_node_firewall.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = var.private_network_id
    # Static IP for the master node — workers join via 10.0.2.1
    ip = "10.0.2.1"
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_public_keys = var.ssh_public_keys
    github_username = var.github_username
    github_pat      = var.github_pat
  })
}

resource "hcloud_server" "worker-nodes" {
  count = 1

  # The name will be secure-systems-worker-node-0
  name        = "secure-systems-worker-node-${count.index}"
  image       = "ubuntu-24.04"
  server_type = "cx23"
  location    = "fsn1"

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = var.private_network_id
    # Static IP to avoid conflicts with other private nodes (postgres=10.0.2.2, rabbitmq=10.0.2.10)
    ip = "10.0.2.${count.index + 20}"
  }

  user_data = templatefile("${path.module}/cloud-init-worker.yaml.tpl", {
    ssh_public_keys = var.ssh_public_keys
    ssh_private_key = var.ssh_private_key
    master_ip       = hcloud_server.master-node.network.*.ip[0]
    github_username = var.github_username
    github_pat      = var.github_pat
  })

  depends_on = [hcloud_server.master-node]
}
