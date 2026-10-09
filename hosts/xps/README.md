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
username, password **hash**, signing secret, and `OP_SERVICE_ACCOUNT_TOKEN`.
The dashboard will not start without this file. The generated plaintext dashboard password stays in 1Password.

`hermes.nix` owns the model and Composio settings. Home Manager merges them into
writable `~/.hermes/config.yaml` on activation, preserving other settings. Dashboard
edits work immediately, but edits to these Nix-managed settings are reset on the
next activation; change `hermes.nix` to make them persistent.

## Browser logins through 1Password

The **Agent Access** custom vault is the access boundary. The **Hermes XPS Agent
Access** service account has `read_items` permission on this vault only: no
writes, sharing, vault creation, or access to Private. Its token is stored in
Private as **XPS Hermes Agent Access service account** and in XPS's private
`.env`. It has no configured expiry; revoke it in 1Password when no longer needed.

Move approved Login items into Agent Access and keep their website URLs accurate.
Hermes's native `browser_vault_list`, `browser_vault_fill`, and
`browser_vault_enter_code` tools read current items on demand. Passwords and stored
TOTP codes are filled locally on matching origins, not returned in ordinary tool
output. No account password, desktop approval, synchronization server, or local
password export is required. The initial approved Login is **Gobreeze** at
<https://web.gobreeze.com>.

The pinned Hermes backend omits the `--vault` required by service-account item
reads. Its Nix-generated `hermes-op` wrapper supplies Agent Access's vault ID,
permits only item list/get, and refuses desktop authentication or other vault
arguments. Credentials are never embedded in that wrapper or Nix configuration.

`hermes-browser.service` runs sandboxed, headless Chromium with a separate
persistent profile at `~/.hermes/browser-agent-access/` (directory 700). Hermes
connects through CDP on **127.0.0.1:9223**; this control port is not exposed to the
LAN. The browser uses its basic local password store to avoid interactive keyring
prompts; filesystem permissions, not a separate browser-unlock password, protect
its session state. XPS is dedicated to Hermes and its full machine access is
intentional. Do not enable copying your personal desktop browser profile.

Removing an item prevents future authorized reads but does **not** terminate
website sessions already issued. Log out/revoke sessions at the website as well
when removing access. Treat browser cookies as credentials. Vault scoping limits
credential access, not the actions those website accounts permit; shared SSO
accounts may grant access to multiple applications. Hardware keys, passkeys,
CAPTCHAs, SMS/email codes, and push approvals can still require your participation.
Normal autofill avoids exposing passwords to the model; unrestricted shell access
is not a guarantee that the agent cannot retrieve its approved credentials.

Authenticated medical application contents are private to Hermes under the
user's chosen ZDR provider policy. Maintenance assistants must not read private
page text, screenshots, records, or Hermes session transcripts. Validate externally
using only service health and generic login/verification status signals.

Use `nh os switch` on XPS to apply changes. Inspect the services with
`systemctl status hermes-dashboard hermes-browser` or
`journalctl -u hermes-dashboard -u hermes-browser`.
