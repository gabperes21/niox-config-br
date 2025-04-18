#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
HOSTNAME="nixos"
USERNAME="usuario"
TIMEZONE="America/Sao_Paulo"
SWAPSIZE="8G"
STATEVERSION="24.11"

echo "==> Limpando partições anteriores"
wipefs -af "$DISK"

echo "==> Criando tabela de partição"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart primary 512MiB 100%
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 2 esp on

echo "==> Configurando LUKS"
cryptsetup luksFormat "${DISK}p1"
cryptsetup open "${DISK}p1" cryptroot

echo "==> Criando sistema de arquivos"
mkfs.vfat -n BOOT "${DISK}p2"
mkfs.btrfs -L nixos /dev/mapper/cryptroot

echo "==> Criando subvolumes Btrfs"
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@persist
btrfs subvolume create /mnt/@swap
umount /mnt

echo "==> Montando subvolumes"
mount -o subvol=@,compress=zstd,noatime /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,nix,persist,swap,boot}
mount -o subvol=@home,compress=zstd,noatime /dev/mapper/cryptroot /mnt/home
mount -o subvol=@nix,compress=zstd,noatime /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@persist,compress=zstd,noatime /dev/mapper/cryptroot /mnt/persist
mount -o subvol=@swap,compress=zstd,noatime /dev/mapper/cryptroot /mnt/swap
mount "${DISK}p2" /mnt/boot

echo "==> Criando swapfile"
btrfs filesystem mkswapfile --size $SWAPSIZE /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile

echo "==> Gerando configuração do sistema"
nixos-generate-config --root /mnt

echo "==> Criando Backup hardware-configuration.nix"
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hardware-configuration.nix.bak

echo "==> Criando novo hardware-configuration.nix"
cat > /mnt/etc/nixos/hardware-configuration.nix <<EOF
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@persist" "compress=zstd" "noatime" ];
  };

  fileSystems."/swap" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@swap" "compress=zstd" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "${DISK}p2";
    fsType = "vfat";
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
EOF

echo "==> Recuperando UUID da partição LUKS"
CRYPTUUID=$(blkid -s UUID -o value ${DISK}p1)

echo "==> Criando configuration.nix"
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/$CRYPTUUID";
    allowDiscards = true;
  };

  networking.hostName = "$HOSTNAME";
  time.timeZone = "$TIMEZONE";

  users.users.$USERNAME = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };

  services.openssh.enable = true;
  system.stateVersion = "$STATEVERSION";
}
EOF

echo "==> Instalando NixOS"
nixos-install --no-root-password

echo "==> Instalação concluída. Pronto para reiniciar."
