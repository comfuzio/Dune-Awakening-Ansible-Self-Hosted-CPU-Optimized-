# Dune: Awakening — Proxmox VM Automation (Ubuntu 26.04 amd64v3)

> **Status: infrastructure automation; validate on a test VM before production use.** This project creates Proxmox VM templates and VMs. It does not distribute Funcom game files or virtual disks.

This is a redesign of the earlier Docker/Ansible approach. That approach assumed SteamCMD supplied a conventional Linux server executable (`DuneServer.sh`). The official deployment method documented in [my Proxmox self-hosting guide](https://github.com/comfuzio/dune-awakening-proxmox-self-hosting) instead downloads `dune-server.vhdx`, a complete virtual disk containing the official Alpine/k3s server environment.

**Important compatibility point:** an Ubuntu 26.04 amd64v3 VM template is not a drop-in replacement for Funcom's VHDX. The official VHDX is already a bootable operating-system disk. There is no supported step in the documented workflow that installs that server directly into an Ubuntu guest. This repository therefore offers two honest workflows rather than pretending the Docker `DuneServer.sh` approach works:

1. **Ubuntu template workflow:** create or reuse a Proxmox Ubuntu 26.04 amd64v3 cloud-init template, then clone it to a VM with the requested hardware. This creates a ready Ubuntu VM, **not a Dune server**.
2. **Official Dune workflow:** import the official Funcom VHDX into a new Proxmox VM with the hardware and disk configuration from the existing guide. This is the workflow for actually running the official server using the current packaging.

## Features

- Interactive prompts for template ID, VM ID, Proxmox storage, bridge, VM name, and SSH public key.
- Optional reuse of an existing Proxmox template; no duplicate template is created unless you choose that option.
- Official Ubuntu 26.04 `amd64v3` cloud image download, SHA-256 verification against Canonical's published `SHA256SUMS`, and conversion to a Proxmox template.
- Ubuntu clone defaults: `--cpu host`, 6 cores, 40960 MiB RAM, ballooning disabled, 110 GiB disk, virtio NIC, user-selected bridge, cloud-init DHCP, and SSH-key login.
- Official Dune VM defaults: `--cpu host`, 6 cores, 40960 MiB RAM, ballooning disabled, virtio NIC, OVMF/EFI, `virtio-scsi-single`, official disk attached as `scsi0`, and an additional `+110G` disk resize as documented in the guide.
- Refuses to overwrite an existing VMID. No VM deletion or destructive Docker cleanup.

## Requirements

- Run the script **as root on the Proxmox VE node**. It uses `qm` and `pvesm` locally; it is not an Ansible playbook to run against the guest OS.
- Proxmox VE with a storage target that supports VM disk images and cloud-init volumes.
- A network bridge such as `vmbr0` already configured on the node.
- Host CPU support for x86-64-v3 for the amd64v3 template; the script checks key CPU flags exposed by the host before creating it. The guest will inherit host CPU features via `cpu: host`.
- `curl` and `sha256sum` for the Ubuntu template workflow.
- For the official Dune workflow, either an existing `dune-server.vhdx` file or SteamCMD already installed on the Proxmox node. SteamCMD installation is deliberately not performed automatically because it may require changing host APT repositories and enabling i386 packages.

## Run it

Copy the repository to the Proxmox node, then:

```bash
chmod +x proxmox/dune-proxmox.sh
./proxmox/dune-proxmox.sh
```

Choose one of the menu options:

### 1. Create Ubuntu 26.04 amd64v3 template

The script asks for the new template VMID, name, storage ID, and bridge. It downloads the official cloud image from Canonical, verifies its checksum, imports it, configures cloud-init and EFI, expands the template disk to 32 GiB, then converts the VM into a template.

### 2. Clone an existing template

Provide the template VMID and the new VMID. The source must already be marked as a Proxmox template. The script asks for the destination storage, bridge, name, SSH **public** key file, and cloud-init IP setting (default `ip=dhcp`). It clones and configures the VM with:

- CPU type: `host`
- vCPU cores: `6`
- Memory: `40960` MiB (40 GiB)
- Ballooning: disabled (`0`)
- Disk: `110G` total virtual disk size
- Network: `virtio` on the selected bridge
- Boot: SCSI 0, `virtio-scsi-single`

If the existing template's disk is already larger than 110 GiB, Proxmox will not shrink it; the script's resize command only grows disks. Use a template with a disk smaller than 110 GiB if you require that exact size.

### 3. Create a VM from the official Dune VHDX

Provide the VHDX path, or leave it blank to download through an already-installed SteamCMD. The script imports the disk and attaches it as **SCSI 0**, adds an EFI disk, uses `cpu: host`, 6 cores, 40 GiB RAM, disabled ballooning, and a selected virtio bridge. It then grows the disk by `+110G`, matching the existing guide's instruction (this is **not** a total disk size of 110 GiB).

After boot, follow the [official VHDX/Proxmox guide](https://github.com/comfuzio/dune-awakening-proxmox-self-hosting) for guest networking, initial setup, battlegroup initialization, and port forwarding. The VM's guest network may need DHCP or static-IP configuration from inside Alpine.

## About amd64v3 and performance

The amd64v3 Ubuntu image is a real Canonical image, not a standard image with `CFLAGS` set. It can optimize compatible Ubuntu userland components compiled for that ISA level. It does **not** automatically recompile arbitrary game binaries, and it does not change the operating system inside Funcom's Alpine VHDX. The official Dune route uses `cpu: host` to expose supported host CPU features to the guest, but whether that improves the game's performance must be measured rather than assumed.

## Safety and limitations

- Review the prompts before confirming any VM creation.
- The script never removes an existing VM, template, disk, or storage volume.
- Use unique VMIDs and verify the chosen storage and bridge.
- The Ubuntu VM option is a general-purpose Ubuntu VM. Do not treat it as a working Dune installation.
- The official VHDX option requires SteamCMD or a VHDX you obtained yourself, and requires the guest setup steps in the guide.
- The script has not been executed against your Proxmox cluster from this environment; test on a non-production VM first.

## Related project

- [Dune Awakening Proxmox self-hosting guide](https://github.com/comfuzio/dune-awakening-proxmox-self-hosting)
