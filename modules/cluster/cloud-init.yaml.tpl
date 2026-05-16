#cloud-config
packages:
  - curl
  - fail2ban
  - ufw
users:
  - name: cluster
    ssh-authorized-keys: ${jsonencode(ssh_public_keys)}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash

write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [DEFAULT]
      bantime = 3600
      findtime = 600
      maxretry = 5
      destemail = admin@localhost
      sendername = Fail2Ban
      action = %(action_mwl)s

      [sshd]
      enabled = true
      port = ssh
      logpath = %(sshd_log)s
      maxretry = 3
      bantime = 7200

      [traefik-auth]
      enabled = true
      port = http,https
      filter = traefik-auth
      logpath = /var/log/traefik-access.log
      maxretry = 3
      bantime = 3600

      [traefik-exploits]
      enabled = true
      port = http,https
      filter = traefik-exploits
      logpath = /var/log/traefik-access.log
      maxretry = 2
      bantime = 7200

      [traefik-badbots]
      enabled = true
      port = http,https
      filter = traefik-badbots
      logpath = /var/log/traefik-access.log
      maxretry = 2
      bantime = 7200

      [traefik-scan]
      enabled = true
      port = http,https
      filter = traefik-scan
      logpath = /var/log/traefik-access.log
      maxretry = 1
      bantime = 86400
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/traefik-auth.conf
    content: |
      [Definition]
      failregex = ^<HOST> - \S+ \[.*\] "\S+ \S+ \S+" (401|403) .*$
      ignoreregex =
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/traefik-exploits.conf
    content: |
      [Definition]
      failregex = ^<HOST> .*"(GET|POST|HEAD).*(\.\.|\.php|\.asp|\.exe|\.pl|\.cgi|\.scgi|union.*select|select.*from|insert.*into|delete.*from|drop.*table|update.*set|\.\./\.\./|<script|javascript:|eval\(|base64_decode).*" (4\d{2}|5\d{2}) .*$
      ignoreregex =
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/traefik-badbots.conf
    content: |
      [Definition]
      badbotscustom = (libwww-perl|wget|python|nikto|scan|java|winhttp|HTTrack|clshttp|loader|email|harvest|extract|grab|miner|suck|reaper|leach|curl|pycurl)
      failregex = ^<HOST> - \S+ \[.*\] ".*" .* .* ".*%(badbotscustom)s.*"$
      ignoreregex =
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/traefik-scan.conf
    content: |
      [Definition]
      failregex = ^<HOST> .*"(GET|POST).*(\/\.env|\/\.git\/|\/wp-admin|\/wp-login|\/phpMyAdmin|\/admin\/|\/administrator|\/api\/|\/graphql).*" (4\d{2}|5\d{2}) .*$
      ignoreregex =
    permissions: "0644"

  - path: /usr/local/bin/setup-traefik-logs.sh
    content: |
      #!/bin/bash
      # Script para configurar logging do Traefik
      echo "Configurando logging do Traefik..."

      # Aguarda o Traefik estar rodando
      sleep 30
      while ! kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik &>/dev/null; do
        echo "Aguardando Traefik..."
        sleep 10
      done

      # Configura o Traefik para salvar logs em arquivo
      kubectl patch deployment traefik -n kube-system --type='json' -p='[
        {
          "op": "add",
          "path": "/spec/template/spec/containers/0/args/-",
          "value": "--accesslog=true"
        },
        {
          "op": "add",
          "path": "/spec/template/spec/containers/0/args/-",
          "value": "--accesslog.filepath=/var/log/traefik-access.log"
        }
      ]' || true

      # Cria um cronjob para copiar logs do pod para o host
      cat <<'EOF' > /etc/cron.d/traefik-logs
      */5 * * * * root /usr/local/bin/sync-traefik-logs.sh >/dev/null 2>&1
      EOF
      chmod 644 /etc/cron.d/traefik-logs
    permissions: "0755"

  - path: /usr/local/bin/sync-traefik-logs.sh
    content: |
      #!/bin/bash
      # Sincroniza logs do Traefik do pod para o host
      POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
      if [ -n "$POD" ]; then
        kubectl logs -n kube-system $POD --tail=1000 2>/dev/null | grep -E '"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)' >> /var/log/traefik-access.log 2>&1 || true
      fi
    permissions: "0755"

  - path: /etc/fail2ban/filter.d/nginx-noscript.conf
    content: |
      [Definition]
      failregex = ^<HOST> -.*GET.*(\.\.|\.php|\.\.\.|\.\.%00|\.asp|\.exe|\.pl|\.cgi|\.scgi)
      ignoreregex =
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/nginx-badbots.conf
    content: |
      [Definition]
      badbots = EmailCollector|WebEMailExtrac|TrackBack/1\.02|sogou music spider
      failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*"(?:%(badbots)s|.*drop table|.*select.*from|.*union.*select|.*and.*1=1|.*or.*1=1)
      ignoreregex =
    permissions: "0644"

  - path: /etc/fail2ban/filter.d/nginx-noproxy.conf
    content: |
      [Definition]
      failregex = ^<HOST> -.*GET http.*
      ignoreregex =
    permissions: "0644"

  - path: /etc/sysctl.d/99-nat-gateway.conf
    content: |
      # Enable IP forwarding so this master node can act as a NAT gateway
      # for private-only nodes (Postgres, RabbitMQ) that have no public IP.
      net.ipv4.ip_forward = 1
    permissions: "0644"

  - path: /usr/local/bin/setup-nat-gateway.sh
    content: |
      #!/bin/bash
      # Configure this master node as a NAT gateway for private-network nodes.
      # Private nodes (Postgres at 10.0.2.2, RabbitMQ at 10.0.2.10) have no
      # public IP and route internet traffic through this node (10.0.2.1).
      # Rules are injected into /etc/ufw/before.rules so they survive UFW restarts.

      set -e

      # Detect the public interface: the one with a non-private, non-loopback IPv4 address.
      # IMPORTANT: filter $3 == "inet" to skip inet6 lines — otherwise the IPv6 loopback
      # address (::1/128) matches first and PUB_IF is set to "lo", breaking MASQUERADE.
      # On Hetzner, interface names may be eth0/eth1 or enp1s0/ens10 depending on
      # the server type and kernel version.
      PUB_IF=$(ip -o addr show | awk '$3 == "inet" && $4 !~ "^10\." && $4 !~ "^127\." {print $2; exit}')
      if [ -z "$PUB_IF" ]; then
        echo "WARNING: Could not detect public interface, falling back to eth0"
        PUB_IF="eth0"
      fi
      echo "Detected public interface: $PUB_IF"

      # Detect the private interface: the one with the 10.0.2.1 address (master node IP).
      PRIV_IF=$(ip -o addr show | awk '$4 ~ "^10\.0\.2\.1/" {print $2}')
      if [ -z "$PRIV_IF" ]; then
        echo "WARNING: Could not detect private interface, falling back to eth1"
        PRIV_IF="eth1"
      fi
      echo "Detected private interface: $PRIV_IF"

      # Apply sysctl immediately
      sysctl -p /etc/sysctl.d/99-nat-gateway.conf

      # Set UFW default forward policy to ACCEPT
      sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

      # Add route for private network via detected interface and persist across reboots
      ip route add 10.0.0.0/8 dev "$PRIV_IF" || true
      mkdir -p /etc/dhcp
      echo "10.0.0.0/8 dev $PRIV_IF" >> /etc/dhcp/dhclient-exit-hooks.d/hetzner-routes || true

      # Inject NAT MASQUERADE rules into /etc/ufw/before.rules BEFORE the filter table.
      # Only inject once (idempotent check).
      if ! grep -q 'MASQUERADE' /etc/ufw/before.rules; then
        # Prepend the NAT table section at the very top of before.rules
        TMP=$(mktemp)
        {
          echo "# NAT table — MASQUERADE outbound traffic from private network via public interface ($PUB_IF)"
          echo "# This enables private-only nodes to reach the internet through this NAT gateway."
          echo "*nat"
          echo ":POSTROUTING ACCEPT [0:0]"
          echo "-A POSTROUTING -s 10.0.0.0/16 -o $PUB_IF -j MASQUERADE"
          echo "COMMIT"
          echo ""
        } > "$TMP"
        cat /etc/ufw/before.rules >> "$TMP"
        mv "$TMP" /etc/ufw/before.rules
      fi
    permissions: "0755"

