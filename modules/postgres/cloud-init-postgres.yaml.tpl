#cloud-config
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

      # Route internet traffic through the Hetzner SDN gateway (10.0.0.1).
      # This private-only node has no public IP. The hcloud_network_route in Terraform
      # tells the SDN to forward 0.0.0.0/0 traffic to the master node (10.0.2.1),
      # which then NAT-masquerades it to the internet.
      #
      # IMPORTANT: We route via the SDN gateway (10.0.0.1), NOT directly via the master
      # (10.0.2.1), because Hetzner assigns /32 IPs on private interfaces — nodes cannot
      # ARP for each other directly. Only the SDN gateway (10.0.0.1) has a valid ARP entry.
      echo "Configuring default route via Hetzner SDN gateway (10.0.0.1)..."

      # Detect the private network interface by its assigned IP (10.0.2.2 for postgres).
      # Interface names on Hetzner Ubuntu 24.04 may be eth0/eth1 or enp1s0/enp7s0.
      PRIV_IP="10.0.2.2"
      PRIV_IF=""
      for attempt in $(seq 1 30); do
        PRIV_IF=$(ip -o addr show | awk -v ip="$PRIV_IP" '$4 ~ "^" ip "/" {print $2}')
        if [ -n "$PRIV_IF" ]; then
          echo "Found private interface: $PRIV_IF (attempt $attempt)"
          break
        fi
        echo "Waiting for interface with IP $PRIV_IP (attempt $attempt/30)..."
        sleep 2
      done

      if [ -z "$PRIV_IF" ]; then
        echo "ERROR: Could not find network interface with IP $PRIV_IP after 30 attempts" >&2
        exit 1
      fi

      ip route replace default via 10.0.0.1 dev "$PRIV_IF" || true

      # Configure DNS via systemd-resolved drop-in.
      # cloud-init's manage_resolv_conf does NOT work on Ubuntu 24.04 because
      # /etc/resolv.conf is a symlink to systemd-resolved's stub (127.0.0.53).
      mkdir -p /etc/systemd/resolved.conf.d
      {
        echo "[Resolve]"
        echo "DNS=8.8.8.8 8.8.4.4 1.1.1.1"
      } > /etc/systemd/resolved.conf.d/dns.conf
      systemctl restart systemd-resolved || true

      # Persist the default route across reboots via networkd-dispatcher.
      # IMPORTANT: Do NOT create a systemd-networkd .network file — it would
      # override Hetzner's existing network config and strip the private IP
      # from the interface.
      mkdir -p /etc/networkd-dispatcher/routable.d
      {
        echo '#!/bin/bash'
        echo "ip route replace default via 10.0.0.1 dev $PRIV_IF 2>/dev/null || true"
      } > /etc/networkd-dispatcher/routable.d/50-nat-default-route.sh
      chmod +x /etc/networkd-dispatcher/routable.d/50-nat-default-route.sh

      export DEBIAN_FRONTEND=noninteractive
      export NEEDRESTART_MODE=a

      # Hetzner Cloud PAM workaround: Hetzner provisions servers with PAM requiring
      # a password change on first login. When apt installs postgresql-16, the
      # postgresql-common post-install script runs `chfn` to set the postgres
      # system user's GECOS field. chfn invokes PAM, which rejects the call because
      # root's password is marked as expired — causing the install to fail with:
      #   "chfn: PAM: Authentication token is no longer valid; new one required"
      # Setting the last-password-change date to today clears the expiration flag
      # without altering the actual password.
      chage -d "$(date +%Y-%m-%d)" root || true

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
      sudo -u postgres psql -d ${db} -c "GRANT ALL ON SCHEMA public TO $${PG_USER};" || true
      %{ endfor ~}

      echo "=== PostgreSQL Setup Completed Successfully at $(date) ==="
      touch /root/postgres-setup-complete
    permissions: "0755"

runcmd:
  - /root/setup-postgres.sh

final_message: "PostgreSQL server setup completed. Check /var/log/postgres-setup.log for details."
