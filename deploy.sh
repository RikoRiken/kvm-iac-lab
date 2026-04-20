#!/bin/bash

# ==============================================================================
# OUTIL DE GESTION DE L'INFRASTRUCTURE - KVM IAC LAB
# ==============================================================================

# Arrête le script immédiatement si une commande échoue
set -e 

# Définition des couleurs pour un affichage propre
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------------------------------------------------
# SYSTÈME DE LOGGING UNIVERSEL (tee)
# ---------------------------------------------------------
LOG_FILE="iac-operations.log"
exec > >(tee -i "$LOG_FILE") 2>&1

echo -e "${BLUE}\nFichier de journalisation : $LOG_FILE${NC}"

# ---------------------------------------------------------
# FONCTION : PREPARER ENVIRONNEMENT
# ---------------------------------------------------------

check_requirements() {
    echo -e "\n${BLUE}🛡️ VÉRIFICATION DES PRÉ-REQUIS (PRE-FLIGHT CHECK) 🛡️${NC}"
    local missing_deps=0

    # 1. Vérification des exécutables de base
    echo -e "\n${YELLOW}1. Recherche des binaires essentiels...${NC}"
    for cmd in terraform ansible-playbook virsh git bash; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ✅ $cmd est installé."
        else
            echo -e "  ❌ $cmd est MANQUANT."
            missing_deps=1
        fi
    done

    # 2. Vérification de KVM / Libvirt
    echo -e "\n${YELLOW}2. Vérification de la virtualisation KVM...${NC}"
    if groups | grep -q "\blibvirt\b"; then
        echo -e "  ✅ L'utilisateur '$(whoami)' appartient bien au groupe 'libvirt'."
    else
        echo -e "  ❌ L'utilisateur '$(whoami)' N'EST PAS dans le groupe 'libvirt'."
        echo -e "     -> Solution : exécutez 'sudo usermod -aG libvirt $(whoami)' puis reconnectez-vous."
        missing_deps=1
    fi

    # 3. Vérification des Collections Ansible (Optionnel mais sécurisant)
    # Si tu utilises ansible.posix (pour sysctl) ou community.general
    echo -e "\n${YELLOW}3. Vérification des collections Ansible...${NC}"
    if ansible-galaxy collection list | grep -q "ansible.posix"; then
         echo -e "  ✅ Collection ansible.posix trouvée."
    else
         echo -e "  ⚠️ Collection ansible.posix manquante. Installation en cours..."
         ansible-galaxy collection install ansible.posix --quiet || echo -e "  ❌ Échec de l'installation de ansible.posix."
    fi

    # Bilan du Pre-flight Check
    if [ "$missing_deps" -ne 0 ]; then
        echo -e "\n${RED}🛑 ÉCHEC DU PRE-FLIGHT CHECK 🛑${NC}"
        echo -e "L'environnement hôte ne remplit pas tous les critères pour lancer le déploiement."
        echo -e "Veuillez corriger les erreurs ci-dessus avant de relancer le script."
        exit 1
    else
        echo -e "\n${GREEN}PRE-FLIGHT CHECK RÉUSSI. L'environnement est prêt.${NC}"
    fi
}

# ---------------------------------------------------------
# FONCTION : DÉPLOIEMENT (--apply)
# ---------------------------------------------------------
deploy_infra() {
    echo -e "\n${BLUE}🚀 DÉMARRAGE DU DÉPLOIEMENT (--apply) 🚀${NC}"
    
    check_requirements

    echo -e "\n${GREEN}[1/5] Vérification des prérequis système...${NC}"
    for cmd in terraform ansible-playbook virsh; do
      if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ Erreur : La commande '$cmd' est introuvable.${NC}"
        exit 1
      fi
    done
    echo "✅ Tous les outils sont installés."

    echo -e "\n${GREEN}[2/5] Configuration des accès SSH...${NC}"
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
        echo "✅ Clé SSH générée."
    fi
    echo "🧹 Nettoyage du cache SSH local (known_hosts)..."
    rm -f ~/.ssh/known_hosts ~/.ssh/known_hosts.old

    echo -e "\n${GREEN}[3/5] Provisioning matériel (Terraform)...${NC}"
    cd terraform
    terraform init -upgrade
    terraform apply -auto-approve
    cd ..

    echo -e "\n${GREEN}[4/5] Attente du démarrage des systèmes...${NC}"
    echo -e "${YELLOW}Pause de 120 secondes...${NC}"
    sleep 120

    echo -e "\n${GREEN}[5/5] Configuration logicielle (Ansible)...${NC}"
    cd ansible
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible-playbook -i inventory.ini site.yml
    cd ..

    echo -e "\n${GREEN}✅ DÉPLOIEMENT TERMINÉ AVEC SUCCÈS ! ${NC}"

    # Récupération dynamique de l'IP publique du pare-feu depuis Terraform
    cd terraform
    FW_IP=$(terraform output -raw router_wan_ip 2>/dev/null || echo "192.168.150.11")
    cd ..

    echo -e "\n${YELLOW}RÉCAPITULATIF DES ACCÈS :${NC}"
    echo -e "------------------------------------------------------------------"
    echo -e "${GREEN}Pare-feu (Routeur)${NC}      : $FW_IP"
    echo -e "${GREEN}Bastion (Point d'entrée)${NC}: ssh debian@$FW_IP -p 2222"
    echo -e "${GREEN}Application Web (Prod)${NC}  : http://$FW_IP  (Routé par le proxy)"
    echo -e "${GREEN}Grafana (Monitoring)${NC}    : http://localhost:3000"
    echo -e "------------------------------------------------------------------"
    echo -e "${YELLOW}Astuce :${NC} Pour accéder à Grafana, ouvrez un tunnel SSH depuis votre PC :"
    echo -e "   ${BLUE}ssh -L 3000:172.16.50.10:3000 debian@$FW_IP -p 2222${NC}\n"
}

# ---------------------------------------------------------
# FONCTION : DESTRUCTION (--destroy)
# ---------------------------------------------------------
destroy_infra() {
    echo -e "\n${RED}DÉMARRAGE DE LA DESTRUCTION (--destroy)${NC}"
    
    echo -e "\n${YELLOW}[1/2] Destruction de l'infrastructure matérielle...${NC}"
    cd terraform
    terraform destroy -auto-approve
    cd ..

    echo -e "\n${YELLOW}[2/2] Nettoyage des caches locaux...${NC}"
    rm -f ~/.ssh/known_hosts ~/.ssh/known_hosts.old
    rm -rf ~/.ansible/cp/* 2>/dev/null || true

    echo -e "\n${GREEN}✅ INFRASTRUCTURE DÉTRUITE PROPREMENT !${NC}"
}

# ---------------------------------------------------------
# MENU DE SÉLECTION (Le Parseur d'Arguments)
# ---------------------------------------------------------

# Si aucun argument n'est passé, on affiche l'aide
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: ./deploy.sh [OPTION]${NC}"
    echo "Options:"
    echo "  --apply    Déploie l'infrastructure complète (Terraform + Ansible)"
    echo "  --destroy  Détruit l'infrastructure et nettoie l'environnement local"
    exit 1
fi

# Switch selon l'argument
case "$1" in
    --apply)
        deploy_infra
        ;;
    --destroy)
        destroy_infra
        ;;
    *)
        echo -e "${RED}❌ Option invalide : $1${NC}"
        echo -e "Utilisez --apply ou --destroy."
        exit 1
        ;;
esac