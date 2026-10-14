# Proxmox helper details

Run `dune-proxmox.sh` as root on a Proxmox VE node. It has three interactive modes:

1. Create a Canonical Ubuntu 26.04 amd64v3 cloud-init template.
2. Clone an existing Proxmox template into a 6-vCPU / 40-GiB RAM / no-balloon / 110-GiB Ubuntu VM.
3. Import Funcom's official Dune VHDX into a VM configured according to the linked self-hosting guide.

The Ubuntu and official-Dune routes are intentionally separate. Current official Dune packaging is a complete VHDX OS image, not a conventional Linux server binary that can be installed inside the Ubuntu template.

The helper refuses to overwrite an existing VMID and does not delete VMs or disks. Review prompts and test on a non-production VM first.
