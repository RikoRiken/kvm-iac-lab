# router_setup.tf
data "template_file" "router_user_data" {

  vars = {
    ssh_user = var.ssh_username
    ssh_key  = file(var.ssh_key_path)
  }

  template = <<EOF
#cloud-config
hostname: vm-fw
ssh_pwauth: false
disable_root: false

# --- AJOUT DE LA SECTION USER ---
users:
  - name: $${ssh_user}
    groups: sudo, admin
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $${ssh_key}

write_files:
  # 1. Empêcher le blocage du boot
  - path: /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
    content: |
      [Service]
      ExecStart=
      ExecStart=/usr/bin/true

  # 2. Config DNS pour que le routeur puisse télécharger les paquets
  - path: /etc/resolv.conf
    content: "nameserver 8.8.8.8"

  # 3. Pré-configuration de dnsmasq
  - path: /etc/dnsmasq.conf
    content: |
      interface=ens4,ens5,ens6,ens7,ens8
      bind-interfaces
      dhcp-option=6,8.8.8.8

      # Pour chaque interface, on définit le range ET la gateway (option 3)
      dhcp-range=interface:ens4,172.16.10.100,172.16.10.200,255.255.255.0,12h
      dhcp-option=interface:ens4,3,172.16.10.1

      dhcp-range=interface:ens5,172.16.20.100,172.16.20.200,255.255.255.0,12h
      dhcp-option=interface:ens5,3,172.16.20.1

      dhcp-range=interface:ens6,172.16.30.100,172.16.30.200,255.255.255.0,12h
      dhcp-option=interface:ens6,3,172.16.30.1

      dhcp-range=interface:ens7,172.16.40.100,172.16.40.200,255.255.255.0,12h
      dhcp-option=interface:ens7,3,172.16.40.1

      dhcp-range=interface:ens8,172.16.50.100,172.16.50.200,255.255.255.0,12h
      dhcp-option=interface:ens8,3,172.16.50.1

runcmd:
  # A. CONFIGURATION RÉSEAU (AVANT l'installation des services)
  - ip link set ens4 up && ip addr add 172.16.10.1/24 dev ens4 || true
  - ip link set ens5 up && ip addr add 172.16.20.1/24 dev ens5 || true
  - ip link set ens6 up && ip addr add 172.16.30.1/24 dev ens6 || true
  - ip link set ens7 up && ip addr add 172.16.40.1/24 dev ens7 || true
  - ip link set ens8 up && ip addr add 172.16.50.1/24 dev ens8 || true

  # B. INSTALLATION (Maintenant que le réseau local est prêt)
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq iptables-persistent net-tools qemu-guest-agent

  # C. ROUTAGE ET NAT (Ouverture des vannes pour les clients)
  - sysctl -w net.ipv4.ip_forward=1
  - iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
  - netfilter-persistent save

  # D. FORCE START (Dernière étape : on démarre le DHCP)
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
  - systemctl restart qemu-guest-agent
EOF
}