

# Nixos Btrfs + LUKS PT-BR
## Intalar via SH
```
git clone https://github.com/gabperes21/nixos-config-br
cd niox-config-br
chmod 777 install.sh
./install.sh
```
## Adicionar prioridade no /log

Adicionar `neededForBoot = true;` para ser montado o quanto antes

```bash
sudo nano /etc/nixos/hardware-configuration.nix
```

```nix
  fileSystems."/var/log" =
    { device = "/dev/disk/by-uuid/XXXXX";
      fsType = "btrfs";
      options = [ "subvol=log" "compress=zstd" "noatime" ];
      neededForBoot = true;
    };
```
