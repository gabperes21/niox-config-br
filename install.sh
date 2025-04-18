#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
HOSTNAME="nixos"
USERNAME="usuario"
TIMEZONE="America/Sao_Paulo"
SWAPSIZE="8G"
STATEVERSION="24.11"

# Limpeza e preparação do disco
echo "==> Limpando partições anteriores"
wipefs -af "$DISK"

echo "==> Criando tabela de partição"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart primary 512MiB 100%
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 2 esp on

echo "==> Configurando LUKS"
cryptsetup luksFormat --type luks2 "${DISK}p1"
cryptsetup open "${DISK}p1" cryptroot

echo "==> Criando sistemas de arquivos"
mkfs.vfat -F32 -n BOOT "${DISK}p2"
mkfs.btrfs -L ROOT /dev/mapper/cryptroot

echo "==> Criando subvolumes Btrfs"
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@swap
umount /mnt

echo "==> Montando estrutura"
mount -o subvol=@,compress=zstd,noatime,ssd,discard=async /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,nix,swap}
mount -o subvol=@home,compress=zstd,noatime,ssd,discard=async /dev/mapper/cryptroot /mnt/home
mount -o subvol=@nix,compress=zstd,noatime,ssd,discard=async /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@swap,compress=zstd,noatime,ssd,discard=async /dev/mapper/cryptroot /mnt/swap
mount "${DISK}p2" /mnt/boot

echo "==> Configurando swap"
btrfs filesystem mkswapfile --size $SWAPSIZE /mnt/swap/swapfile
swapon /mnt/swap/swapfile

echo "==> Gerando configuração base"
nixos-generate-config --root /mnt

echo "==> Criando configuration.nix"
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.initrd = {
    availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
    kernelModules = [ "dm-snapshot" ];
    luks.devices."cryptroot" = {
      device = "/dev/disk/by-partuuid/$(blkid -s PARTUUID -o value ${DISK}p1)";
      allowDiscards = true;
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.supportedFilesystems = [ "btrfs" ];

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" "ssd" "discard=async" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" "ssd" "discard=async" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" "ssd" "discard=async" ];
  };

  fileSystems."/swap" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@swap" ];
  };

  swapDevices = [ {
    device = "/swap/swapfile";
    priority = 0;
  } ];

  networking.hostName = "${HOSTNAME}";
  time.timeZone = "${TIMEZONE}";

  users.users.${USERNAME} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };

  system.stateVersion = "${STATEVERSION}";
}
EOF

echo "==> Instalando NixOS"
nixos-install --no-root-password --flake github:youruser/yourrepo#yourhost

echo "==> Instalação concluída!"
echo "==> Execute 'reboot' para reiniciar o sistema"
