# Dune: Awakening — Ubuntu 26.04 amd64v3 Self-Hosted Server

An Ansible-based deployment workflow for running the Linux dedicated server for **Dune: Awakening** on an Ubuntu VM hosted by Proxmox VE.

This project aims to use more modern cpu architectures, updated to use Canonical's **Ubuntu Server 26.04 LTS amd64v3 cloud image** instead of legacy Ubuntu. It creates a Proxmox VM, bootstraps Ubuntu, installs SteamCMD and the Linux server payload, configures k3s and the Funcom components, and initializes a self-hosted world.

> **Performance note:** amd64v3 is an x86-64 CPU feature level, not a performance guarantee. The host CPU must support the required instructions. The guest VM is configured with Proxmox CPU type `host`, and the selected cloud image is the amd64v3 build. Real-world performance depends on the server workload, CPU, storage and network.

## Choose your template

When you run the wrapper, it asks whether you already have an Ubuntu 26.04 LTS amd64v3 Proxmox template.

- **Reuse existing template:** answer `y` (default), then enter its VMID. The example default is `8010`. The VMID must refer to a usable Proxmox template built from Ubuntu 26.04 amd64v3 with cloud-init configured.
- **Create a template:** answer `n`. The playbook downloads the official Canonical amd64v3 cloud image, verifies it against Canonical's published `SHA256SUMS`, imports it into Proxmox, configures cloud-init and EFI, and converts the VM into a template.

The workflow then clones that template into a new Dune VM. It does not delete or overwrite an existing template or VM. Choose unused VMIDs.

## What it automates

1. Optionally creates an Ubuntu 26.04 LTS amd64v3 cloud-init template on Proxmox.
2. Clones a VM from the chosen template and configures its hardware.
3. Boots and bootstraps Ubuntu, installs prerequisites and configures the `dune` service account.
4. Installs SteamCMD and downloads the Linux Dune server files (Steam app ID `4754530` by default).
5. Installs/configures k3s and the required Funcom operators and images.
6. Creates and configures the self-hosted world, waits for server readiness and prints verification commands.

The wrapper asks for VM sizing, network, SSH keys, server/world settings, public IP override and the Funcom self-host token.

## VM defaults

| Setting | Default |
|---|---|
| Proxmox template VMID | Reuse existing: `8010`; create new: `200` |
| New Dune VMID | `201` |
| CPU cores | `6` |
| CPU type | `host` |
| RAM | `40 GiB` |
| Ballooning | Disabled |
| Disk | `110 GiB` |
| Proxmox bridge | `vmbr0` |
| Proxmox storage | `local-lvm` |
| Guest network | Static IPv4/CIDR, prompted by wrapper |
| Ubuntu image for new template | `ubuntu-26.04-server-cloudimg-amd64v3.img` |

Adjust defaults when prompted to match your own Proxmox environment. Storage must support VM disks and cloud-init volumes.

## Requirements

### Proxmox VE

- Reachable Proxmox node with permission to create, clone, configure, start and import VM disks.
- Storage with sufficient free space for the template and a Dune VM disk of at least 110 GiB.
- A configured bridge (for example `vmbr0`).
- A host CPU that supports the x86-64-v3 instruction set if you create/use the amd64v3 template.
- If you reuse a template, ensure it is Ubuntu 26.04 LTS amd64v3 and has working cloud-init.

### Ansible controller

The controller may be a Linux workstation, WSL Ubuntu or another Linux host that can SSH to Proxmox and the new guest.

Install:

- `git`
- `bash`
- `ssh`
- `python3`
- `python3-venv`
- `ansible`

Create or choose an SSH key pair. The public key is injected into the VM by cloud-init; the matching private key is used by Ansible to connect to the guest. A dedicated key pair for this server is recommended.

### Network and game setup

- Reserve a static LAN IP for the VM and know the subnet CIDR and gateway.
- Ensure the guest can reach the internet.
- Configure router/firewall forwarding if players outside your LAN need to connect.
- The default ports documented by this workflow are UDP `7777-7890` and TCP `31982`. Verify current requirements before exposing the server.
- Obtain a valid self-host token from Funcom. The wrapper prompts for it as a secret; do not commit it to the repository or paste it into public logs.

