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
  - path: /root/.ssh/id_rsa
    content: |
      ${indent(6, ssh_private_key)}
    permissions: "0600"

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

  - path: /usr/local/bin/setup-worker-network.sh
    content: |
      #!/bin/bash
      # Configure DNS — systemd-resolved stub (127.0.0.53) has no upstream DNS
      # configured on private-only nodes (no DHCP from public network).
      mkdir -p /etc/systemd/resolved.conf.d
      echo -e "[Resolve]\nDNS=8.8.8.8 8.8.4.4 1.1.1.1" > /etc/systemd/resolved.conf.d/dns.conf
      systemctl restart systemd-resolved || true

      # Ensure default route via Hetzner SDN gateway.
      # Private nodes use /32 IPs and cannot ARP for other nodes directly.
      # Route through the SDN gateway (10.0.0.1) — the hcloud_network_route
      # tells the SDN to forward 0.0.0.0/0 traffic to the master for NAT.
      PRIV_IF=$(ip -o -4 addr show | awk '$4 ~ "^10\.0\." {print $2; exit}')
      if [ -n "$PRIV_IF" ]; then
        echo "Detected private interface: $PRIV_IF"
        ip route replace default via 10.0.0.1 dev "$PRIV_IF" || true
      else
        echo "WARNING: Could not detect private interface, skipping route setup"
      fi
    permissions: "0755"

runcmd:
  - /usr/local/bin/setup-worker-network.sh
  - apt-get update -y
  # Configure UFW firewall — allow all traffic from private network
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow from 10.0.0.0/8
  - ufw --force enable
  # Start and enable fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban
  # Wait for the master node to be ready
  - until curl -k https://${master_ip}:6443; do sleep 5; done
  # Copy the K3s token from the master node via SSH
  - REMOTE_TOKEN=$(ssh -o StrictHostKeyChecking=accept-new cluster@${master_ip} sudo cat /var/lib/rancher/k3s/server/node-token)
  # Install k3s worker and join the cluster
  - curl -sfL https://get.k3s.io | K3S_URL=https://${master_ip}:6443 K3S_TOKEN=$REMOTE_TOKEN sh -
