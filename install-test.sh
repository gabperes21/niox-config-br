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

echo "==> Criptografando..."
cryptsetup --verify-passphrase -v luksFormat "$DISK"p3
cryptsetup open "$DISK"p3 enc

echo "==> Criando sistema de arquivos"
mkfs.vfat -n boot "$DISK"p1
mkswap "$DISK"p2
swapon "$DISK"p2
mkfs.btrfs /dev/mapper/enc

echo "==> Criando subvolumes Btrfs"
mount -t btrfs /dev/mapper/enc /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/nix
btrfs subvolume create /mnt/persist
btrfs subvolume create /mnt/log
btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
umount /mnt

echo "==> Montando subvolumes"
mount -o subvol=root,compress=zstd,noatime /dev/mapper/enc /mnt
mkdir /mnt/home
mount -o subvol=home,compress=zstd,noatime /dev/mapper/enc /mnt/home
mkdir /mnt/nix
mount -o subvol=nix,compress=zstd,noatime /dev/mapper/enc /mnt/nix
mkdir /mnt/persist
mount -o subvol=persist,compress=zstd,noatime /dev/mapper/enc /mnt/persist
mkdir -p /mnt/var/log
mount -o subvol=log,compress=zstd,noatime /dev/mapper/enc /mnt/var/log
mkdir /mnt/boot
mount "$DISK"p1 /mnt/boot

echo "==> Gerando configuração do sistema"
nixos-generate-config --root /mnt

echo "==> Criando configuration.nix"
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.kernelPackages = pkgs.linuxPackages_hardened;
  boot.supportedFilesystems = [ "btrfs" ];
  hardware.enableAllFirmware = true;
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "$HOSTNAME";
  networking.networkmanager.enable = true;
  
  time.timeZone = "$TIMEZONE";
  services.xserver.enable = true;

  users.users.$USERNAME = {
    isNormalUser = true;
    extraGroups = [ "wheel"];
    initialPassword = "nixos";
  };

  services.openssh.enable = true;
  system.stateVersion = "$STATEVERSION";
}
EOF

echo "==> Instalando NixOS..."
nixos-install --no-root-password

echo "==> Instalação concluída com sucesso!"
echo "==> Execute 'reboot' para reiniciar o sistema"
