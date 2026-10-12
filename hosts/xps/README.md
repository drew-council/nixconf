# XPS

Hermes runs on `192.168.1.145`. Closing the lid leaves the host running.

| Service | Endpoint |
| --- | --- |
| `hermes-dashboard` | <http://192.168.1.145:9119> |
| `hermes-gateway` | Messaging and scheduled jobs |
| `hermes-browser` | CDP `127.0.0.1:9223` |
| `hermes-sms-receiver` | Health: <http://192.168.1.145:8788/health> |
| `peanut-map` | <https://peanutmap.home.drewcouncil.com> (direct: <http://192.168.1.145:8765>) |

Dashboard login: `drew`; password in 1Password's **Hermes XPS** item.
Dashboard, SMS and peanut map access are restricted to `192.168.1.0/24`.

## Peanut map

`peanut-map` serves a read-only map from `~/personal/placeparse` using that
checkout's `.venv`; it cannot write to `/home`. Replies show up without a
restart. After pulling changes there, run `uv sync`, rebuild the frontend with
`npm --prefix peanut_map/frontend ci` and `npm --prefix peanut_map/frontend run build`,
then `sudo systemctl restart peanut-map`. tungsten's nginx-proxy-manager
provides the HTTPS name.

## Runtime files

- `~/.hermes/config.yaml`: writable Hermes-owned settings; not managed by Nix.
- `~/.hermes/.env`: provider/dashboard credentials and the Agent Access token.
  Keep this file mode 600 and its directory mode 700; never commit secrets.
- `~/.hermes/sms/webhook_receiver.py`: private MacroDroid receiver implementation.
- `~/.hermes/browser-agent-access/`: persistent browser profile; treat cookies as credentials.

Browser logins use a read-only 1Password service account scoped to **Agent Access**.
Use `/run/current-system/sw/bin/hermes-op` as the vault CLI in runtime settings.
The frontend patch in `patches/` supplies dashboard verification-code prompts
and includes regression tests.

## Git and deployment

GitHub uses `~/.ssh/hermes-github-ed25519` (mode 600), registered to `drew-council`.
Signing is disabled; commits default to **Hermes Agent** and the account's noreply email.
Keep the private key outside Git/Nix; revoke its GitHub registration if compromised.

After publishing changes, run `git pull --ff-only` and `nh os switch` in XPS's
`~/nixconf` checkout. Nix owns the services; do not install another Hermes gateway.
Check status with `systemctl is-active hermes-dashboard hermes-gateway hermes-browser hermes-sms-receiver peanut-map`.
