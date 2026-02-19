# Print SSH Bastion IP (Infrastructure entry point)


# --- BUG FIX ---
# PROBLEME : L'accès direct à l'index [0] (ex: .addresses[0]) provoque une erreur
# fatale "Invalid Index" si la VM n'a pas encore d'IP ou si le déploiement a échoué.
# Cela bloque totalement la commande "terraform apply ou terraform destroy".
#
# SOLUTION : Utilisation fonction try().
# Si l'IP est introuvable, Terraform n'affiche pas d'erreur mais le message de secours.


output "bastion_ip" {
  description = "Bastion Public IP (Management)"
  value       = try(libvirt_domain.bastion.network_interface[0].addresses[0], "Wait for OPNsense DHCP...")
}

output "router_wan_ip" {
  description = "Router WAN IP (Web Interface)"
  value       = try(libvirt_domain.router.network_interface[0].addresses[0], "Check via 'terraform refresh' later")
}

output "setup_instruction" {
  value = "Wait 2-3 minutes for the router to boot completely. Then run 'terraform refresh' to reveal IPs."
}
