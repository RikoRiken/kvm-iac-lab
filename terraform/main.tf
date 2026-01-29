terraform {
  required_version = ">= 1.5.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# =================================================================
# 1. NETWORKING - Physical architecture
# =================================================================

# 1.1 WAN Network (Simulated Internet) - with NAT
resource "libvirt_network" "wan" {
  name      = "wan-network"
  mode      = "nat"
  domain    = "wan.local"
  addresses = ["192.168.122.0/24"] # Standard Libvirt
  dhcp { enabled = true }
}

# 1.2 VLANs (Isolated networks)
# We create here multiple "virtual switches" for each area
# It's just "virtual cables", no NAT, no DHCP, the firewall will handle this

resource "libvirt_network" "mgmt" {
  name = "vlan-mgmt"
  mode = "none"
}

resource "libvirt_network" "dmz" {
  name = "vlan-dmz"
  mode = "none"
}

resource "libvirt_network" "prod" {
  name = "vlan-prod"
  mode = "none"
}

resource "libvirt_network" "backup" {
  name = "vlan-backup"
  mode = "none"
}

resource "libvirt_network" "monitor" {
  name = "vlan-monitor"
  mode = "none"
}

# =================================================================
# 2. STOCKAGE (STORAGE) - Les Disques Durs
# =================================================================

# 1.1 Default Debian ISO img (Downloaded from URL in variables.tf)
resource "libvirt_volume" "debian_base" {
  name   = "debian-base.qcow2"
  pool   = "default"
  source = var.debian_image_path
  format = "qcow2"
}

# 1.2 VMs disks (Cloned from the default image : "Copy-On-Write" process)

resource "libvirt_volume" "bastion_disk" {
  name           = "bastion.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 10737418240 # 10GB in bytes, not really 10GB stored locally, it's virutally allocated
}

resource "libvirt_volume" "proxy_disk" {
  name           = "proxy.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 10737418240 # 10GB
}

resource "libvirt_volume" "prod_disk" {
  name           = "prod.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 21474836480 # 20GB (Bigger for K3s and DB)
}

resource "libvirt_volume" "backup_disk" {
  name           = "backup.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 53687091200 # 50GB (Storage for backups)
}

resource "libvirt_volume" "monitor_disk" {
  name           = "monitor.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 21474836480 # 20GB (Logs Loki)
}

# 1.3 SPECIFIC CASE : OPNsense disk
# TODO : Il faudra placer manuellement l'image "opnsense.qcow2" dans /var/lib/libvirt/images
# ou créer un volume base comme pour Debian si tu as l'URL.
# Pour l'instant, création disque vide qu'on écrasera ou une réf vers une base.
resource "libvirt_volume" "fw_disk" {
  name   = "opnsense-fw.qcow2"
  pool   = "default"
  format = "qcow2"
  source = "/var/lib/libvirt/images/opnsense-base.qcow2" # <--- ATTENTION : image n'existe pas
}

# =================================================================
# 3. CONFIGURATION (CLOUD-INIT utilty)
# =================================================================

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    user    = var.ssh_username
    ssh_key = file(var.ssh_key_path)
    domain  = var.domain_name
  }
}

#Creating ISO file to configure each machine with hostname, ssh pub key...
resource "libvirt_cloudinit_disk" "bastion_init" {
  name      = "bastion-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { hostname = "vm-bastion", user = var.ssh_username, ssh_key = file(var.ssh_key_path), domain = var.domain_name })
  pool      = "default"
}

resource "libvirt_cloudinit_disk" "proxy_init" {
  name      = "proxy-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { hostname = "vm-proxy", user = var.ssh_username, ssh_key = file(var.ssh_key_path), domain = var.domain_name })
  pool      = "default"
}

resource "libvirt_cloudinit_disk" "prod_init" {
  name      = "prod-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { hostname = "vm-prod", user = var.ssh_username, ssh_key = file(var.ssh_key_path), domain = var.domain_name })
  pool      = "default"
}