## Quick start

On a Linux or WSL Ubuntu controller:

```bash
sudo apt update
sudo apt install -y git python3 python3-venv openssh-client
git clone https://github.com/comfuzio/Dune-Awakening-Ansible-Self-Hosted-CPU-Optimized-.git
cd Dune-Awakening-Ansible-Self-Hosted-CPU-Optimized-
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install ansible
ssh-keygen -t ed25519 -f ~/.ssh/dune_vm_ed25519
```

Edit `inventory/inventory.ini` with your Proxmox host address and SSH user:

```ini
[proxmox]
pve ansible_host=YOUR_PROXMOX_IP ansible_user=YOUR_PROXMOX_USER
```

Run the wrapper:

```bash
chmod +x scripts/run_full_setup.sh
./scripts/run_full_setup.sh
```

When prompted, use the dedicated key paths if you created the example key:

- Private key: `~/.ssh/dune_vm_ed25519`
- Public key: `~/.ssh/dune_vm_ed25519.pub`

The wrapper's default key paths are `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`; enter the paths you actually use.

## Existing template example

If you already have the right template at VMID `8010`:

1. Start `./scripts/run_full_setup.sh`.
2. Answer `y` to reuse an existing Ubuntu 26.04 LTS amd64v3 template.
3. Enter `8010` when asked for the template VMID.
4. Provide an unused VMID for the new Dune VM, then configure its name, storage, bridge, CPU, RAM, disk, IP, gateway, keys and world details.

The wrapper skips template creation and proceeds to clone from the supplied template. It does not inspect the image's internal build provenance, so verify that your existing template really is Ubuntu 26.04 amd64v3 with cloud-init before using it.

## Manual playbook order

The supported full workflow is the wrapper. If running playbooks manually, the intended order is:

1. `playbooks/01_build_template.yml` — only when creating a new template.
2. `playbooks/02_create_vm.yml`
3. `playbooks/03_bootstrap_vm.yml`
4. `playbooks/04_install_steamcmd.yml`
5. `playbooks/05_install_dune_server.yml`
6. `playbooks/06_install_k3s.yml`
7. `playbooks/07_bootstrap_kubernetes.yml`
8. `playbooks/10_run_vendor_setup.yml`

Optional helper playbooks are `08_run_dune_setup.yml` and `09_customize_world_template.yml`.

## Validation after setup

On the Dune VM:

```bash
kubectl get pods -A
/home/dune/.dune/download/scripts/battlegroup.sh status
```

The successful end state should show a healthy battlegroup and the core maps running. Use the individual map and pod states to diagnose startup issues.

## Security and operational notes

- Do not commit self-host tokens, SSH private keys, passwords, or real inventory details.
- Review firewall exposure carefully; do not expose SSH publicly unless necessary and secured.
- The wrapper uses SSH host-key checking settings from the upstream workflow for unattended bootstrap. Understand the security trade-off before using it outside a trusted lab.
- The automation has not been validated against every Proxmox version or every host CPU. Test it in a non-production environment before relying on it.
- This project installs the Linux dedicated-server deployment; it does **not** import Funcom's official server VHDX.

## Alternative: official Funcom VM on Proxmox

For the separate approach that runs Funcom's official virtual disk directly on Proxmox, see [Comfuzio's Dune: Awakening Proxmox self-hosting guide](https://github.com/comfuzio/dune-awakening-proxmox-self-hosting). That guide is a reference and is not part of this Ubuntu-based installation workflow.

## Upstream method

This project adapts the Ansible-based method and server setup sequence documented by [IEquilibriumI/dune-selfhost-ansible](https://github.com/IEquilibriumI/dune-selfhost-ansible). Refer to that repository for upstream context and implementation history; see [UPSTREAM.md](UPSTREAM.md) for attribution and licensing notes.
