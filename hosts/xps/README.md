# XPS Hermes Agent

Hermes is installed only on XPS from the pinned `llm-agents` flake input. Its
**official dashboard**, including browser chat, runs as `hermes-dashboard.service`
on boot at <http://192.168.1.145:9119>.

- Login: `drew`; password in the **Hermes XPS** item in 1Password's Private vault.
- Main model: `deepseek/deepseek-v4.1-flash` through OpenRouter.
- Delegated agents: `deepseek/deepseek-v4.1-flash`, reasoning effort `high`.
- Composio: the same personal Composio Connect MCP account as Pi, with all its
  discovery/execution tools available and no added toolkit allowlist.
- Firewall: dashboard TCP 9119 and the Hermes-managed MacroDroid SMS receiver
  TCP 8788 are restricted to `192.168.1.0/24`. Existing service allowances,
  including SSH, remain in place. No router forwarding is configured.
  MacroDroid must reach XPS over the home LAN; cellular access is not enabled.
  Keep receiver credentials in its private runtime configuration, not Nix.
  The diagnostic server on TCP 8789 is intentionally not allowed.

Secrets live in `/home/drew/.hermes/.env` (mode 600, directory 700), never in Nix
or the store. It contains `OPENROUTER_API_KEY`, `COMPOSIO_API_KEY`, and the dashboard
username, password **hash**, signing secret, and `OP_SERVICE_ACCOUNT_TOKEN`.
The dashboard will not start without this file. The generated plaintext dashboard password stays in 1Password.

`hermes.nix` owns the model and Composio settings. Home Manager merges them into
writable `~/.hermes/config.yaml` on activation, preserving other settings. Dashboard
edits work immediately, but edits to these Nix-managed settings are reset on the
next activation; change `hermes.nix` to make them persistent.

## Gateway and Android

`hermes-gateway.service` runs Hermes's standard `gateway run` messaging/cron
process as a NixOS system service at boot, using the pinned package and existing
`.env`/config. It does not spawn a second dashboard. No messaging platform is
implicitly enabled or made public; configure platform credentials/settings when
adding Telegram, Discord, or another integration. Without any configured platform,
Hermes keeps the gateway running for scheduled jobs. Do not run `hermes gateway
install`: Nix owns this service. Lifecycle commands should target the system scope
(e.g. `hermes gateway status --system`).

[Hermes for Android](https://github.com/adebnar/hermes-android) connects to the
existing dashboard at **http://192.168.1.145:9119**. Use username **drew** and the
**Hermes XPS** password from Private; leave Token blank. This is not your 1Password
account password. The standalone gateway's running/off indicator is independent
of the dashboard listener. No additional connector/plugin or public port is needed.

The app's optional **Scan QR** accepts a v1 JSON payload containing `url`,
`username`, and optionally `password` or `token`. A QR containing only the URL and
username is safe to display; enter the password on the phone afterward. Do not
publish a credential-bearing pairing QR in logs or maintenance chat.

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

### Verification-code delivery

The official dashboard's `/chat` embeds the Ink TUI over PTY; its React sidebar
has a separate metadata session, not the chat session. The pinned upstream TUI
rejected `vault.code` requests even though Desktop/shared transport supported
that contract. `patches/hermes-vault-code.patch` adds the code prompt to the real
embedded TUI's existing masked input. Return sends a nonempty value directly as
`{result: {value: "…"}}` with the original string request ID; Esc explicitly
cancels. Codes never go through the chat composer or its history. Empty Return
keeps the prompt open. Refresh reconnects to the pending prompt within the
backend's existing 180-second deadline; a backend restart is not a replay.

`hermes.nix` patches only the pinned frontend derivation and redirects the Hermes
wrapper to it. It does not change backend versions, auth, network exposure,
browser sandbox/profile, or Agent Access authority. Native dashboard and WS
integration evidence and reproduction are in `tests/README.md`.

Activation is parent/operator-owned: apply the NixOS configuration on XPS with
`sudo nixos-rebuild switch --flake path:/home/drew/nixconf#xps` from an existing
authorized activation context. The `path:` form includes the new patch before
Git integration; ordinary Git-backed flakes require the patch to be tracked.
The changed package restarts Nix-owned services; an already-running old PTY must
be replaced before testing the new prompt. Do not launch a replacement user
gateway, unlock 1Password, or change the browser service. Synthetic fixture
success is not proof of any real account login or real-phone delivery.
Normal autofill avoids exposing passwords to the model; unrestricted shell access
is not a guarantee that the agent cannot retrieve its approved credentials.

Authenticated medical application contents are private to Hermes under the
user's chosen ZDR provider policy. Maintenance assistants must not read private
page text, screenshots, records, or Hermes session transcripts. Validate externally
using only service health and generic login/verification status signals.

Use `nh os switch` on XPS to apply changes. Inspect the services with
`systemctl is-active hermes-dashboard hermes-browser hermes-gateway`. Do not fetch
private runtime logs/session transcripts into maintenance contexts.
