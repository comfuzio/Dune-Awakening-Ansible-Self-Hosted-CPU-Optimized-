#!/usr/bin/env bash
set -Eeuo pipefail

# Run as root on a Proxmox VE node. This script never deletes existing VMs or disks.
UBUNTU_IMAGE="ubuntu-26.04-server-cloudimg-amd64v3.img"
UBUNTU_BASE_URL="https://cloud-images.ubuntu.com/releases/server/26.04/release"
DEFAULT_DISK_SIZE="110G"
DEFAULT_CORES="6"
DEFAULT_MEMORY="40960"

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

need_root_and_pve() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || { red "Run as root on a Proxmox VE node."; exit 1; }
  command -v qm >/dev/null || { red "qm not found; this must run on a Proxmox VE node."; exit 1; }
  command -v pvesm >/dev/null || { red "pvesm not found."; exit 1; }
  command -v curl >/dev/null || { red "curl is required."; exit 1; }
  command -v sha256sum >/dev/null || { red "sha256sum is required."; exit 1; }
}

ask() {
  local __var="$1" __prompt="$2" __default="${3:-}" __value
  if [[ -n "$__default" ]]; then
    read -r -p "$__prompt [$__default]: " __value
    __value="${__value:-$__default}"
  else
    read -r -p "$__prompt: " __value
  fi
  printf -v "$__var" '%s' "$__value"
}
ask_required() {
  local __var="$1" __prompt="$2" __value
  while :; do
    read -r -p "$__prompt: " __value
    [[ -n "$__value" ]] && break
    red "A value is required."
  done
  printf -v "$__var" '%s' "$__value"
}
confirm() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
vmid_unused() {
  local id="$1"
  [[ "$id" =~ ^[0-9]+$ ]] || { red "VMID must be numeric."; return 1; }
  if qm config "$id" >/dev/null 2>&1; then
    red "VMID $id already exists. Nothing has been changed."
    return 1
  fi
}
storage_exists() {
  pvesm status --storage "$1" >/dev/null 2>&1 || { red "Storage '$1' is not available."; return 1; }
}
bridge_exists() {
  [[ -d "/sys/class/net/$1" ]] || { red "Bridge/interface '$1' was not found on this node."; return 1; }
}
check_v3_cpu() {
  local flags missing=() f
  flags="$(awk -F: '/^flags[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo)"
  for f in avx avx2 bmi1 bmi2 f16c fma movbe xsave; do
    [[ " $flags " == *" $f "* ]] || missing+=("$f")
  done
  [[ " $flags " == *" lzcnt "* || " $flags " == *" abm "* ]] || missing+=("lzcnt/abm")
  if (( ${#missing[@]} )); then
    red "Host CPU is missing checked x86-64-v3 flags: ${missing[*]}"
    red "Check CPU/BIOS support before creating an amd64v3 template."
    return 1
  fi
  green "Host CPU exposes the checked x86-64-v3 instruction flags."
}
ask_storage_and_bridge() {
  ask_required STORAGE "Proxmox storage ID for VM disks (e.g. local-zfs)"
  storage_exists "$STORAGE"
  ask BRIDGE "Proxmox network bridge" "vmbr0"
  bridge_exists "$BRIDGE"
}

create_ubuntu_template() {
  local template_id name image_dir image checksum_line
  check_v3_cpu
  ask_required template_id "New template VMID"
  vmid_unused "$template_id"
  ask name "Template name" "ubuntu-26.04-amd64v3-cloudinit"
  ask_storage_and_bridge

  image_dir="/var/lib/vz/template/cache/ubuntu-amd64v3"
  image="$image_dir/$UBUNTU_IMAGE"
  mkdir -p "$image_dir"
  yellow "Downloading Canonical Ubuntu 26.04 amd64v3 cloud image and SHA256SUMS."
  curl --fail --location --retry 3 --output "$image_dir/SHA256SUMS" "$UBUNTU_BASE_URL/SHA256SUMS"
  curl --fail --location --retry 3 --output "$image" "$UBUNTU_BASE_URL/$UBUNTU_IMAGE"
  checksum_line="$(grep -F "$UBUNTU_IMAGE" "$image_dir/SHA256SUMS" | head -n1 || true)"
  [[ -n "$checksum_line" ]] || { red "Image not found in official SHA256SUMS; aborting."; exit 1; }
  (cd "$image_dir" && printf '%s\n' "$checksum_line" | sha256sum --check --status) || {
    red "Image checksum verification failed; not importing."; exit 1;
  }
  green "Ubuntu image checksum verified."

  qm create "$template_id" --name "$name" --memory 4096 --cores 2 --cpu host \
    --net0 "virtio,bridge=$BRIDGE,firewall=1" --ostype l26 --machine q35 --bios ovmf \
    --scsihw virtio-scsi-single --serial0 socket --vga serial0
  qm importdisk "$template_id" "$image" "$STORAGE"
  qm set "$template_id" --scsi0 "$STORAGE:vm-$template_id-disk-0,discard=on,ssd=1" \
    --efidisk0 "$STORAGE:0,efitype=4m,pre-enrolled-keys=1" --ide2 "$STORAGE:cloudinit" \
    --boot 'order=scsi0' --ipconfig0 'ip=dhcp' --agent 'enabled=1' --ciupgrade 1
  qm resize "$template_id" scsi0 32G
  qm template "$template_id"
  green "Created template $template_id ($name). This is a reusable Ubuntu template, not a Dune server."
}

clone_ubuntu_vm() {
  local template_id vm_id name key_file ip_setting
  ask_required template_id "Existing Ubuntu template VMID"
  qm config "$template_id" >/dev/null 2>&1 || { red "Template VMID $template_id does not exist."; return 1; }
  grep -qx 'template: 1' <(qm config "$template_id") || { red "VMID $template_id is not marked as a template."; return 1; }
  ask_required vm_id "New VMID for cloned Ubuntu VM"
  vmid_unused "$vm_id"
  ask name "New VM name" "dune-ubuntu-$vm_id"
  ask_storage_and_bridge
  ask_required key_file "Path to SSH public key file (e.g. /root/.ssh/id_ed25519.pub)"
  [[ -f "$key_file" ]] || { red "SSH public key file not found."; return 1; }
  [[ "$key_file" == *.pub ]] || yellow "Filename does not end in .pub; ensure this is a public key."
  ask ip_setting "Cloud-init IP configuration" "ip=dhcp"

  qm clone "$template_id" "$vm_id" --full 1 --storage "$STORAGE" --name "$name"
  qm set "$vm_id" --name "$name" --cpu host --cores "$DEFAULT_CORES" --memory "$DEFAULT_MEMORY" \
    --balloon 0 --machine q35 --bios ovmf --scsihw virtio-scsi-single \
    --net0 "virtio,bridge=$BRIDGE,firewall=1" --ide2 "$STORAGE:cloudinit" \
    --ciuser ubuntu --sshkeys "$key_file" --ipconfig0 "$ip_setting" --agent 'enabled=1' \
    --boot 'order=scsi0' --serial0 socket --vga serial0
  qm resize "$vm_id" scsi0 "$DEFAULT_DISK_SIZE"
  green "Cloned template $template_id to VM $vm_id."
  printf 'CPU=host, cores=%s, RAM=%s MiB, ballooning=disabled, disk=%s, bridge=%s, storage=%s\n' \
    "$DEFAULT_CORES" "$DEFAULT_MEMORY" "$DEFAULT_DISK_SIZE" "$BRIDGE" "$STORAGE"
  yellow "This is a standard Ubuntu VM only; it does not install Dune: Awakening."
  if confirm "Start VM $vm_id now?"; then qm start "$vm_id"; fi
}

find_steamcmd() {
  if command -v steamcmd >/dev/null 2>&1; then command -v steamcmd; return 0; fi
  if [[ -x /usr/games/steamcmd ]]; then printf '%s\n' /usr/games/steamcmd; return 0; fi
  return 1
}
create_official_dune_vm() {
  local vm_id name vhdx download_dir steamcmd_path
  ask_required vm_id "New VMID for official Dune server VM"
  vmid_unused "$vm_id"
  ask name "VM name" "dune-awakening-$vm_id"
  ask_storage_and_bridge
  read -r -p "Path to dune-server.vhdx (blank to download via installed SteamCMD): " vhdx
  if [[ -z "$vhdx" ]]; then
    if ! steamcmd_path="$(find_steamcmd)"; then
      red "SteamCMD is not installed. Install it using your guide or supply a downloaded VHDX."
      red "No VM was created; this script will not alter host APT repositories."
      return 1
    fi
    download_dir="/var/lib/vz/template/cache/dune-awakening-download"
    mkdir -p "$download_dir"
    "$steamcmd_path" +@sSteamCmdForcePlatformType windows +force_install_dir "$download_dir" \
      +login anonymous +app_update 4754530 validate +quit
    vhdx="$download_dir/Virtual Hard Disks/dune-server.vhdx"
  fi
  [[ -f "$vhdx" ]] || { red "VHDX not found: $vhdx. No VM has been created."; return 1; }
  yellow "The official VHDX boots its bundled Alpine/k3s environment; this does not install Dune into Ubuntu."
  confirm "Create VM $vm_id from this VHDX on '$STORAGE' and grow disk by +110G?" || {
    yellow "Cancelled; no VM has been created."; return 0;
  }

  qm create "$vm_id" --name "$name" --memory "$DEFAULT_MEMORY" --cores "$DEFAULT_CORES" \
    --cpu host --balloon 0 --net0 "virtio,bridge=$BRIDGE,firewall=1" --ostype l26 \
    --machine q35 --bios ovmf --scsihw virtio-scsi-single --vga virtio
  qm importdisk "$vm_id" "$vhdx" "$STORAGE"
  qm set "$vm_id" --scsi0 "$STORAGE:vm-$vm_id-disk-0,discard=on,ssd=1" \
    --efidisk0 "$STORAGE:0,efitype=4m,pre-enrolled-keys=1" --boot 'order=scsi0'
  qm resize "$vm_id" scsi0 +110G
  green "Created official Dune VM $vm_id: CPU=host, 6 cores, 40 GiB RAM, no ballooning, virtio NIC, SCSI 0 boot."
  yellow "Disk was grown by +110G (not set to a total size of 110G). Follow the linked guide for guest setup."
  if confirm "Start VM $vm_id now?"; then qm start "$vm_id"; fi
}

main() {
  need_root_and_pve
  printf '\nDune: Awakening / Proxmox helper\n'
  printf '1) Create Ubuntu 26.04 amd64v3 cloud-init template\n'
  printf '2) Clone an existing template into a configured Ubuntu VM\n'
  printf '3) Create a VM from Funcom official Dune VHDX (for actual Dune deployment)\n'
  printf 'q) Quit\n\n'
  local choice
  read -r -p 'Choose an option: ' choice
  case "$choice" in
    1) create_ubuntu_template ;;
    2) clone_ubuntu_vm ;;
    3) create_official_dune_vm ;;
    q|Q) exit 0 ;;
    *) red "Invalid choice."; exit 2 ;;
  esac
}
main "$@"
