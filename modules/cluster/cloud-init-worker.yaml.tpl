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
  - apt-get update -y
  # Configure routing for Hetzner private network
  - ip route add 10.0.0.0/8 dev eth1 || true
  - echo "10.0.0.0/8 dev eth1" >> /etc/dhcp/dhclient-exit-hooks.d/hetzner-routes || true
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
