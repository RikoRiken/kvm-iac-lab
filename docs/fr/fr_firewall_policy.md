# 🛡️ Matrice de Flux Réseau (Firewall Policy)

Ce document définit la politique de filtrage appliquée sur le pare-feu central **Debian**. Il traduit les exigences de segmentation du projet en règles techniques concrètes. L'approche retenue est le **"Deny All by Default"** (tout ce qui n'est pas explicitement autorisé est interdit).

## 1. Objets & Alias (Définitions)

Pour simplifier la lecture et la configuration du routeur/pare-feu, les alias suivants sont utilisés :

| Alias | Valeur / IP | Description |
| :--- | :--- | :--- |
| `VLAN_MGMT` | `172.16.10.0/24` | Réseau d'administration **(VLAN 10)** |
| `VLAN_DMZ` | `172.16.20.0/24` | Réseau frontal (exposé) **(VLAN 20)** |
| `VLAN_PROD` | `172.16.30.0/24` | Réseau prod/applicatif **(VLAN 30)** |
| `VLAN_BACKUP` | `172.16.40.0/24` | Réseau de sauvegarde **(VLAN 40)** |
| `VLAN_MONITOR` | `172.16.50.0/24` | Réseau de supervision **(VLAN 50)** |
| `ALL_VLAN` | `172.16.0.0/16` | Super-réseau contenant tous les VLANs internes |
| `HOST_BASTION`| `172.16.10.10` | VM Bastion SSH |
| `HOST_PROXY` | `172.16.20.10` | VM Reverse Proxy |
| `HOST_PROD` | `172.16.30.10` | VM Application (K3s) |
| `HOST_BACKUP` | `172.16.40.10` | VM Borg Backup |
| `HOST_MONITOR`| `172.16.50.10` | VM Monitoring (Stack PLG) |
| `GW_FW` | `172.16.x.254` | Interfaces LAN du Firewall |

---

## 2. Règles de Filtrage (Filter Rules)

**Politique par défaut :** ⛔ **BLOQUER (DROP/REJECT)** tout trafic non explicitement autorisé.

### 2.1 Flux d'Administration (Zone MGMT)
*Objectif : Permettre à l'administrateur de gérer l'infrastructure de manière sécurisée.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **ADM-01** | *INTERNET* | `HOST_BASTION` | 2222 (TCP) | ✅ ALLOW | Port Forward : `WAN:2222` -> `HOST_BASTION:22`.<br>⚠️ Sécurité : Authentification par Clé uniquement. Mots de passe désactivés. Protection bruteforce par CrowdSec. |
| **ADM-02** | `VLAN_MGMT` | `GW_FW` | 22 (TCP) | ✅ ALLOW | Accès SSH de secours au Firewall. |
| **ADM-03** | `HOST_BASTION` | `ALL_VLAN` | 22 (TCP) | ✅ ALLOW | **Rebond SSH** : Le Bastion doit pouvoir administrer toutes les VMs internes. |

### 2.2 Flux Métier (Application BookStack)
*Objectif : Faire fonctionner l'application pour les utilisateurs finaux.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **APP-01** | *INTERNET* | `HOST_PROXY` | 80, 443 (TCP) | ✅ ALLOW | Accès public HTTP/HTTPS vers le Reverse Proxy (DMZ). |
| **APP-02** | `HOST_PROXY` | `HOST_PROD` | 30080 (TCP) | ✅ ALLOW | Le Proxy transfère le trafic vers le NodePort du cluster K3s. |
| **APP-03** | `HOST_PROD` | *INTERNET* | 443 (TCP) | ✅ ALLOW | Téléchargement des images Docker et MAJs. Ajout d'un proxy whitelist pour hardening.  |

### 2.3 Flux de Supervision (Monitoring)
*Objectif : Collecte des métriques et logs.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **MON-01** | `HOST_MONITOR` | `ALL_VLAN` | 9100 (TCP) | ✅ ALLOW | **Prometheus Scrape** : Le serveur va chercher les infos sur les Node Exporters. |
| **MON-02** | `HOST_MONITOR` | `HOST_PROD` | 6443 (TCP) | ✅ ALLOW | Monitoring de l'API Kubernetes. |
| **MON-03** | `ALL_VLAN` | `HOST_MONITOR` | 3100 (TCP) | ✅ ALLOW | **Loki Push** : Les VMs envoient leurs logs vers Loki (Promtail). |

### 2.4 Flux de Sauvegarde (Backup)
*Objectif : Sécurisation des données.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **BCK-01** | `ALL_VLAN` | `HOST_BACKUP` | 22 (TCP) | ✅ ALLOW | **Borg Push** : Les VMs se connectent au repo de backup pour déposer leurs archives. |

### 2.5 Services d'Infrastructure (DNS, NTP, Updates)
*Objectif : Bon fonctionnement du système.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **INF-01** | `ALL_VLAN` | `GW_FW` | 53 (UDP/TCP)| ✅ ALLOW | Résolution DNS via le Resolver (Unbound). |
| **INF-02** | `ALL_VLAN` | `GW_FW` | 123 (UDP) | ✅ ALLOW | Synchronisation horaire NTP. |
| **INF-03** | `ALL_VLAN` | *INTERNET* | 80, 443 (TCP)| ✅ ALLOW | Mises à jour système et CrowdSec. Ajout d'un proxy whitelist (squid) pour hardening. |
| **INF-04** | `ALL_VLAN` | `GW_FW` | ICMP (Ping) | ✅ ALLOW | Test de connectivité à la Gateway/Firewall. |
| **INF-05** | `VLAN_MGMT` | `ALL_VLAN` | ICMP (Ping) | ✅ ALLOW | L'administration peut tester toutes les machines |

---

## 3. Analyse de Sécurité (Notes pour soutenance)

1.  **Isolation DMZ :** La DMZ (`VLAN 20`) ne peut **jamais** initier de connexion vers le réseau de Management ou de Backup. Si le Proxy est compromis, l'attaquant est bloqué.
2.  **Sens du flux Backup :** C'est le client qui pousse vers le serveur de backup (`Push Mode`). Le serveur de Backup n'a accès à **rien** en sortie (sauf updates), limitant la propagation en cas de ransomware sur le serveur de backup lui-même.
3.  **Stateful Inspection :** Toutes les règles ci-dessus concernent l'initiation de connexion. Le firewall autorise implicitement les paquets de retour (ACK) pour les connexions établies.
