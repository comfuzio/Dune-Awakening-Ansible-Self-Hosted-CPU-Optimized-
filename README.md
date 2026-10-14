# Dune: Awakening Ansible Deployment (Proxmox / ZFS / Ubuntu 26.04 v3)

> **⚠️ WORK IN PROGRESS / USE AT YOUR OWN RISK ⚠️**
> This is a work-in-progress project and should not be treated as a final, production-ready release just yet. Please ensure you back up your data regularly (as you ought to anyway). I am not responsible for any data loss, server crashes, or corrupted worlds. Proceed with caution.

An unapologetically modern, highly optimized Ansible playbook for deploying a self-hosted Dune: Awakening server. 

I built this because I am tired of the half-baked, outdated solutions floating around GitHub. After waste hours hours manually upgrading from Ubuntu 24.04, to 26.04, and finally to get `amd64v3` working, I decided to build it right from the ground up. No legacy baggage. No generic stock images. 

This is purpose-built for **Proxmox environments running ZFS**, utilizing an **Ubuntu 26.04 amd64v3** container base.

---

## Why this specific stack? (The Performance Breakdown)

Funcom's Alpine image is built for maximum legacy compatibility, meaning it wastes the potential of modern hardware. Here is exactly why this stack blows standard deployments out of the water:

### 1. Ubuntu 26.04 vs. Ubuntu 24.04
Running the latest 26.04 LTS brings significantly newer kernels and an updated `glibc`. For game servers, this means:
* **Smarter Thread Scheduling:** If you are assigning cores to your Proxmox VM/LXC on a modern CPU (especially Intel P/E core architectures or AMD Zen 4/5 chiplets), the 26.04 kernel scheduler handles Unreal Engine 5's multithreading vastly better than 24.04. 
* **ZFS Integration:** The newer kernel provides better native ZFS ARC (Adaptive Replacement Cache) memory management, preventing the host out-of-memory locking issues occasionally seen in heavy 24.04 ZFS deployments.

### 2. The `amd64v3` Architecture vs. Standard `amd64`
Standard Docker images compile for baseline `x86-64` hardware from almost two decades ago. By forcing `amd64v3` (x86-64-v3), we tell the container and its underlying libraries to natively utilize AVX, AVX2, BMI1, BMI2, and FMA instructions. 
* **Update & Patching Times:** SteamCMD downloads are heavily compressed. AVX2 instruction sets drastically speed up file decompression. Game updates that used to take 10 minutes to unpack will finish in a fraction of the time.
* **Startup Times:** Loading massive Unreal Engine 5 world data from disk into memory is bottlenecked by CPU decompression overhead. `amd64v3` cuts server boot times down noticeably.
* **Gameplay Tick Rate:** Unreal Engine server binaries rely heavily on vector math for physics, line-of-sight checks, and projectile calculations. AVX2 allows the CPU to process these calculations in bulk, keeping server tick rates stable even during massive sandstorms or base raids, completely separate from player population size.

### 3. Proxmox + ZFS
This setup is designed expecting ZFS underneath. When Docker creates the container volumes on a ZFS dataset, you benefit from inline LZ4/ZSTD compression and ARC. The server's constant small file reads (configuration, database state) are served directly from RAM rather than hitting your SSDs, drastically reducing I/O wait times during server saves.

---

## Prerequisites

* **Hypervisor:** Proxmox VE (latest).
* **Storage:** ZFS pool recommended for optimal Docker I/O and caching.
* **CPU:** Must support `x86-64-v3` instructions (Intel Haswell / AMD Excavator or newer). If your CPU was made in the last 10 years, you are likely fine.
* **Host OS:** A Proxmox LXC container or VM running Debian or Ubuntu.

## Deployment

1. Clone this repository to your Ansible control machine.
2. Edit `inventory.yml` with your target server's IP and SSH credentials.
3. Adjust your server variables in `group_vars/all.yml` (Name, slots, RCON password).
4. Run the playbook:
   ```bash
   ansible-playbook -i inventory.yml playbook.yml
