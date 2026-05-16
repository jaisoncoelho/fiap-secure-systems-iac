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

      # Route internet traffic through master node NAT gateway (no public IP on this server).
      # The master node at 10.0.2.1 has a public IP and is configured as a NAT gateway.
      # Without this route, apt-get and curl calls would fail — there is no direct internet
      # access from this private-only node.
      echo "Configuring default route via NAT gateway (10.0.2.1)..."

      # Detect the private network interface by its assigned IP (10.0.2.2 for postgres).
      # Interface names on Hetzner Ubuntu 24.04 may be eth0/eth1 or enp1s0/ens10.
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

      # Use 'onlink' so the kernel accepts the gateway even though it's not in the
      # directly-connected subnet table entry for the private interface.
      ip route replace default via 10.0.2.1 dev "$PRIV_IF" onlink || true

      # Persist the default route across reboots using a systemd-networkd drop-in.
      # Ubuntu 24.04 uses systemd-networkd; /etc/network/interfaces is not available.
      mkdir -p /etc/systemd/network
      {
        echo "[Match]"
        echo "Name=$PRIV_IF"
        echo ""
        echo "[Route]"
        echo "Gateway=10.0.2.1"
        echo "GatewayOnLink=yes"
      } > /etc/systemd/network/10-hetzner-private-default-route.network
      systemctl restart systemd-networkd || true

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
      %{ endfor ~}

      echo "=== PostgreSQL Setup Completed Successfully at $(date) ==="
      touch /root/postgres-setup-complete
    permissions: "0755"

runcmd:
  - /root/setup-postgres.sh

final_message: "PostgreSQL server setup completed. Check /var/log/postgres-setup.log for details."