resource "libvirt_cloudinit_disk" "backup_init" {
  name      = "backup-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { hostname = "vm-backup", user = var.ssh_username, ssh_key = file(var.ssh_key_path), domain = var.domain_name })
  pool      = "default"
}

resource "libvirt_cloudinit_disk" "monitor_init" {
  name      = "monitor-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { hostname = "vm-monitor", user = var.ssh_username, ssh_key = file(var.ssh_key_path), domain = var.domain_name })
  pool      = "default"
}

# =================================================================
# 4. VIRTUAL MACHINES (COMPUTE)
# =================================================================

# --- 1. Firewall ---
resource "libvirt_domain" "opnsense" {
  name   = "vm-fw"
  memory = var.vm_fw_ram
  vcpu   = 2

  disk { volume_id = libvirt_volume.fw_disk.id }

  # vtnet0/eth0 : WAN (Internet)
  network_interface { network_name = "wan-network" }

  # vtnet1/eth1 : LAN MGMT (VLAN 10)
  network_interface { network_name = "vlan-mgmt" }

  # vtnet2/eth2 : LAN DMZ (VLAN 20)
  network_interface { network_name = "vlan-dmz" }

  # vtnet3/eth3 : LAN PROD (VLAN 30)
  network_interface { network_name = "vlan-prod" }

  # vtnet4/eth4 : LAN BACKUP (VLAN 40)
  network_interface { network_name = "vlan-backup" }
  
  # vtnet5/eth5 : LAN MONITOR (VLAN 50)
  network_interface { network_name = "vlan-monitor" }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- B. Bastion (Zone MGMT) ---
resource "libvirt_domain" "bastion" {
  name   = "vm-bastion"
  memory = var.vm_bastion_ram
  vcpu   = 1
  cloudinit = libvirt_cloudinit_disk.bastion_init.id

  # Connecté uniquement au VLAN MGMT (Sécurité !)
  # L'accès SSH viendra du Port Forwarding d'OPNsense
  network_interface { 
    network_name = "vlan-mgmt" 
    wait_for_lease = false # Pas de DHCP Libvirt ici, c'est OPNsense qui donnera l'IP
  }

  disk { volume_id = libvirt_volume.bastion_disk.id }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- C. Proxy (Zone DMZ) ---
resource "libvirt_domain" "proxy" {
  name   = "vm-proxy"
  memory = var.vm_proxy_ram
  vcpu   = 1
  cloudinit = libvirt_cloudinit_disk.proxy_init.id

  network_interface { network_name = "vlan-dmz" }

  disk { volume_id = libvirt_volume.proxy_disk.id }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- D. Prod (Zone PROD) ---
resource "libvirt_domain" "prod" {
  name   = "vm-prod"
  memory = var.vm_prod_ram
  vcpu   = 2 # K3s a besoin d'un peu de CPU
  cloudinit = libvirt_cloudinit_disk.prod_init.id

  network_interface { network_name = "vlan-prod" }

  disk { volume_id = libvirt_volume.prod_disk.id }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- E. Backup (Zone BACKUP) ---
resource "libvirt_domain" "backup" {
  name   = "vm-backup"
  memory = var.vm_backup_ram
  vcpu   = 1
  cloudinit = libvirt_cloudinit_disk.backup_init.id

  network_interface { network_name = "vlan-backup" }

  disk { volume_id = libvirt_volume.backup_disk.id }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# --- F. Monitoring (Zone MONITOR) ---
resource "libvirt_domain" "monitor" {
  name   = "vm-monitor"
  memory = var.vm_monitor_ram
  vcpu   = 2
  cloudinit = libvirt_cloudinit_disk.monitor_init.id

  network_interface { network_name = "vlan-monitor" }

  disk { volume_id = libvirt_volume.monitor_disk.id }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}