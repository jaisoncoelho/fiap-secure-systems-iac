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

  - path: /root/setup-rabbitmq.sh
    content: |
      #!/bin/bash
      set -e

      # Redireciona tudo para o log
      exec &> >(tee -a /var/log/rabbitmq-setup.log)

      echo "=== RabbitMQ Setup Started at $(date) ==="

      # Route internet traffic through master node NAT gateway (no public IP on this server).
      # The master node at 10.0.2.1 has a public IP and is configured as a NAT gateway.
      # Without this route, apt-get and curl calls would fail — there is no direct internet
      # access from this private-only node.
      echo "Configuring default route via NAT gateway (10.0.2.1)..."
      ip route replace default via 10.0.2.1 || true

      # Persist the default route across reboots using a systemd-networkd drop-in.
      # Ubuntu 24.04 uses systemd-networkd; /etc/network/interfaces is not available.
      mkdir -p /etc/systemd/network
      cat > /etc/systemd/network/10-hetzner-private-default-route.network <<NETCFG
      [Match]
      Name=eth0

      [Route]
      Gateway=10.0.2.1
      GatewayOnLink=yes
      NETCFG
      systemctl restart systemd-networkd || true

      # Hetzner Cloud PAM workaround: Hetzner provisions servers with PAM requiring
      # a password change on first login. Package post-install scripts that invoke
      # chfn/adduser will fail because root's password is marked as expired.
      # Setting the last-password-change date to today clears the expiration flag.
      chage -d "$(date +%Y-%m-%d)" root || true

      # Fix PAM issue that prevents RabbitMQ installation
      echo "Configuring system for RabbitMQ installation..."

      # Pre-create rabbitmq user with home directory to avoid PAM issues during package install
      if ! id rabbitmq &>/dev/null; then
        useradd -r -m -d /var/lib/rabbitmq -s /bin/bash rabbitmq
      fi

      # Ensure home directory exists with correct permissions
      mkdir -p /var/lib/rabbitmq
      chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
      chmod 755 /var/lib/rabbitmq

      # Disable password expiry for rabbitmq user
      chage -I -1 -m 0 -M 99999 -E -1 rabbitmq 2>/dev/null || true

      # Install prerequisites
      echo "Installing prerequisites..."
      export DEBIAN_FRONTEND=noninteractive
      export NEEDRESTART_MODE=a

      ## Team RabbitMQ's signing key
      curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null

      ## Add apt repositories maintained by Team RabbitMQ
      sudo tee /etc/apt/sources.list.d/rabbitmq.list <<EOF

      ## Modern Erlang/OTP releases ##

      deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/noble noble main
      deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/ubuntu/noble noble main

      ## Latest RabbitMQ releases ##
      deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/noble noble main
      deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/ubuntu/noble noble main
      EOF

      ## Update package indices
      sudo apt-get update -y

      ## Install Erlang packages
      sudo apt-get install -y erlang-base \
                            erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
                            erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
                            erlang-runtime-tools erlang-snmp erlang-ssl \
                            erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl
      ## Install rabbitmq-server and its dependencies
      sudo apt-get install rabbitmq-server -y --fix-missing

      # Verify RabbitMQ is installed
      if ! command -v rabbitmqctl &> /dev/null; then
        echo "ERROR: RabbitMQ installation failed!"
        exit 1
      fi

      echo "RabbitMQ installed successfully!"

      # Enable and start RabbitMQ
      echo "Starting RabbitMQ..."
      systemctl enable rabbitmq-server
      systemctl start rabbitmq-server
      sleep 10

      # Verify RabbitMQ is running
      if ! systemctl is-active --quiet rabbitmq-server; then
        echo "ERROR: RabbitMQ failed to start!"
        systemctl status rabbitmq-server
        exit 1
      fi

      # Enable management plugin
      echo "Enabling RabbitMQ management plugin..."
      rabbitmq-plugins enable rabbitmq_management

      # Wait for plugins to load
      sleep 5
      systemctl restart rabbitmq-server
      sleep 10

      # Create admin user
      echo "Creating admin user..."
      rabbitmqctl add_user ${rabbitmq_user} ${rabbitmq_pass} || true
      rabbitmqctl set_user_tags ${rabbitmq_user} administrator
      rabbitmqctl set_permissions -p / ${rabbitmq_user} ".*" ".*" ".*"

      # Delete guest user for security
      echo "Deleting guest user..."
      rabbitmqctl delete_user guest || true

      # Show users
      echo "Current RabbitMQ users:"
      rabbitmqctl list_users

      # Check listening ports
      echo "RabbitMQ listening on:"
      ss -tlnp | grep beam || netstat -tlnp | grep beam

      echo "=== RabbitMQ Setup Completed Successfully at $(date) ==="
      touch /root/rabbitmq-setup-complete
    permissions: "0755"

runcmd:
  - /root/setup-rabbitmq.sh

final_message: "RabbitMQ server setup completed. Check /var/log/rabbitmq-setup.log for details."
