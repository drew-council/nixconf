#!/usr/bin/env nu

let pr_query = '
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      id
      number
      url
      state
      merged
      mergedAt
      isDraft
      isMergeQueueEnabled
      isInMergeQueue
      mergeQueueEntry {
        id
        position
        state
        enqueuedAt
        estimatedTimeToMerge
      }
      autoMergeRequest {
        enabledAt
        mergeMethod
      }
      mergeStateStatus
      mergeable
      reviewDecision
      headRefOid
      statusCheckRollup {
        state
      }
      timelineItems(
        last: 10
        itemTypes: [
          ADDED_TO_MERGE_QUEUE_EVENT
          REMOVED_FROM_MERGE_QUEUE_EVENT
          MERGED_EVENT
          AUTO_MERGE_ENABLED_EVENT
          HEAD_REF_FORCE_PUSHED_EVENT
        ]
      ) {
        nodes {
          __typename
          ... on AddedToMergeQueueEvent {
            createdAt
          }
          ... on RemovedFromMergeQueueEvent {
            createdAt
            reason
          }
          ... on MergedEvent {
            createdAt
          }
          ... on AutoMergeEnabledEvent {
            createdAt
          }
          ... on HeadRefForcePushedEvent {
            createdAt
          }
        }
      }
    }
  }
}'

def fail [code: string msg: string] {
  error make {
    msg: $msg
    code: $code
  }
}

def print-progress [message: string --stderr] {
  let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")
  let line = $"[($timestamp)] ($message)"

  if $stderr {
    print --stderr $line
  } else {
    print $line
  }
}

def sleep-seconds [seconds: int] {
  sleep ($"($seconds)sec" | into duration)
}

def command-error-message [prefix: string result: record] {
  [
    $prefix
    ($result.stderr | default "" | str trim)
    ($result.stdout | default "" | str trim)
  ]
  | where {|part| ($part | str length) > 0 }
  | str join "\n"
}

def parse-pr-url [pr_url: string] {
  let parsed = (
    $pr_url
    | parse -r 'https?://(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<number>[0-9]+)(?:[/?#].*)?$'
  )

  if ($parsed | is-empty) {
    fail "USAGE" $"PR URL must look like https://<host>/<owner>/<repo>/pull/<number>. Got: ($pr_url)"
  }

  let record = ($parsed | first)
  {
    host: $record.host
    owner: $record.owner
    repo: $record.repo
    number: ($record.number | into int)
    url: $pr_url
  }
}

def ensure-gh-ready [host: string] {
  if ((which gh) | is-empty) {
    fail "USAGE" "`gh` is required but was not found in PATH."
  }

  let auth = (^gh auth status --hostname $host | complete)
  if ($auth.exit_code != 0) {
    fail "USAGE" (command-error-message $"GitHub auth is not ready for host ($host)." $auth)
  }
}

def resolve-pr-url [pr_url?: string] {
  if ($pr_url != null) {
    return $pr_url
  }

  if ((which gh) | is-empty) {
    fail "USAGE" "`gh` is required but was not found in PATH."
  }

  let result = (^gh pr view --json url --jq .url | complete)
  let url = ($result.stdout | default "" | str trim)

  if ($result.exit_code != 0) or ($url | is-empty) {
    fail "USAGE" (command-error-message "No PR URL was provided, and no active PR was found for the current branch." $result)
  }

  $url
}

