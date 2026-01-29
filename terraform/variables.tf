# --- Hypervisor connection ---

variable "libvirt_uri" {
  description = "connection URI to KVM"
  default     = "qemu:///system"
}


# --- System Image ---
# By default : Cloud debian URL

variable "debian_image_path" {
  description = "Cloud Debian image source (URL)"
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}


# --- Default network ---

variable "network_cidr" { 
    description = "IP range for main network"
    type = string
    default = "172.16.0.0/16" 
    }

variable "domain_name"  { 
    description = "Local lab domain name"
    type = string
    default = "kvm-iac.lab" 
    }


# --- Ressources ---
# Default total RAM for this environment is 11GB

variable "pool_path"      { 
    description = "Absolute path to default disk image storage"
    type = string
    default = "/var/lib/libvirt/images" 
    }

variable "vm_bastion_ram" { default = 1024 }
variable "vm_fw_ram"      { default = 2048 }
variable "vm_prod_ram"    { default = 4096 } # 4GB recommended for K3s, prod app and database
variable "vm_proxy_ram"   { default = 1024 }
variable "vm_monitor_ram" { default = 2048 }
variable "vm_backup_ram"  { default = 1024 }
 

# --- SSH ---

variable "ssh_username" { default = "debian" }
variable "ssh_key_path" { default = "~/.ssh/id_ed25519.pub" }