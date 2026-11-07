# nixconf

Configuration files for NixOS and Home Manager
![image](https://github.com/user-attachments/assets/7e27dec8-1485-4878-88d9-a9dbe81463a1)

## Overview

This config uses [hyprland](https://hyprland.org/) as a window manager, and uses Qt-based applications wherever possible.

It is themed heavily with [Catppuccin](https://catppuccin.com/) Mocha (mauve accent).

## Structure

`ls modules` is the menu: every entry except `flake/` and `hosts/` is a feature, and a file's folder says which hosts get it.

- `modules/hosts/<hostname>/`: each computer's feature list, display data, and machine-specific config.
- `modules/flake/`: the host builder and other flake plumbing.
- `pkgs/<name>/package.nix`: custom packages, exposed as `pkgs.<name>`.

New files must be `git add`ed before evaluating because flakes only see tracked files.

## macOS

The Apple-silicon configuration is `darwinConfigurations.macos`. It expects the official Nix installer, the native 1Password app, and this repository at `/Users/drew/nixconf`.

```sh
nix run github:nix-darwin/nix-darwin -- switch --flake .#macos
```

## Other Notes

This config uses [catppuccin-nix](https://github.com/catppuccin/nix) to automatically theme most applications.

I have made an effort to stick primarily to Nix language configuration where possible, as opposed to various `.json`, `.toml`, `.yaml`, etc. files being added by home manager.

