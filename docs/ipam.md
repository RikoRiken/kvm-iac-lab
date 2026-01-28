# 🌍 Addressing and Naming Policy (IPAM)

## 1. Standards & Conventions

### 1.1 Network Identity
* **Private Network Range:** `172.16.0.0/16` (RFC1918)
* **Technology:** Isolated virtual networks (KVM/Libvirt) routed by OPNsense.

### 1.2 Naming Convention
Format: `vm-<role>`
* **Examples:** `vm-bastion`, `vm-prod`, `vm-backup`.

### 1.3 IP Allocation Convention
For each subnet (`/24`), the distribution is standardized:

| Range | Usage | Comment |
| :--- | :--- | :--- |
| `.1` - `.9` | **Infrastructure** | Reserved for Virtual Switches & Network Equipment |
| `.10` - `.99` | **Servers (Static IP)** | Infrastructure and Application VMs |
| `.100` - `.199` | **DHCP Pool** | Temporary clients (if applicable) |
| `.254` | **Gateway** | Firewall Interface (OPNsense) |

---

## 2. Segmentation & Security Zones

The architecture relies on strict segmentation using VLANs (Virtual Switches).

| Zone | VLAN ID | CIDR | Trust Level | Description |
| :--- | :---: | :--- | :---: | :--- |
| **WAN** | - | `192.168.122.0/24` | 🔴 Untrusted | Transport network (Libvirt NAT). Simulates Internet. |
| **DMZ** | **20** | `172.16.20.0/24` | 🟠 Semi-Trusted | Exposed Zone (Web Front-end). Isolated from LAN. |
| **PROD** | **30** | `172.16.30.0/24` | 🟢 Trusted | Critical Application Zone (App + Data). |
| **MGMT** | **10** | `172.16.10.0/24` | 🔒 Restricted | "Entry Airlock". Only zone allowed to initiate SSH. |
| **BACKUP**| **40** | `172.16.40.0/24` | 🛡️ Sanctuarized | Isolated zone. Inbound flows limited to strict minimum. |
| **MONIT** | **50** | `172.16.50.0/24` | 🔵 Read-Only | Observation zone. Collects metrics and logs. |

---

## 3. Detailed Resource Inventory

### 3.1 Network Core (Gateway)

| Hostname | IP (Internal) | OS | Role |
| :--- | :--- | :--- | :--- |
| **vm-fw** | `172.16.10.254`<br>`172.16.20.254`<br>`172.16.30.254`<br>`172.16.40.254`<br>`172.16.50.254` | **OPNsense** | Firewall, Inter-VLAN Routing, DHCP, DNS Resolver. |

### 3.2 MANAGEMENT Zone (VLAN 10)

| Hostname | IP | OS | Services & Security |
| :--- | :--- | :--- | :--- |
| **vm-bastion** | `172.16.10.10` | Debian 12 | **SSH Gateway**, Ansible Controller.<br>🛡️ *Security:* **CrowdSec Agent** (SSH Protection). |

### 3.3 DMZ Zone (VLAN 20)

| Hostname | IP | OS | Services & Security |
| :--- | :--- | :--- | :--- |
| **vm-proxy** | `172.16.20.10` | Debian 12 | **Nginx** (Reverse Proxy).<br>🛡️ *Security:* **CrowdSec Agent** (HTTP/L7 Protection). |

### 3.4 PRODUCTION Zone (VLAN 30)

| Hostname | IP | OS | Services & Security |
| :--- | :--- | :--- | :--- |
| **vm-prod** | `172.16.30.10` | Debian 12 | **K3s Cluster** (Single Node).<br>📦 *Apps:* BookStack, MariaDB. |

### 3.5 BACKUP Zone (VLAN 40)

| Hostname | IP | OS | Services & Security |
| :--- | :--- | :--- | :--- |
| **vm-backup** | `172.16.40.10` | Debian 12 | **BorgBackup Repository**.<br>Encrypted and deduplicated storage. |

### 3.6 MONITORING Zone (VLAN 50)

| Hostname | IP | OS | Services & Security |
| :--- | :--- | :--- | :--- |
| **vm-monitor** | `172.16.50.10` | Debian 12 | **PLG Stack** :<br>- Prometheus (Metrics)<br>- Loki (Logs)<br>- Grafana (Dashboards) |

---

## 4. Flow Matrix & Architecture

### 4.1 Architecture Diagram
*(See the detailed diagram provided in the architecture folder)*

> 💡 *Note: Insert architecture image here*

### 4.2 Administration Flows (Secure Path)
Access to internal servers is forbidden from the User LAN or Internet, except via the following process:
1.  **Admin** (Fedora Host) -> SSH -> **Firewall** (Port Forwarding).
2.  **Firewall** -> **vm-bastion** (SSH Key Verification + CrowdSec).
3.  **vm-bastion** -> SSH Jump -> **Target** (Prod, Backup, etc.).

### 4.3 Public Application Flows
1.  **Internet** -> HTTPS (443) -> **Firewall**.
2.  **Firewall** -> **vm-proxy** (SSL Termination).
3.  **vm-proxy** -> HTTP (80) -> **vm-prod** (K3s NodePort Service).