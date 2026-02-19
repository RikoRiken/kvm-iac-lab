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
  addresses = ["192.168.122.0/24"]
  dhcp { enabled = true }
  dns { enabled = true } 
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

resource "libvirt_volume" "router_disk" {
  name           = "router-disk.qcow2"
  base_volume_id = libvirt_volume.debian_base.id
  pool           = "default"
  size           = 5368709120 # 5 Go 
}

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

# =================================================================
# 3. CONFIGURATION (CLOUD-INIT utilty)
# =================================================================

# --- BUG FIX ---
# Ce bloc global génère une erreur "Unknown variable" car le fichier cloud_init.cfg attend une variable ${hostname}.
# Comme le hostname change pour chaque VM, on ne peut pas le définir ici globalement.
# SOLUTION: On utilise la fonction templatefile() directement dans chaque ressource "libvirt_cloudinit_disk" plus bas.

/*
data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    user    = var.ssh_username
    ssh_key = file(var.ssh_key_path)
    domain  = var.domain_name
  }
}
*/

# Creating ISO file to configure each machine with hostname, ssh pub key...

resource "libvirt_cloudinit_disk" "router_init" {
  name           = "router-init.iso"
  user_data      = data.template_file.router_user_data.rendered
  pool           = "default"
}

resource "libvirt_cloudinit_disk" "bastion_init" {
  name      = "bastion-init.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", { 
    hostname = "vm-bastion", 
    user = var.ssh_username, 
    # trimspace() enlève le saut de ligne tueur
    # pathexpand() corrige le bug du tilde "~"
    ssh_key  = trimspace(file(pathexpand(var.ssh_key_path))), 
    domain = var.domain_name })
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
  pool = "default"
}


# =================================================================
# 4. VIRTUAL MACHINES (COMPUTE)
# =================================================================

# --- A. Router (Debian 12)---

resource "libvirt_domain" "router" {
  name   = "vm-fw"
  memory = 1024
  vcpu   = 1
  
  cloudinit = libvirt_cloudinit_disk.router_init.id

  network_interface { network_name = "wan-network" }   # eth0
  network_interface { network_name = "vlan-mgmt" }     # eth1
  network_interface { network_name = "vlan-dmz" }      # eth2
  network_interface { network_name = "vlan-prod" }     # eth3
  network_interface { network_name = "vlan-backup" }   # eth4
  network_interface { network_name = "vlan-monitor" }  # eth5

  disk {
    volume_id = libvirt_volume.router_disk.id
  }

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
  # qemu_agent = true
  depends_on = [libvirt_domain.router]
  # Only connected to MGMT vlan network

  network_interface { 
    network_name = "vlan-mgmt" 
    wait_for_lease = false
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
  # qemu_agent = true
  depends_on = [libvirt_domain.router]

  network_interface { 
    network_name = "vlan-dmz"
    wait_for_lease = false
    }

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
  # qemu_agent = true
  depends_on = [libvirt_domain.router]

  network_interface { 
    network_name = "vlan-prod"
    wait_for_lease = false
    }

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
  # qemu_agent = true
  depends_on = [libvirt_domain.router]

  network_interface { 
    network_name = "vlan-backup"
    wait_for_lease = false
    }

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
  # qemu_agent = true
  depends_on = [libvirt_domain.router]

  network_interface { 
    network_name = "vlan-monitor"
    wait_for_lease = false
    }

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