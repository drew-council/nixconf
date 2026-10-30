# nixconf

Configuration files for NixOS and Home Manager
![image](https://github.com/user-attachments/assets/7e27dec8-1485-4878-88d9-a9dbe81463a1)

## Overview

This config uses [hyprland](https://hyprland.org/) as a window manager, and uses Qt-based applications wherever possible.

It is themed heavily with [Catppuccin](https://catppuccin.com/) Mocha (mauve accent).

## Structure

Each computer hostname has a folder in `hosts` and an entry in the `flake.nix` file. These can then import various host-specific modules.
For now, all computers also import the `home/home.nix` module to use for home manager.

## macOS

The Apple-silicon configuration is `darwinConfigurations.macos`. It expects the official Nix installer, the native 1Password app, and this repository at `/Users/drew/nixconf`.

```sh
nix run github:nix-darwin/nix-darwin -- switch --flake .#macos
```

## Other Notes

This config uses [catppuccin-nix](https://github.com/catppuccin/nix) to automatically theme most applications.

I have made an effort to stick primarily to Nix language configuration where possible, as opposed to various `.json`, `.toml`, `.yaml`, etc. files being added by home manager.

