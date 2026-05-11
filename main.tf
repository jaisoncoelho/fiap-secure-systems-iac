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
}

module "rabbitmq" {
  source             = "./modules/rabbitmq"
  private_network_id = module.network.network_id
  ssh_public_keys    = var.ssh_public_keys
  rabbitmq_user      = var.rabbitmq_user
  rabbitmq_pass      = var.rabbitmq_pass
}
