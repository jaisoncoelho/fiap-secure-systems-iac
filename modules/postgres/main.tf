terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.52.0"
    }
  }
}

resource "hcloud_firewall" "postgres_firewall" {
  name = "postgres-firewall"

  # SSH access — private network only (no public IP; access via jump host through master)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "10.0.0.0/8"
    ]
  }

  # ICMP (ping) — private network only
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "10.0.0.0/8"
    ]
  }

  # PostgreSQL port — private network only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "5432"
    source_ips = [
      "10.0.0.0/8"
    ]
  }
}

resource "hcloud_server" "postgres" {
  name         = "postgres-node"
  image        = "ubuntu-24.04"
  server_type  = "cx23"
  location     = "fsn1"
  firewall_ids = [hcloud_firewall.postgres_firewall.id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = var.private_network_id
    # Static IP for the Postgres server
    ip = "10.0.2.2"
  }

  user_data = templatefile("${path.module}/cloud-init-postgres.yaml.tpl", {
    ssh_public_keys   = var.ssh_public_keys
    postgres_user     = var.postgres_user
    postgres_password = var.postgres_password
    database_names    = var.database_names
  })
}
