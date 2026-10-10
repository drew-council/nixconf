# Synthetic two-factor acceptance

`two-factor-dashboard.mjs` launches exactly one isolated Chromium instance and
an isolated native dashboard using the built package's own Python/Node/frontend.
It inherits no operator HOME, provider credentials, proxy, or vault variables.
The noncredential provider fixture only permits session initialization; no model
turn is submitted. The browser target is a loopback HTML one-time-code field.

The Python harness redirects only the browser-supervisor boundary to that
fixture's CDP target. Production `browser_vault_enter_code`, classifier,
inspection/fill JavaScript, rebound `gateway._wire_callbacks`, `server_requests`,
contract registry, dispatcher, session membership and transports remain real.
Profile-scoped dashboard PTYs spawn their native stdio gateway; a transient
`sitecustomize` installs the stimulus in that process, not a replacement gateway.
The test reads the mounted real xterm buffer through its React ref (the actual
canvas renderer has no DOM innerText), checks visible canvas geometry, and uses
normal browser keyboard input. No fake prompt UI or mock request contract.

Coverage:
- rendered masked prompt, empty Return stays open, synthetic value absent from
  terminal text, exact string-ID `{result:{value:string}}` reaches browser fill;
- explicit Esc returns `code_declined`, with no new fill;
- browser reload keeps the pending prompt and does not autoanswer on disposal;
- independent native `/api/ws` capability advertisement and session attachment,
  direct response, explicit cancellation, and `session.activate.open_requests`
  replay retaining the same string ID after socket replacement;
- neither synthetic code appears in Hermes persisted files or server diagnostics.

Run from the repository, with public Playwright installed **only in scratch**:

```sh
scratch=$(mktemp -d)
cd "$scratch"
npm install --ignore-scripts --no-audit --no-fund playwright
cd /home/drew/nixconf
package=$(nix build --no-link --print-out-paths --impure --expr '
  let f = builtins.getFlake (toString /home/drew/nixconf);
  in builtins.head (builtins.filter (p: (p.pname or "") == "hermes-agent")
    f.nixosConfigurations.xps.config.environment.systemPackages)')
CHROMIUM=$(command -v chromium) \
PLAYWRIGHT_MODULE="$scratch/node_modules/playwright/index.mjs" \
node hosts/xps/tests/two-factor-dashboard.mjs "$package"
nix build --no-link path:/home/drew/nixconf#nixosConfigurations.xps.config.system.build.toplevel
```

The harness deletes its temporary profile/home on exit and never saves browser
screenshots, raw response frames, or transcripts. Its diagnostic failure paths
are synthetic-only. It does not touch production port 9223, Android/emulators,
authenticated websites, system activation, or services on XPS.

The patch also adds source-named TUI regressions to
`createGatewayEventHandler.test.ts` and `useInputHandlers.test.ts`. In a scratch
copy of the pinned package source, apply the patch with `patch -p1`, install the
locked UI workspace with `npm ci --ignore-scripts --engine-strict=false --workspace ui-tui`,
then run:

```sh
npm run build:ink --workspace ui-tui
npm run test --workspace ui-tui -- \
  src/__tests__/createGatewayEventHandler.test.ts \
  src/__tests__/useInputHandlers.test.ts
```

These tests/builds do not establish production account login success. Service
activation and real-phone confirmation remain parent-owned follow-up.
