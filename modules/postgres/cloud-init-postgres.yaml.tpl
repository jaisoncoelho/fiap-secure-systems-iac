#cloud-config
manage_resolv_conf: true
resolv_conf:
  nameservers:
    - "8.8.8.8"
    - "8.8.4.4"
    - "1.1.1.1"

packages:
  - fail2ban
  - curl
  - apt-transport-https
  - gnupg

write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [DEFAULT]
      bantime = 3600
      findtime = 600
      maxretry = 5

      [sshd]
      enabled = true
      port = ssh
      logpath = %(sshd_log)s
      maxretry = 3
      bantime = 7200
    permissions: "0644"

  - path: /root/setup-postgres.sh
    content: |
      #!/bin/bash
      set -e

      exec &> >(tee -a /var/log/postgres-setup.log)

      echo "=== PostgreSQL Setup Started at $(date) ==="

      export DEBIAN_FRONTEND=noninteractive
      export NEEDRESTART_MODE=a

      # Install PostgreSQL 16 from official apt repo
      echo "Adding PostgreSQL apt repository..."
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

      apt-get update -y
      apt-get install -y postgresql-16

      echo "PostgreSQL 16 installed successfully."

      # Configure listen_addresses to accept connections from private network
      PG_CONF=/etc/postgresql/16/main/postgresql.conf
      PG_HBA=/etc/postgresql/16/main/pg_hba.conf

      sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF

      # Allow password auth from private network
      echo "host    all             all             10.0.0.0/8              md5" >> $PG_HBA

      # Restart to apply config
      systemctl restart postgresql

      echo "Configuring PostgreSQL user and databases..."

      PG_USER="${postgres_user}"
      PG_PASS="${postgres_password}"

      # Create the application user
      sudo -u postgres psql -c "CREATE USER $${PG_USER} WITH PASSWORD '$${PG_PASS}';" || true

      # Create databases and grant privileges
      %{ for db in database_names ~}
      sudo -u postgres psql -c "CREATE DATABASE ${db};" || true
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${db} TO $${PG_USER};" || true
      %{ endfor ~}

      echo "=== PostgreSQL Setup Completed Successfully at $(date) ==="
      touch /root/postgres-setup-complete
    permissions: "0755"

runcmd:
  - /root/setup-postgres.sh

final_message: "PostgreSQL server setup completed. Check /var/log/postgres-setup.log for details."
