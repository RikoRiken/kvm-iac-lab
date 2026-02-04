# 🏗️ Infrastructure as Code (KVM + Terraform)

This directory contains the Terraform code used to deploy a fully segmented and secure laboratory environment on a Linux KVM hypervisor.

## Objective
Deploy the following infrastructure with a single command (`terraform apply`), ensuring "Zero Touch" automation:
- **1 Router/Firewall** (OPNsense) automatically configured.
- **5 Isolated Networks** (VLANs) simulating an enterprise architecture.
- **Application Servers** (Bastion, Production, Monitoring, etc.) running on Debian 12.

---

## Project Structure

| File | Description |
| :--- | :--- |
| `main.tf` | Core definition of VMs (Compute) and Networks. |
| `opnsense_setup.tf` | **Advanced Logic**: Handles OPNsense image download and configuration injection (XML/Fat32) for zero-touch provisioning. |
| `variables.tf` | Parameter definitions (RAM, IPs, Domain Name) for portability. |
| `outputs.tf` | Displays critical IPs (Bastion, Firewall WAN) after deployment. |
| `cloud_init.cfg` | Post-boot configuration for Debian VMs (Users, SSH Keys, Packages). |
| `terraform.tfvars.example` | (Delete `.example` to use) Local variable overrides (e.g., local image path, RAM sizing). |

---

## Technical Choices & Providers

### 1. `dmacvicar/libvirt` Provider
We use this community provider (the de facto standard for KVM) instead of the official HashiCorp provider (which targets Public Cloud).
- **Connection URI:** `qemu:///system` (Root Mode).
- **Why?** Required for creating virtual switches and handling low-level network operations.

### 2. Network Management (`mode = "none"`)
All internal networks (Mgmt, DMZ, Prod...) are defined with `mode = "none"`.
- **Explanation:** KVM creates the virtual "cables" and switches (Layer 2) but provides **no services** (no DHCP, no DNS, no Routing).
- **Advantage:** The **OPNsense VM** handles all traffic. This guarantees strict isolation (Air Gap) and forces traffic to pass through the firewall rules.

### 3. Storage (QCOW2 & Copy-on-Write)
- **Base Image:** A single Debian Cloud image is downloaded once.
- **VM Volumes:** Each VM uses a disk that is a "delta" (overlay) of the base image.
- **Benefit:** Instant deployment and drastic disk space saving.

---

## OPNsense Automation (`opnsense_setup.tf`)

Since OPNsense does not support Cloud-Init natively, we implemented a custom injection method to avoid manual setup.

1.  **Auto-Download:** Terraform uses `wget` and `qemu-img` via a `null_resource` to fetch and convert the official Nano image.
2.  **Configuration Injection:**
    - Terraform generates an XML file (`config.xml`) containing interface mappings and SSH activation.
    - This file is converted into a small FAT32 virtual disk using `virt-make-fs` (part of `libguestfs`).
3.  **Boot Process:** The disk is attached to the VM. OPNsense detects the configuration drive at boot and triggers its "Importer" routine.

---

## Usage

### Prerequisites (Fedora/Linux)
Ensure you have KVM and the image manipulation tools installed:
```bash
sudo dnf install terraform libvirt-devel qemu-kvm guestfs-tools
sudo usermod -aG libvirt $(whoami)
```

### Deployment Steps
1.  **Initialize the project:**
    ```bash
    terraform init
    ```
2.  **Configuration (Optional):**
    Create a `terraform.tfvars` file to override defaults (e.g., reduce RAM for laptops):
    ```hcl
    vm_prod_ram = 2048
    debian_image_path = "/home/user/images/debian.qcow2"
    ```
3.  **Launch:**
    ```bash
    terraform apply
    ```

### Access
Once deployed, wait 2-3 minutes for OPNsense to fully boot, then run `terraform refresh`.
- **Bastion:** `ssh debian@<BASTION_IP>`
- **OPNsense (Web UI):** `https://<WAN_IP>` (Credentials: `root` / `opnsense`)

---

## ⚠️ Troubleshooting

**Error: `Network is already in use by interface virbr0`**
- *Cause:* The default KVM network conflicts with our WAN network definition.
- *Fix:*
  ```bash
  sudo virsh net-destroy default
  sudo virsh net-undefine default
  ```

**Error: `Invalid index` in outputs**
- *Cause:* Terraform is trying to display IPs before the VMs have received a DHCP lease.
- *Fix:* Wait a few minutes and run `terraform refresh`. The outputs use a `try()` function to prevent crashing.