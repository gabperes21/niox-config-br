#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/sda"
HOSTNAME="nixos"
USERNAME="usuario"
TIMEZONE="America/Sao_Paulo"
SWAPSIZE="4G"
STATEVERSION="24.05"

echo "==> Limpando partições anteriores"
wipefs -a "$DISK"

echo "==> Criando tabela de partição"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart primary 512MiB 100%
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 2 esp on

echo "==> Configurando LUKS"
cryptsetup luksFormat "${DISK}1"
cryptsetup open "${DISK}1" cryptroot

echo "==> Criando sistema de arquivos"
mkfs.vfat -n BOOT "${DISK}2"
mkfs.btrfs -L nixos /dev/mapper/cryptroot

echo "==> Criando subvolumes Btrfs"
mount /dev/mapper/cryptroot /mnt
for subvol in @ @home @log @nix @persist @swap; do
  btrfs subvolume create "/mnt/$subvol"
done
umount /mnt

echo "==> Montando subvolumes"
mount -o subvol=@ /dev/mapper/cryptroot /mnt
for dir in home log nix persist swap; do
  mkdir -p "/mnt/$dir"
  mount -o subvol=@$dir /dev/mapper/cryptroot "/mnt/$dir"
done
mkdir -p /mnt/boot
mount "${DISK}2" /mnt/boot

echo "==> Criando swapfile"
btrfs filesystem mkswapfile --size $SWAPSIZE /mnt/swap/swapfile
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile

echo "==> Gerando configuração do sistema"
nixos-generate-config --root /mnt

echo "==> Substituindo configuration.nix"
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."cryptroot".device = "${DISK}1";

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };
  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" ];
  };
  fileSystems."/log" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@log" ];
  };
  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" ];
  };
  fileSystems."/persist" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@persist" ];
  };
  fileSystems."/boot" = {
    device = "${DISK}2";
    fsType = "vfat";
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];

  boot.kernelPackages = pkgs.linuxPackages_hardened;

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

