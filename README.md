

# Nixos Btrfs + LUKS PT-BR
# Intalar via SH
```
git clone https://github.com/gabperes21/nixos-config-br
cd niox-config-br
./install.sh
```

# Manual
## Baixe e inicie com a ISO mínima.
Baixe e inicie com a ISO mínima.

## Baixe e inicie com a ISO mínima.
Atenção: isso apaga todo o disco!
```bash
# Crie tabela de partição GPT
parted /dev/sda -- mklabel gpt

# Crie partições
parted /dev/sda -- mkpart primary 512MiB 100%
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 2 esp on

# Criptografe a partição principal
cryptsetup luksFormat /dev/sda1
cryptsetup open /dev/sda1 cryptroot
```

## Criar sistema de arquivo
```bash
# Boot
mkfs.vfat -n BOOT /dev/sda2

# Btrfs
mkfs.btrfs -L nixos /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

# Criar subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@persist
btrfs subvolume create /mnt/@swap
umount /mnt
```

## Montar os subvolumes
```bash
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,log,nix,persist,swap}
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@log /dev/mapper/cryptroot /mnt/log
mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@persist /dev/mapper/cryptroot /mnt/persist
mount -o subvol=@swap /dev/mapper/cryptroot /mnt/swap
mount /dev/sda2 /mnt/boot
```
##  Instalar o sistema base
```
nixos-generate-config --root /mnt
```

## Editar /mnt/etc/nixos/configuration.nix

Utilizando `Kernel Hardened`

```nix
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."cryptroot".device = "/dev/sda1";

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
    device = "/dev/sda2";
    fsType = "vfat";
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];

  boot.kernelPackages = pkgs.linuxPackages_hardened;

  networking.hostName = "nixos";
  time.timeZone = "America/Sao_Paulo";

  users.users.seuUsuario = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  services.openssh.enable = true;
  system.stateVersion = "24.05";
}
```
## Instalar 
```bash
nixos-install
```

## Reboot
```bash
reboot
```
