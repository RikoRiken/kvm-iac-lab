# KVM IaC Lab

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](#)
[![QEMU](https://img.shields.io/badge/-QEMU-FF6600?style=flat&logo=qemu&logoColor=white)](#)
[![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=fff)](#)
[![Ansible](https://img.shields.io/badge/-Ansible-EE0000?style=flat&logo=ansible&logoColor=white)](#)
[![Kubernetes](https://img.shields.io/badge/-Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)](#)
[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=fff)](#)
[![MariaDB](https://img.shields.io/badge/MariaDB-003545?logo=mariadb&logoColor=white)](#)
![Nginx](https://img.shields.io/badge/nginx-%23009639.svg?logo=nginx&logoColor=white)
[![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)](#)
[![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)](#)


<br>

## 📖 About The Project

This project provides a **fully automated, secure-by-design infrastructure stack** meant for local development, security simulation, and self-hosting. It leverages **Infrastructure as Code (IaC)** principles to deploy a segmented network behind an enterprise-grade firewall on a Linux KVM hypervisor.

Unlike simple Docker-compose setups, this project simulates a **Real-World Architecture** using nested virtualization (The "Russian Doll" approach):
1.  **Hardware Level:** Your Host Machine (Linux Based).
2.  **Infrastructure Level:** KVM VMs managed by Terraform.
3.  **Application Level:** Docker Containers & Kubernetes Pods managed by Ansible.

It is designed to be **environment-agnostic**: network plans (CIDR), resources (RAM/CPU), and domain names are fully customizable via variables, making it compatible with any homelab setup.

> 🇫🇷 **Français :** La documentation technique détaillée, l'IPAM et la Matrice de Flux sont disponibles en français dans le dossier [docs/fr/](./docs/fr/).

<br>

## 🏗️ Architecture

![Architecture Schema](./docs/architecture_v4.png)

> Check the [IP Address Management](./docs/ipam.md) for further information.

The stack is strictly segmented into VLANs to enforce a **Zero-Trust** security model:

| Zone | VLAN | Role | Services |
| :--- | :---: | :--- | :--- |
| **WAN** | - | Untrusted | Internet Simulation / NAT |
| **MGMT** | 10 | Restricted | Bastion SSH, Ansible Controller |
| **DMZ** | 20 | Front-End | Nginx Reverse Proxy, CrowdSec Agent |
| **PROD** | 30 | Backend | **K3s Cluster** (Website, MariaDB) |
| **BACKUP**| 40 | Isolated | BorgBackup Repository |
| **MONIT** | 50 | Observability | **PLG Stack** (Prometheus, Loki, Grafana) |

> Check the [Firewall Policy](./docs/firewall_policy.md) for further information.

<br>

## 🚀 Getting Started

### 0. Prerequisites

* **OS:** A Linux Host (Debian/Fedora/Ubuntu) with hardware virtualization enabled (VT-x/AMD-v).
* **Hypervisor:** `libvirt` and KVM installed and the `libvirtd` service running.
* **Permissions:** Your current user **must** belong to the `libvirt` group (`sudo usermod -aG libvirt $USER`).
* **Tools:** `terraform`, `ansible` (with `ansible-galaxy`), and `git` installed.

<br>

### 1. Installation

Clone the repository to your local machine:
```bash
git clone https://github.com/RikoRiken/kvm-iac-lab.git
cd kvm-iac-lab
```

<br>

### 2. Configuration

* **No local SSH configuration is required.** The Ansible inventory natively handles the complex routing and `ProxyJump` through the firewall to reach internal networks.
* The deployment script includes a **Pre-flight Check** that will scan your host environment, verify dependencies, and ensure your system is ready.

<br>

### 3. Deployment

The infrastructure lifecycle is fully automated via a single entrypoint script `deploy.sh`. All operations are logged automatically in `iac-operations.log`.

**To build the infrastructure:**
```bash
./deploy.sh --apply
```
*Note: The deployment takes approximately **5-8 minutes** depending on your internet connection (Debian Cloud Image download) and CPU speed. A post-deployment summary will output all your access credentials and URLs.*at the end of the process

**To destroy the infrastructure:**
```bash
./deploy.sh --destroy
```
*Note: This command will safely destroy all KVM resources, networks, and clean up local SSH/Ansible caches, leaving your host exactly as it was.*

<br>

## 🛡️ Security Strategy

- Debian router with `iptables-nft` Firewall: Acts as the central gateway. All Inter-VLAN traffic is inspected, and iptables rules are translated by kernel to nftables logic.

- Deny All by Default: No traffic is allowed unless explicitly whitelisted.

- Bastion Host: No direct SSH access to internal VMs. All administration traffic must pass through the Bastion (VLAN 10).

- CrowdSec IPS: Collaborative security agents deployed on the Bastion (SSH protection) and Proxy (HTTP protection).

- Network Isolation: The DMZ cannot access the Backup or Management networks.

<br>

## 🛠️ Built With

- [Terraform](https://www.terraform.io/) - Infrastructure Provisioning (Libvirt Provider).

- [Ansible](https://www.ansible.com/) - Configuration Management & App Deployment.

- [Docker](https://www.docker.com/) - Container Runtime for Monitoring & Proxy.

- [K3s](https://k3s.io/) - Lightweight Kubernetes distribution for Production apps.

- [Linux: Debian](https://debian.org/) - Linux distribution for router/fw and prod machines.

<br>

## 📝 License

Distributed under the MIT License. See `LICENSE` for more information.

