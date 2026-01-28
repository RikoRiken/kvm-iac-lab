# Print SSH Bastion IP (Infrastructure entry point)

output "bastion_ip" {
  value       = libvirt_domain.bastion.network_interface[0].addresses[0]
  description = "(WAN) Bastion public IP for SSH connections"
}

# Print WAN Firewall IP (for info)

output "firewall_wan_ip" {
   value = libvirt_domain.opnsense.network_interface[0].addresses[0]
}