runcmd:
  - apt-get update -y
  # Private network route is now configured inside setup-nat-gateway.sh
  # Generate SSH key for cluster user to access other nodes
  - sudo -u cluster ssh-keygen -t ed25519 -f /home/cluster/.ssh/id_ed25519 -N ""
  - sudo -u cluster cat /home/cluster/.ssh/id_ed25519.pub > /tmp/master-node-key.pub
  # Disable strict host key checking for private network
  - sudo -u cluster bash -c 'echo "Host 10.0.*" > /home/cluster/.ssh/config'
  - sudo -u cluster bash -c 'echo "  StrictHostKeyChecking no" >> /home/cluster/.ssh/config'
  - sudo -u cluster bash -c 'echo "  UserKnownHostsFile=/dev/null" >> /home/cluster/.ssh/config'
  - chmod 600 /home/cluster/.ssh/config
  - chown cluster:cluster /home/cluster/.ssh/config
  # Set up NAT gateway BEFORE ufw is enabled
  - /usr/local/bin/setup-nat-gateway.sh
  # Configure UFW firewall
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ssh
  - ufw allow 6443/tcp
  - ufw allow 10250/tcp
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw --force enable
  # Start and enable fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban
  # Install K3s with flannel vxlan backend
  - curl https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=vxlan --cluster-cidr=10.42.0.0/16 --service-cidr=10.43.0.0/16" sh -
  - chown cluster:cluster /etc/rancher/k3s/k3s.yaml
  - chown cluster:cluster /var/lib/rancher/k3s/server/node-token
  # Configure Traefik logging and log synchronization
  - /usr/local/bin/setup-traefik-logs.sh &
  - touch /var/log/traefik-access.log
  - chmod 644 /var/log/traefik-access.log
  # Install Helm
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  # Wait for K3s to be ready
  - sleep 30
  - bash -c 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && while ! kubectl get nodes &>/dev/null; do echo "Waiting for K3s..."; sleep 10; done'
  # Configure GHCR docker login for image pulls
  - export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  - mkdir -p /root/.docker
  - echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$(echo -n "${github_username}:${github_pat}" | base64)\"}}}" > /root/.docker/config.json
  - kubectl create secret docker-registry ghcr-secret --docker-server=ghcr.io --docker-username=${github_username} --docker-password=${github_pat} --namespace=default || true
