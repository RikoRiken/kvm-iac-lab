# 🛡️ Network Flow Matrix (Firewall Policy)

This document defines the filtering policy applied on the **OPNsense** central firewall. It translates the project's segmentation requirements into concrete technical rules. The adopted approach is **"Deny All by Default"** (traffic not explicitly allowed is forbidden).

## 1. Objects & Aliases (Definitions)

To simplify OPNsense configuration and readability, the following aliases are used:

| Alias | Value / CIDR | Description |
| :--- | :--- | :--- |
| `VLAN_MGMT` | `172.16.10.0/24` | Management Network **(VLAN 10)** |
| `VLAN_DMZ` | `172.16.20.0/24` | Frontend Network (Exposed) **(VLAN 20)** |
| `VLAN_PROD` | `172.16.30.0/24` | Production/App Network **(VLAN 30)** |
| `VLAN_BACKUP` | `172.16.40.0/24` | Backup Network **(VLAN 40)** |
| `VLAN_MONITOR` | `172.16.50.0/24` | Monitoring Network **(VLAN 50)** |
| `ALL_VLAN` | `172.16.0.0/16` | Supernet containing all internal VLANs |
| `HOST_BASTION`| `172.16.10.10` | Bastion SSH VM |
| `HOST_PROXY` | `172.16.20.10` | Reverse Proxy VM |
| `HOST_PROD` | `172.16.30.10` | Application VM (K3s) |
| `HOST_BACKUP` | `172.16.40.10` | Borg Backup VM |
| `HOST_MONITOR`| `172.16.50.10` | Monitoring VM (PLG Stack) |
| `GW_FW` | `172.16.x.254` | Firewall LAN Interfaces |

> 💡 **Automation Note:** These aliases are automatically provisioned in OPNsense via Ansible. If the IP plan is modified in the project variables, these aliases are updated dynamically.

---

## 2. Filtering Rules

**Default Policy:** ⛔ **DROP/REJECT** all traffic not explicitly allowed.

### 2.1 Administration Flows (MGMT Zone)
*Objective: Enable secure infrastructure management.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **ADM-01** | *INTERNET* | `HOST_BASTION` | 2222 (TCP) | ✅ ALLOW | **Port Forward**: `WAN:2222` -> `HOST_BASTION:22`.<br>⚠️ Security: Key-based authentication only. Passwords disabled. Bruteforce protection via CrowdSec. |
| **ADM-02** | `VLAN_MGMT` | `GW_FW` | 443 (TCP) | ✅ ALLOW | OPNsense Web GUI access from Admin Network. |
| **ADM-03** | `VLAN_MGMT` | `GW_FW` | 22 (TCP) | ✅ ALLOW | Emergency SSH access to Firewall. |
| **ADM-04** | `HOST_BASTION` | `ALL_VLAN` | 22 (TCP) | ✅ ALLOW | **SSH Jump**: The Bastion must be able to manage all internal VMs. |

### 2.2 Business Flows (BookStack Application)
*Objective: Ensure application availability for end-users.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **APP-01** | *INTERNET* | `HOST_PROXY` | 80, 443 (TCP) | ✅ ALLOW | Public HTTP/HTTPS access to Reverse Proxy (DMZ). |
| **APP-02** | `HOST_PROXY` | `HOST_PROD` | 30080 (TCP) | ✅ ALLOW | Proxy forwards traffic to K3s NodePort. |
| **APP-03** | `HOST_PROD` | *INTERNET* | 443 (TCP) | ✅ ALLOW | Docker image download & Updates. Whitelist proxy added for hardening. |

### 2.3 Monitoring Flows
*Objective: Metrics and logs collection.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **MON-01** | `HOST_MONITOR` | `ALL_VLAN` | 9100 (TCP) | ✅ ALLOW | **Prometheus Scrape**: Server fetches info from Node Exporters. |
| **MON-02** | `HOST_MONITOR` | `HOST_PROD` | 6443 (TCP) | ✅ ALLOW | Kubernetes API Monitoring. |
| **MON-03** | `ALL_VLAN` | `HOST_MONITOR` | 3100 (TCP) | ✅ ALLOW | **Loki Push**: VMs send their logs to Loki (Promtail). |

### 2.4 Backup Flows
*Objective: Data security.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **BCK-01** | `ALL_VLAN` | `HOST_BACKUP` | 22 (TCP) | ✅ ALLOW | **Borg Push**: VMs connect to the backup repo to upload archives. |

### 2.5 Infrastructure Services (DNS, NTP, Updates)
*Objective: System maintenance and operations.*

| ID | Source | Destination | Port / Proto | Action | Description / Justification |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **INF-01** | `ALL_VLAN` | `GW_FW` | 53 (UDP/TCP)| ✅ ALLOW | DNS Resolution via OPNsense Resolver (Unbound). |
| **INF-02** | `ALL_VLAN` | `GW_FW` | 123 (UDP) | ✅ ALLOW | NTP Time Synchronization. |
| **INF-03** | `ALL_VLAN` | *INTERNET* | 80, 443 (TCP)| ✅ ALLOW | System & CrowdSec updates. Whitelist proxy (Squid) added for hardening. |
| **INF-04** | `ALL_VLAN` | `GW_FW` | ICMP (Ping) | ✅ ALLOW | Connectivity check to Gateway/Firewall. |
| **INF-05** | `VLAN_MGMT` | `ALL_VLAN` | ICMP (Ping) | ✅ ALLOW | Administration can test connectivity to all machines. |

---

## 3. Security Analysis (Notes)

1.  **DMZ Isolation:** The DMZ (`VLAN 20`) can **never** initiate a connection towards Management or Backup networks. If the Proxy is compromised, the attacker is contained.
2.  **Backup Flow Direction:** Uses "Push Mode". The Backup server has no outbound access (except updates), limiting ransomware propagation risks on the backup server itself.
3.  **Stateful Inspection:** All rules above apply to connection initiation. The firewall implicitly allows return packets (ACK) for established connections.