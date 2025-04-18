#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/nvme0n1"
HOSTNAME="nixos"
USERNAME="username"
TIMEZONE="America/Sao_Paulo"
SWAPSIZE="4G"
STATEVERSION="24.11"

echo "==> Limpando partições anteriores"
wipefs -af "$DISK"

echo "==> Criando tabela de partição"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart primary 512MiB 100%
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 2 esp on

echo "==> Criando sistema de arquivos"
mkfs.vfat -F32 -n BOOT "${DISK}p2"
mkfs.btrfs -L nixos "${DISK}p1"

echo "==> Criando subvolumes Btrfs"
mount "${DISK}p1" /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @nix
btrfs subvolume create @persist
btrfs subvolume create @swap
cd /
umount /mnt

echo "==> Montando subvolumes"
mount -o subvol=@,compress=zstd,noatime,ssd,discard=async "${DISK}p1" /mnt
mkdir -p /mnt/{boot,home,nix,persist,swap}
mount -o subvol=@home,compress=zstd,noatime,ssd,discard=async "${DISK}p1" /mnt/home
mount -o subvol=@nix,compress=zstd,noatime,ssd,discard=async "${DISK}p1" /mnt/nix
mount -o subvol=@persist,compress=zstd,noatime,ssd,discard=async "${DISK}p1" /mnt/persist
mount -o subvol=@swap,compress=zstd,noatime,ssd,discard=async "${DISK}p1" /mnt/swap
mount "${DISK}p2" /mnt/boot

mkdir -p /mnt/nix/store

echo "==> Criando swapfile"
btrfs filesystem mkswapfile --size $SWAPSIZE /mnt/swap/swapfile
swapon /mnt/swap/swapfile

echo "==> Gerando configuração do sistema"
nixos-generate-config --root /mnt

#echo "==> Criando Backup hardware-configuration.nix"
#mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hardware-configuration.nix.bak

echo "==> Criando configuration.nix"
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader = {
    systemd-boot.enable = true;
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
  };

  networking.hostName = "$HOSTNAME";
  time.timeZone = "$TIMEZONE";

  users.users.$USERNAME = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos";
  };

  services.openssh.enable = true;
  system.stateVersion = "$STATEVERSION";
}
EOF

echo "==> Instalando NixOS"
nixos-install --no-root-password

echo "==> Instalação concluída com sucesso!"
echo "==> Execute 'reboot' para reiniciar o sistema"
