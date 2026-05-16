module "network" {
  source       = "./modules/network"
  network_name = var.network_name
}

module "cluster" {
  source             = "./modules/cluster"
  private_network_id = module.network.network_id
  github_username    = var.github_username
  github_pat         = var.github_pat
  ssh_public_keys    = var.ssh_public_keys
  ssh_private_key    = var.ssh_private_key
}

module "postgres" {
  source             = "./modules/postgres"
  private_network_id = module.network.network_id
  ssh_public_keys    = var.ssh_public_keys
  postgres_user      = var.postgres_user
  postgres_password  = var.postgres_password
  database_names     = var.database_names

  depends_on = [hcloud_network_route.nat_gateway]
}

module "rabbitmq" {
  source             = "./modules/rabbitmq"
  private_network_id = module.network.network_id
  ssh_public_keys    = var.ssh_public_keys
  rabbitmq_user      = var.rabbitmq_user
  rabbitmq_pass      = var.rabbitmq_pass

  depends_on = [hcloud_network_route.nat_gateway]
}

# Route all internet-bound traffic from private nodes through the master node NAT gateway.
# Hetzner's SDN requires an explicit hcloud_network_route to deliver packets destined for
# 0.0.0.0/0 from private-only nodes (Postgres, RabbitMQ) to the master (10.0.2.1).
# Without this, internet-bound packets from private nodes would be dropped by the SDN.
resource "hcloud_network_route" "nat_gateway" {
  network_id  = module.network.network_id
  destination = "0.0.0.0/0"
  gateway     = "10.0.2.1"

  depends_on = [module.cluster, module.network]
}

# ---------------------------------------------------------------------------
# Health checks — verify services are running on private nodes.
# These run from the master node (via SSH) since private nodes have no public IP.
# If a check fails, terraform apply fails with a clear error message.
# ---------------------------------------------------------------------------

resource "null_resource" "verify_postgres" {
  depends_on = [module.postgres, module.cluster]

  provisioner "remote-exec" {
    inline = [
      "echo '=== Waiting for PostgreSQL on ${module.postgres.postgres_private_ip} ==='",
      "for i in $(seq 1 30); do if timeout 2 bash -c \"echo > /dev/tcp/${module.postgres.postgres_private_ip}/5432\" 2>/dev/null; then echo '=== PostgreSQL is ready! ==='; exit 0; fi; echo \"Attempt $i/30 — waiting 20s...\"; sleep 20; done",
      "echo 'ERROR: PostgreSQL not reachable on port 5432 after 10 minutes'",
      "exit 1",
    ]
    connection {
      type        = "ssh"
      user        = "cluster"
      private_key = var.ssh_private_key
      host        = module.cluster.master_node_public_ip
      timeout     = "15m"
    }
  }
}

resource "null_resource" "verify_rabbitmq" {
  depends_on = [module.rabbitmq, module.cluster]

  provisioner "remote-exec" {
    inline = [
      "echo '=== Waiting for RabbitMQ on ${module.rabbitmq.rabbitmq_private_ip} ==='",
      "for i in $(seq 1 30); do if timeout 2 bash -c \"echo > /dev/tcp/${module.rabbitmq.rabbitmq_private_ip}/5672\" 2>/dev/null; then echo '=== RabbitMQ is ready! ==='; exit 0; fi; echo \"Attempt $i/30 — waiting 20s...\"; sleep 20; done",
      "echo 'ERROR: RabbitMQ not reachable on port 5672 after 10 minutes'",
      "exit 1",
    ]
    connection {
      type        = "ssh"
      user        = "cluster"
      private_key = var.ssh_private_key
      host        = module.cluster.master_node_public_ip
      timeout     = "15m"
    }
  }
}

resource "null_resource" "verify_workers" {
  depends_on = [module.cluster]

  provisioner "remote-exec" {
    inline = [
      "echo '=== Waiting for worker nodes to join K3s cluster ==='",
      "for i in $(seq 1 30); do NODES=$(sudo kubectl get nodes --kubeconfig=/etc/rancher/k3s/k3s.yaml --no-headers 2>/dev/null | wc -l); if [ \"$NODES\" -ge 2 ]; then echo \"=== $NODES nodes in cluster — workers joined! ===\"; sudo kubectl get nodes --kubeconfig=/etc/rancher/k3s/k3s.yaml; exit 0; fi; echo \"Attempt $i/30 — $NODES node(s) so far, waiting 20s...\"; sleep 20; done",
      "echo 'ERROR: Worker nodes did not join the cluster after 10 minutes'",
      "sudo kubectl get nodes --kubeconfig=/etc/rancher/k3s/k3s.yaml || true",
      "exit 1",
    ]
    connection {
      type        = "ssh"
      user        = "cluster"
      private_key = var.ssh_private_key
      host        = module.cluster.master_node_public_ip
      timeout     = "15m"
    }
  }
}
