#!/usr/bin/env nu

# Start Canopy locally inside Herdr: a new tab in the active sheer workspace
# with the local API (cmd/local) on the left and `pnpm run dev` on the right,
# both running from that workspace's checkout.
#
# The API talks to real Gemini on Vertex, so it needs Application Default
# Credentials; pass --fake-gemini to use the canned fake client instead.
#
# By default the API runs on empty emulators. Pass --staging to copy payers
# from staging Spanner, and name rows as TableName:ID to pull them too:
#
#   canopy-local --staging Account:<id> SheerCase:<id>

def fail [msg: string] {
  error make --unspanned {msg: $msg}
}

def herdr-json [args: list<string>] {
  let result = (^herdr ...$args | complete)

  if ($result.exit_code != 0) {
    fail $"`herdr ($args | str join ' ')` failed:\n($result.stderr | str trim)"
  }

  $result.stdout | from json | get result
}

# The workspace this pane lives in, or the focused one when run outside a pane.
def active-workspace [] {
  let workspaces = (herdr-json [workspace list] | get workspaces)

  let workspace = if ("HERDR_WORKSPACE_ID" in $env) {
    $workspaces | where workspace_id == $env.HERDR_WORKSPACE_ID | first
  } else {
    $workspaces | where focused == true | first
  }

  if ($workspace | get --optional worktree.repo_name) != "sheer" {
    fail $"workspace '($workspace.label)' is not a sheer checkout"
  }

  $workspace
}

def ensure-adc [reason: string] {
  let result = (^gcloud auth application-default print-access-token | complete)

  if ($result.exit_code != 0) {
    fail $"($reason) needs Application Default Credentials; run `gcloud auth application-default login`"
  }
}

def main [
  ...test_ids: string # with --staging, rows to seed from staging as TableName:ID
  --staging # seed payers (and any named rows) from staging
  --proxies # with --staging, also seed proxies
  --fake-gemini # use the fake Gemini client instead of real Gemini
  --focus # switch to the new tab instead of leaving it in the background
] {
  if ($env.HERDR_ENV? | default "") != "1" {
    fail "not running inside Herdr"
  }

  if (not $staging) and ($proxies or ($test_ids | is-not-empty)) {
    fail "--proxies and TableName:ID rows only apply with --staging"
  }

  let malformed = ($test_ids | where {|id| $id !~ '^[A-Za-z][A-Za-z0-9]*:.+$' })
  if ($malformed | is-not-empty) {
    fail $"rows must be TableName:ID, got: ($malformed | str join ', ')"
  }

  let workspace = (active-workspace)
  let repo = $workspace.worktree.checkout_path
  let canopy = ($repo | path join projects canopy)

  if $staging {
    ensure-adc "seeding from staging"
  } else if not $fake_gemini {
    ensure-adc "real Gemini"
  }

  let seed_args = if $staging {
    (
      ["--seed_payers"]
      | append (if $proxies { ["--seed_proxies"] } else { [] })
      | append ($test_ids | each {|id| $"--test_ids ($id)" })
    )
  } else {
    []
  }

  let api_args = (
    [$"--fake-gemini-client=($fake_gemini)"]
    | append $seed_args
  )

  let api_cmd = (
    [$"bazel run --run_under \"cd ($repo) && exec\" //cmd/local --"]
    | append $api_args
    | str join " "
  )

  let focus_flag = if $focus { "--focus" } else { "--no-focus" }

  let tab = (
    herdr-json [
      tab
      create
      --workspace
      $workspace.workspace_id
      --cwd
      $repo
      --label
      "canopy local"
      $focus_flag
    ]
  )
  let api_pane = $tab.root_pane.pane_id

  let canopy_pane = (
    herdr-json [
      pane
      split
      $api_pane
      --direction
      right
      --no-focus
      --cwd
      $canopy
    ]
  ).pane.pane_id

  ^herdr pane rename $api_pane "api (cmd/local)" | ignore
  ^herdr pane rename $canopy_pane "canopy (pnpm dev)" | ignore

  ^herdr pane run $api_pane $api_cmd | ignore
  ^herdr pane run $canopy_pane "pnpm run dev" | ignore

  print $"tab ($tab.tab.tab_id) in workspace '($workspace.label)' \(($repo)\)"
  print $"  api    ($api_pane): ($api_cmd)"
  print $"  canopy ($canopy_pane): pnpm run dev -> http://localhost:4200"
  print $"  gemini: (if $fake_gemini { 'fake client' } else { 'real (Vertex)' })"
  if $staging {
    print "  seeding from staging; the API is up once its pane logs 'starting service'"
  }
}
