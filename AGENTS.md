# Repository Guidelines

## Project Structure & Module Organization
This repository is a dendritic Nix flake for NixOS, nix-darwin, and Home Manager, built on flake-parts and import-tree.

- `flake.nix`: inputs; outputs load every `.nix` file under `modules/`.
- `modules/`: `ls modules` is the menu. Every entry except `flake/` and `hosts/` is a feature a host lists in `hosts.<name>.features`. Place a file by which hosts get it. Each file is a flake-parts module writing `flake.modules.<nixos|darwin|homeManager>.<feature>`.
- `modules/flake/`: host builder, nixpkgs, formatter, flake outputs.
- `modules/hosts/<hostname>/`: per-host features, display data, and machine-specific config. Paths with a `/_` component (`_hardware.nix`) are not auto-loaded and are imported explicitly.
- `pkgs/<name>/package.nix`: custom packages, exposed as `pkgs.<name>`.

New files MUST be `git add`ed before evaluating: flakes only see tracked files.

## Build, Test, and Development Commands
- `nix flake check`: run flake checks (includes formatting check from `treefmt-nix`).
- `nix fmt`: format repository files via flake formatter.
- `nh os build`: build config for the current host.

## Coding Style & Naming Conventions
- Nix: keep modules focused and composable; prefer small files over monolithic ones.
- File naming: use lowercase kebab/snake style as already used (`virt-manager.nix`, `hypr-monitor-profile`).
- Python: max line length 79 (`pyproject.toml`), lint with Ruff.
- Shell scripting: prefer Nushell for new scripts when practical.

## Commit Guidelines
Commits are short, imperative, and scoped (examples: `add substituters config json`, `update flake.lock`, `format`).
Changes specific to a program use that as prefix (examples: `lazygit: fix copy keybind`, `herdr: set accent color to "mauve"`).

Follow that style:

- Keep subject lines concise and action-oriented.
- Separate refactors/formatting from behavior changes when possible.
- Link related issues/tasks and call out breaking configuration changes explicitly.