def fetch-pr-state [pr: record] {
  let result = (
    ^gh api graphql
    --hostname $pr.host
    -f $"query=($pr_query)"
    -F $"owner=($pr.owner)"
    -F $"repo=($pr.repo)"
    -F $"number=($pr.number)"
    | complete
  )

  let stdout = ($result.stdout | default "" | str trim)
  if ($stdout | is-empty) {
    fail "UNEXPECTED" (command-error-message "GitHub GraphQL returned no JSON response." $result)
  }

  let response = (
    try {
      $stdout | from json
    } catch {|err|
      fail "UNEXPECTED" (
        [
          "Failed to parse GitHub GraphQL JSON response."
          ($err.msg | default ($err | to json))
          $stdout
        ]
        | str join "\n"
      )
    }
  )

  let raw_pr = ($response.data.repository.pullRequest? | default null)

  if (("errors" in $response) and ($raw_pr == null)) {
    return null
  }

  if ("errors" in $response) {
    fail "UNEXPECTED" (
      [
        "GitHub GraphQL returned errors."
        ($response.errors | to json)
      ]
      | str join "\n"
    )
  }

  if ($raw_pr == null) {
    return null
  }

  let timeline = (
    $raw_pr.timelineItems.nodes
    | default []
    | each {|item|
      {
        type: ($item.__typename? | default "")
        createdAt: ($item.createdAt? | default null)
        reason: ($item.reason? | default null)
      }
    }
  )

  {
    id: $raw_pr.id
    number: $raw_pr.number
    url: $raw_pr.url
    state: $raw_pr.state
    merged: $raw_pr.merged
    mergedAt: ($raw_pr.mergedAt? | default null)
    isDraft: $raw_pr.isDraft
    isMergeQueueEnabled: $raw_pr.isMergeQueueEnabled
    isInMergeQueue: $raw_pr.isInMergeQueue
    mergeQueueEntry: ($raw_pr.mergeQueueEntry? | default null)
    autoMergeRequest: ($raw_pr.autoMergeRequest? | default null)
    mergeStateStatus: $raw_pr.mergeStateStatus
    mergeable: $raw_pr.mergeable
    reviewDecision: ($raw_pr.reviewDecision? | default null)
    headRefOid: $raw_pr.headRefOid
    statusCheckState: ($raw_pr.statusCheckRollup.state? | default null)
    timeline: $timeline
  }
}

def assert-initial-eligibility [state: any pr_url: string] {
  if ($state == null) {
    fail "INITIAL_INELIGIBLE" $"Could not find PR for URL: ($pr_url)"
  }

  if $state.merged {
    return
  }

  if ($state.state != "OPEN") {
    fail "INITIAL_INELIGIBLE" $"PR is not open: state=($state.state)"
  }

  if $state.isDraft {
    fail "INITIAL_INELIGIBLE" "PR is still a draft."
  }

  if (not $state.isMergeQueueEnabled) {
    fail "INITIAL_INELIGIBLE" "The PR base branch does not require a merge queue."
  }

  if ($state.mergeable == "CONFLICTING") {
    fail "INITIAL_INELIGIBLE" "PR has merge conflicts and cannot enter the merge queue."
  }
}

def enqueue-or-arm [pr: record failure_code: string] {
  let state = (fetch-pr-state $pr)

  if ($state == null) {
    fail $failure_code $"Could not load PR state for ($pr.url)"
  }

  if $state.merged {
    return $state
  }

  let merge_result = (^gh pr merge $pr.url --match-head-commit $state.headRefOid | complete)
  let refreshed = (fetch-pr-state $pr)

  if ($refreshed != null) and (
    $refreshed.merged
    or $refreshed.isInMergeQueue
    or ($refreshed.mergeQueueEntry != null)
    or ($refreshed.autoMergeRequest != null)
  ) {
    return $refreshed
  }

  if ($merge_result.exit_code != 0) {
    fail $failure_code (command-error-message $"Failed to arm or enqueue PR ($pr.url)." $merge_result)
  }

  if ($refreshed == null) {
    fail "UNEXPECTED" $"PR disappeared after merge-queue request: ($pr.url)"
  }

  $refreshed
}

def latest-queue-event [state: record] {
  let events = (
    $state.timeline
    | where {|event| ($event.createdAt != null) }
    | sort-by createdAt
  )

  if ($events | is-empty) {
    return null
  }

  $events | last
}

def is-retryable-removal-reason [reason: string] {
  let normalized = ($reason | str downcase)

  let manual_terms = [
    "user requesting a removal"
    "user requested"
    "manually removed"
    "removed via the api"
    "removed via api"
    "remove from queue"
  ]

  let policy_terms = [
    "branch protection failure"
    "branch protection"
  ]

  let conflict_terms = [
    "conflict"
    "merge conflict"
    "unmergeable"
  ]

  let retryable_terms = [
    "test failure"
    "failed"
    "status check"
    "merge group"
    "timed out"
    "timeout"
    "ci"
  ]

  if ($manual_terms | any {|term| $normalized | str contains $term }) {
    return "terminal-manual"
  }

  if ($policy_terms | any {|term| $normalized | str contains $term }) {
    return "terminal-policy"
  }

  if ($conflict_terms | any {|term| $normalized | str contains $term }) {
    return "terminal-conflict"
  }

  if ($retryable_terms | any {|term| $normalized | str contains $term }) {
    return "retryable-ci"
  }

  "terminal-unknown"
}

