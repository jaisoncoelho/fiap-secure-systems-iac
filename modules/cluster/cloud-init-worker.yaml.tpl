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

runcmd:
  # Configure DNS via systemd-resolved (Ubuntu 24.04 stub resolver has no upstream on private-only nodes)
  - mkdir -p /etc/systemd/resolved.conf.d
  - echo -e "[Resolve]\nDNS=8.8.8.8 8.8.4.4 1.1.1.1" > /etc/systemd/resolved.conf.d/dns.conf
  - systemctl restart systemd-resolved || true
  # Ensure default route via Hetzner SDN gateway (not direct to master — /32 IPs can't ARP directly)
  - "PRIV_IF=$(ip -o addr show | awk '$3 == \"inet\" && $4 ~ \"^10\\\\.0\\\\.\" {print $2; exit}')"
  - "[ -n \"$PRIV_IF\" ] && ip route replace default via 10.0.0.1 dev $PRIV_IF || true"
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
