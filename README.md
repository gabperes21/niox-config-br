

# Nixos Btrfs + LUKS PT-BR
## Intalar via SH
```
git clone https://github.com/gabperes21/nixos-config-br
cd niox-config-br
chmod 777 install.sh
./install.sh
```
## Adicionar prioridade no /var/log

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

```
sudo nix flake update --flake /etc/nixos; and sudo nixos-rebuild switch --flake /etc/nixos#bilbo --upgrade
```


## Referencias

[Encypted Btrfs Root com Opt-in Estado em NixOS](https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html)