def main [
  pr_url?: string
  --poll-seconds: int = 30
  --retry-delay-seconds: int = 10
] {
  try {
    if ($poll_seconds < 1) {
      fail "USAGE" "--poll-seconds must be at least 1."
    }

    if ($retry_delay_seconds < 1) {
      fail "USAGE" "--retry-delay-seconds must be at least 1."
    }

    let resolved_pr_url = (resolve-pr-url $pr_url)
    let pr = (parse-pr-url $resolved_pr_url)
    ensure-gh-ready $pr.host

    mut state = (fetch-pr-state $pr)
    assert-initial-eligibility $state $pr.url

    if $state.merged {
      print-progress $"PR already merged: ($pr.url)"
      return
    }

    print-progress $"Requesting merge-queue handling for ($pr.url)"
    $state = (enqueue-or-arm $pr "INITIAL_INELIGIBLE")

    loop {
      if ($state == null) {
        fail "TERMINAL_INELIGIBLE" $"PR is no longer available: ($pr.url)"
      }

      if $state.merged {
        let merged_at = ($state.mergedAt | default "unknown time")
        print-progress $"PR merged successfully at ($merged_at)."
        return
      }

      if ($state.state != "OPEN") {
        fail "TERMINAL_INELIGIBLE" $"PR is no longer open: state=($state.state)"
      }

      if $state.isDraft {
        fail "TERMINAL_INELIGIBLE" "PR became a draft while waiting."
      }

      if (not $state.isMergeQueueEnabled) {
        fail "TERMINAL_INELIGIBLE" "Merge queue is no longer enabled for the PR base branch."
      }

      if ($state.mergeable == "CONFLICTING") {
        fail "TERMINAL_INELIGIBLE" "PR became conflicting while waiting in merge queue."
      }

      if $state.isInMergeQueue or ($state.mergeQueueEntry != null) {
        let queue_state = ($state.mergeQueueEntry.state? | default "QUEUED")
        let position = ($state.mergeQueueEntry.position? | default "?")
        let eta = ($state.mergeQueueEntry.estimatedTimeToMerge? | default null)
        let eta_suffix = if ($eta == null) {
          ""
        } else {
          $" eta=($eta)s"
        }

        print-progress $"In merge queue: position=($position) state=($queue_state)($eta_suffix)"
        sleep-seconds $poll_seconds
        $state = (fetch-pr-state $pr)
        continue
      }

      if ($state.autoMergeRequest != null) {
        let review = ($state.reviewDecision | default "UNKNOWN")
        let checks = ($state.statusCheckState | default "UNKNOWN")
        print-progress $"Auto-merge enabled; waiting for requirements. review=($review) checks=($checks) merge_state=($state.mergeStateStatus)"
        sleep-seconds $poll_seconds
        $state = (fetch-pr-state $pr)
        continue
      }

      let event = (latest-queue-event $state)
      if ($event != null) and ($event.type == "RemovedFromMergeQueueEvent") {
        let reason = ($event.reason | default "No removal reason provided by GitHub.")
        let classification = (is-retryable-removal-reason $reason)

        if ($classification == "retryable-ci") {
          print-progress $"Removed from merge queue: ($reason). Retrying in ($retry_delay_seconds)s."
          sleep-seconds $retry_delay_seconds
          $state = (enqueue-or-arm $pr "TERMINAL_INELIGIBLE")
          continue
        }

        fail "TERMINAL_INELIGIBLE" $"PR was removed from the merge queue and will not be retried: ($reason)"
      }

      if ($event != null) and ($event.type == "HeadRefForcePushedEvent") {
        print-progress "Head branch was force-pushed. Waiting for GitHub to update queue state."
        sleep-seconds $poll_seconds
        $state = (fetch-pr-state $pr)
        continue
      }

      let checks = ($state.statusCheckState | default "UNKNOWN")
      print-progress $"Waiting for merge-queue state to settle. merge_state=($state.mergeStateStatus) checks=($checks)"
      sleep-seconds $poll_seconds
      $state = (fetch-pr-state $pr)
    }
  } catch {|err|
    let payload = (
      try {
        $err.json | from json
      } catch {
        {
          code: "UNEXPECTED"
          msg: ($err.msg | default ($err | to json))
        }
      }
    )

    let code = ($payload.code | default "UNEXPECTED")
    let message = ($payload.msg | default "Unexpected failure.")

    print-progress $message --stderr

    if ($code == "USAGE") {
      exit 1
    }

    if ($code == "INITIAL_INELIGIBLE") {
      exit 2
    }

    if ($code == "TERMINAL_INELIGIBLE") {
      exit 3
    }

    exit 4
  }
}
