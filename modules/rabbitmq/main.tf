terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.52.0"
    }
  }
}

resource "hcloud_firewall" "rabbitmq_firewall" {
  name = "rabbitmq-firewall"

  # SSH access
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # ICMP (ping)
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # RabbitMQ AMQP port (5672) — private network only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "5672"
    source_ips = [
      "10.0.0.0/8"
    ]
  }

  # RabbitMQ Management UI (15672)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "15672"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # RabbitMQ epmd (4369) — private network only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "4369"
    source_ips = [
      "10.0.0.0/8"
    ]
  }

  # RabbitMQ distribution port (25672) — private network only
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "25672"
    source_ips = [
      "10.0.0.0/8"
    ]
  }
}

resource "hcloud_server" "rabbitmq" {
  name         = "rabbitmq-node"
  image        = "ubuntu-24.04"
  server_type  = "cx22"
  location     = "fsn1"
  firewall_ids = [hcloud_firewall.rabbitmq_firewall.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = var.private_network_id
    # Static IP for the RabbitMQ server
    ip = "10.0.2.10"
  }

  user_data = templatefile("${path.module}/cloud-init-rabbitmq.yaml.tpl", {
    ssh_public_keys = var.ssh_public_keys
    rabbitmq_user   = var.rabbitmq_user
    rabbitmq_pass   = var.rabbitmq_pass
  })
}
