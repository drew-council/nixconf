# XPS Hermes Agent

Hermes is installed only on XPS from the pinned `llm-agents` flake input. Its
**official dashboard**, including browser chat, runs as `hermes-dashboard.service`
on boot at <http://192.168.1.145:9119>.

- Login: `drew`; password in the **Hermes XPS** item in 1Password's Private vault.
- Main model: `mistralai/mistral-large-4-0` through OpenRouter.
- Delegated agents: `deepseek/deepseek-v4.1-flash`, reasoning effort `high`.
- Composio: the same personal Composio Connect MCP account as Pi, with all its
  discovery/execution tools available and no added toolkit allowlist.
- Firewall: dashboard access is restricted to `192.168.1.0/24`. Existing service
  allowances, including SSH, remain in place. No router forwarding is configured.

Secrets live in `/home/drew/.hermes/.env` (mode 600, directory 700), never in Nix
or the store. It contains `OPENROUTER_API_KEY`, `COMPOSIO_API_KEY`, and the dashboard
username, password **hash**, and signing secret. The dashboard will not start
without this file. The generated plaintext dashboard password stays in 1Password.

`hermes.nix` owns the model and Composio settings. Home Manager merges them into
writable `~/.hermes/config.yaml` on activation, preserving other settings. Dashboard
edits work immediately, but edits to these Nix-managed settings are reset on the
next activation; change `hermes.nix` to make them persistent.

Use `nh os switch` on XPS to apply changes. Inspect the service with
`systemctl status hermes-dashboard` or `journalctl -u hermes-dashboard`.
