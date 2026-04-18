#!/bin/bash

# ==============================================================================
# DÉPLOIEMENT AUTOMATISÉ - KVM IAC LAB
# ==============================================================================

# Arrête le script immédiatement si une commande échoue
set -e 

# Définition des couleurs pour un affichage propre
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}🚀 DÉMARRAGE DU DÉPLOIEMENT DE L'INFRASTRUCTURE 🚀${NC}"
echo -e "${BLUE}======================================================${NC}"

# ---------------------------------------------------------
# 1. VÉRIFICATION DES PRÉREQUIS
# ---------------------------------------------------------
echo -e "\n${GREEN}[1/5] Vérification des prérequis système...${NC}"
for cmd in terraform ansible-playbook virsh; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}❌ Erreur : La commande '$cmd' est introuvable.${NC}"
    echo -e "${YELLOW}Veuillez installer $cmd avant de lancer ce script.${NC}"
    exit 1
  fi
done
echo "✅ Tous les outils nécessaires sont installés."

# ---------------------------------------------------------
# 2. GESTION DES CLÉS SSH
# ---------------------------------------------------------
echo -e "\n${GREEN}[2/5] Configuration des accès SSH...${NC}"
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "⚠️ Aucune clé SSH Ed25519 trouvée. Génération en cours..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
    echo "✅ Clé SSH générée."
else
    echo "✅ Clé SSH locale détectée."
fi

echo "🧹 Nettoyage du cache SSH local (known_hosts)..."
rm -f ~/.ssh/known_hosts ~/.ssh/known_hosts.old

# ---------------------------------------------------------
# 3. CRÉATION DU MATÉRIEL (TERRAFORM)
# ---------------------------------------------------------
echo -e "\n${GREEN}[3/5] Provisioning de l'infrastructure (Terraform)...${NC}"
cd terraform
terraform init -upgrade
terraform apply -auto-approve
cd ..

# ---------------------------------------------------------
# 4. TEMPS DE CHAUFFE (BOOT DES VMS)
# ---------------------------------------------------------
echo -e "\n${GREEN}[4/5] Attente du démarrage des systèmes d'exploitation...${NC}"
echo -e "${YELLOW}⏳ Pause de 60 secondes pour laisser le service SSH démarrer sur les VMs...${NC}"
sleep 60

# ---------------------------------------------------------
# 5. CONFIGURATION LOGICIELLE (ANSIBLE)
# ---------------------------------------------------------
echo -e "\n${GREEN}[5/5] Configuration des serveurs et services (Ansible)...${NC}"
cd ansible

# On force Ansible à ne pas bloquer sur la vérification des clés SSH (yes/no)
export ANSIBLE_HOST_KEY_CHECKING=False

ansible-playbook -i inventory.ini site.yml
cd ..

# ---------------------------------------------------------
# FIN
# ---------------------------------------------------------
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}🎉 DÉPLOIEMENT TERMINÉ AVEC SUCCÈS ! 🎉${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "🔗 Votre proxy applicatif est accessible sur : http://172.16.20.10"
echo -e "📊 Votre interface Grafana est accessible via tunnel SSH sur la vm-monitor"