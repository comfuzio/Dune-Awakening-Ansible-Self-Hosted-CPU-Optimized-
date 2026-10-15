# Dune: Awakening — Performance-focused self-hosted deployment

An Ansible-based workflow for deploying the Linux dedicated server for **Dune: Awakening** on a Proxmox VE virtual machine.

The project deliberately targets **Ubuntu Server 26.04 LTS amd64v3** on compatible x86-64 hardware. The aim is to establish a modern, capable baseline, remove avoidable deployment and VM overhead, and give server operators clear tools for validating and tuning their own systems. It does not promise a specific performance increase: the game workload, Funcom's binaries and services, CPU, storage, memory and network all affect results.

## Performance philosophy

Ubuntu 26.04 publishes an amd64v3 cloud image. The x86-64-v3 feature level includes AVX2 and additional instruction-set extensions. Funcom's published self-hosting requirements call for AVX2; this project intentionally selects the stricter amd64v3 baseline rather than treating AVX2 alone as proof that the host can run the image.

The Proxmox VM uses CPU type `host` so the guest can see the host CPU feature set. The host and guest must both support the required instructions. An amd64v3 operating system can use optimized system packages where available, but this does **not** automatically recompile or optimize Funcom's server binaries, and it does not guarantee a faster game server.

Our goal is to use available hardware capabilities sensibly, avoid unnecessary services and virtualization overhead, and measure results rather than advertise unverified gains. Further optimization of Funcom's server binaries, bundled components and server implementation ultimately requires changes from Funcom.

## Deployment model

This repository deploys the Linux server environment into an Ubuntu VM. It does **not** import or run Funcom's official server VHDX.

The automation creates or reuses a Proxmox cloud-init template, clones a VM, configures the guest, installs SteamCMD and the server payload, configures k3s and Funcom components, and runs the world setup sequence.

### Template choice

The wrapper asks whether to reuse an existing Ubuntu 26.04 LTS amd64v3 template.

- **Reuse:** answer `y` (default) and provide the template VMID (example: `8010`). Confirm manually that it really is Ubuntu 26.04 amd64v3 and has working cloud-init; the automation can validate Proxmox template status but cannot prove the guest image's build provenance.
- **Create:** answer `n`. The playbook downloads Canonical's Ubuntu 26.04 amd64v3 cloud image and checks its SHA-256 against Canonical's published `SHA256SUMS` before importing it.

The automation checks for VMID conflicts and does not intentionally delete existing VMs or templates. Review all prompts before proceeding.

## Default VM sizing

| Setting | Default |
|---|---|
| CPU type | `host` |
| vCPU cores | 6 |
| Memory | 40 GiB |
| Memory ballooning | Disabled |
| Disk | 110 GiB |
| Bridge | `vmbr0` |
| Storage | `local-lvm` |
| Ubuntu image | Ubuntu 26.04 LTS amd64v3 cloud image |
| Example template VMID | `8010` when reusing; `200` when creating |
| Example Dune VMID | `201` |

These are starting values, not a universal optimum. Leave sufficient memory for the host and other guests, and benchmark changes under representative server load. The best settings depend on the host CPU topology, storage backend, other workloads and player count.

## Requirements

### Proxmox host

- Proxmox VE with permission to create, clone, configure and start VMs, and import disks.
- A storage target that supports VM disks and cloud-init drives, with sufficient free capacity.
- A configured network bridge such as `vmbr0`.
- A CPU supporting the full x86-64-v3 feature set for the amd64v3 guest.
- SSH access from the Ansible controller.

### Ansible controller

A Linux workstation or WSL environment that can reach the Proxmox node and the guest. Install Git, Bash, Python 3, a Python virtual environment, OpenSSH client and Ansible.

Create or select an SSH key pair. The public key is injected into the guest; Ansible uses the matching private key. A dedicated key pair is recommended.

### Network and Funcom setup

- Reserve a guest IP address and know the subnet and gateway.
- Ensure the guest can reach required internet endpoints.
- Obtain a valid Funcom self-host token.
- Configure firewall and router forwarding only for ports required by the current server documentation. The current workflow documents UDP `7777-7890` and TCP `31982`; verify these before exposing the service.

Do not commit tokens, private keys, passwords or real inventory details.

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

Edit `inventory/inventory.ini` with your Proxmox host and SSH user:

```ini
[proxmox]
pve ansible_host=YOUR_PROXMOX_IP ansible_user=YOUR_PROXMOX_USER
```

Run the wrapper:

```bash
chmod +x scripts/run_full_setup.sh
./scripts/run_full_setup.sh
```

Enter the key paths you actually use when prompted. For the example key above, use `~/.ssh/dune_vm_ed25519` and `~/.ssh/dune_vm_ed25519.pub`.

## Validation and troubleshooting

After deployment, connect to the guest and inspect the cluster:

```bash
kubectl get nodes -o wide
kubectl get pods -A
/home/dune/.dune/download/scripts/battlegroup.sh status
```

A completed Ansible run is not by itself proof that the world is playable. Confirm the battlegroup and map services are healthy, then test connectivity from the intended player networks.

## Proxmox 9.2 compatibility and testing status

The workflow uses the Proxmox `qm` CLI for VM creation, disk import/attachment, cloning, cloud-init configuration, disk resizing and startup. These are established Proxmox VM-management operations, but command availability alone does not prove this complete workflow works on every Proxmox release.

**Proxmox VE 9.2.21 has not been tested against a live host in this development environment.** Static inspection can identify configuration and scripting problems, but cannot validate storage plugins, permissions, cloud-init boot, guest networking, current SteamCMD payloads, Funcom authentication or world creation. Test on a disposable VM and review the logs before production use.

Suggested preflight checks on the target Proxmox node:

```bash
pveversion -v
qm help create
qm help set
qm help importdisk
qm help resize
pvesm status
ip -br link
grep -m1 '^flags' /proc/cpuinfo
```

Record the output with the test report. Do not run a destructive cleanup as part of troubleshooting.

## Security and operational notes

- Ansible SSH host-key verification should remain enabled by default. Verify and trust the Proxmox and guest host keys rather than silently disabling verification.
- Protect the Funcom token and SSH private key. Avoid passing secrets in shell command-line arguments or logging them.
- Test in a non-production environment first.
- Use unique VMIDs and confirm the target storage and bridge before creating resources.
- Performance claims should be based on repeatable measurements, not CPU architecture labels alone.

## Alternative deployment method

For the separate approach that runs Funcom's official virtual disk directly on Proxmox, see [Comfuzio's Dune: Awakening Proxmox self-hosting guide](https://github.com/comfuzio/dune-awakening-proxmox-self-hosting). That is a separate project and is not part of this Ubuntu-based workflow.

## Licensing and third-party notices

This repository is licensed under AGPL-3.0. Some existing deployment logic was adapted from third-party GPL-3.0-licensed work. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the applicable notice. The repository's license does not remove or replace any license obligations that apply to incorporated third-party material.
