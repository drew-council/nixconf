---
name: hyprland-lua-config
description: Work on this repo's Hyprland Lua configuration. Use when editing modules/desktop-linux/hyprland Lua modules, generated Home Manager wiring for hypr/hyprland.lua, Hyprland Lua APIs, hl.config tables, binds, dispatchers, events, monitors, window rules, animations, or Lua config docs/stubs.
---

# Hyprland Lua Config

This repo configures Hyprland through Home Manager and Lua:

- Home Manager wiring: `modules/desktop-linux/hyprland/default.nix`
- Lua modules: `modules/desktop-linux/hyprland/src/*.lua`
- Generated runtime entrypoint: `$XDG_CONFIG_HOME/hypr/hyprland.lua`
- Generated Nix data module: `$XDG_CONFIG_HOME/hypr/nixconf/generated.lua`

The generated entrypoint extends `package.path`, clears cached modules, then
requires the `nixconf.*` modules in the order listed in
`modules/desktop-linux/hyprland/default.nix`.

## Documentation Snapshot

Before guessing Hyprland Lua API names, refresh or query the local
machine-readable snapshot:

```nu
.agents/skills/hyprland-lua-config/scripts/hyprland_lua_docs.nu
```

The helper reads `~/personal/Hyprland` by default. If that checkout is missing,
it clones `https://github.com/hyprwm/Hyprland.git` there. It does not fetch raw
documentation URLs.

Output:

- `references/hyprland-lua-docs.json`: deterministic JSON snapshot containing
  the Hyprland commit, parsed aliases from `meta/hl.meta.lua`, class fields,
  config value types, global `hl` function signatures, source hashes, and the
  example Lua config.

Useful queries:

```nu
open .agents/skills/hyprland-lua-config/references/hyprland-lua-docs.json | get aliases."HL.ConfigKey".values | where $it =~ '^general\.'
open .agents/skills/hyprland-lua-config/references/hyprland-lua-docs.json | get aliases."HL.EventName".values
open .agents/skills/hyprland-lua-config/references/hyprland-lua-docs.json | get globals | where name =~ '^hl\.dsp\.'
```

## Editing Rules

- Keep Lua config split into focused modules under `modules/desktop-linux/hyprland/src`.
- Put host/package/path data in `generatedLua` in `modules/desktop-linux/hyprland/default.nix`,
  then consume it from Lua with `require("nixconf.generated")`.
- Use Lua table syntax accepted by Hyprland 0.55+ (`hl.config({ ... })`,
  `hl.window_rule({ ... })`, `hl.on(...)`, `hl.dsp.*`), not old hyprlang
  syntax.
- Prefer checking `HL.ConfigKey`, `HL.EventName`, and `globals` in the JSON
  snapshot before inventing option, event, dispatcher, or helper names.
- If Nix files change, use the repo's Nix validation workflow. If only Lua files
  change, at minimum run a focused syntax check where practical.
