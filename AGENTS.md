# Repository Guidelines

## Project Structure & Module Organization
This repository is a Nix flake for NixOS + Home Manager.

- `flake.nix`: main entrypoint, inputs, outputs, host wiring, formatter/checks.
- `hosts/<hostname>/`: machine-specific NixOS configs (`configuration.nix`, `hardware-configuration.nix`).
- `modules/`: reusable system modules (base, server, laptop, display manager, package sets).
- `home/`: Home Manager modules, shell setup, WM configs, and scripts.
- `pkgs/`: custom package definitions.

## Build, Test, and Development Commands
- `nix flake check`: run flake checks (includes formatting check from `treefmt-nix`).
- `nix fmt`: format repository files via flake formatter.
- `nh os build`: build config for the current host.

## Coding Style & Naming Conventions
- Nix: keep modules focused and composable; prefer small imports over monolithic files.
- File naming: use lowercase kebab/snake style as already used (`remote-desktop.nix`, `hyprmonitor`).
- Python: max line length 79 (`pyproject.toml`), lint with Ruff.
- Shell scripting: prefer Nushell for new scripts when practical.

## Commit Guidelines
Commits are short, imperative, and scoped (examples: `add substituters config json`, `update flake.lock`, `format`).
Changes specific to a program use that as prefix (examples: `lazygit: fix copy keybind`, `herdr: set accent color to "mauve"`).

Follow that style:

- Keep subject lines concise and action-oriented.
- Separate refactors/formatting from behavior changes when possible.
- Link related issues/tasks and call out breaking configuration changes explicitly.

