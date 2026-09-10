#!/usr/bin/env nu

const REPO = "sheerhealth/sheer"
const REPO_DIR = "~/repos/sheer"
const REVIEW_TEAMS = [go-readability api-readability build-readability]
const JSON_FIELDS = "number,title,url,author,updatedAt"

def require_herdr [] {
  if (($env.HERDR_ENV? | default "0") != "1") {
    error make {msg: "reviewprs.nu must be run inside Herdr (HERDR_ENV=1)"}
  }
}

def open_prs []: list<any> -> nothing {
  # Open each PR in a new Herdr tab.
  $in | each {|pr|
    let tab = (herdr tab create --label $pr.title --no-focus | from json)
    let pane_id = $tab.result.root_pane.pane_id
    herdr pane run $pane_id $"tuicr pr ($pr.url)"
  }
}

# Open PRs awaiting review from one of my readability teams.
def prs [limit: int] {
  $REVIEW_TEAMS
  | par-each {|team|
    (
      gh pr list
      --repo $REPO
      --state open
      --limit $limit
      --search $"-author:@me team-review-requested:SheerHealth/($team)"
      --json $JSON_FIELDS
    )
    | from json
  }
  | flatten
  | uniq-by number
  | sort-by updatedAt --reverse
}

def main [--limit: int = 200] {
  require_herdr
  cd $REPO_DIR

  let candidates = (prs $limit)

  if ($candidates | is-empty) {
    print -e "no pull requests awaiting review"
    exit 1
  }

  (
    $candidates |
    # format for input display
    upsert "display" {|pr|
      $"@($pr.author.login | fill --alignment left --width 20)($pr.title)"
    } |
    # get user selection ("a" for all)
    input list --multi --display "display" | reverse | open_prs
  )
}

def normalize_pr_ref [raw: string] {
  let ref = ($raw | str replace --regex '#.*$' '' | str trim)

  if ($ref | is-empty) {
    return null
  }

  if ($ref =~ `^(www\.)?github\.com/`) {
    return $"https://($ref)"
  }

  $ref
}

def load_pr [ref: string] {
  let result = (^gh pr view $ref --repo $REPO --json $JSON_FIELDS | complete)

  if $result.exit_code == 0 {
    return {
      ok: true
      input: $ref
      pr: ($result.stdout | from json)
    }
  }

  {
    ok: false
    input: $ref
    error: ($result.stderr | str trim)
  }
}

# Paste a list of PR URLs or numbers into an editor and open them all.
def "main urls" [] {
  require_herdr
  cd $REPO_DIR

  let tempfile = (mktemp --suffix .txt)
  nvim $tempfile
  let refs = (
    open $tempfile
    | lines
    | each {|line| normalize_pr_ref $line }
    | where {|ref| $ref != null }
    | uniq
  )
  rm $tempfile

  if ($refs | is-empty) {
    print -e "no pull request urls entered"
    exit 1
  }

  let results = ($refs | par-each {|ref| load_pr $ref })
  let failures = ($results | where {|result| not $result.ok })
  let prs = ($results | where {|result| $result.ok } | get pr)

  if (not ($failures | is-empty)) {
    print -e "failed to load some pull requests:"
    $failures | each {|failure|
      print -e $"  ($failure.input): ($failure.error)"
    }
  }

  if ($prs | is-empty) {
    exit 1
  }

  $prs | open_prs
}
