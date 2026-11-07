#!/usr/bin/env nu

const THREADS_QUERY = '
query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          isResolved
          path
          line
          comments(first: 1) {
            nodes {
              author {
                login
              }
              body
              url
            }
          }
        }
      }
    }
  }
}'

const RESOLVE_MUTATION = '
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread {
      isResolved
    }
  }
}'

def gh_repo_args [repo?: string] {
  if $repo == null { [] } else { [--repo $repo] }
}

def load_pr [pr?: string repo?: string] {
  let args = ([$pr] | compact) ++ (gh_repo_args $repo)
  let result = (^gh pr view ...$args --json number,url,title,state,latestReviews | complete)
  if $result.exit_code != 0 {
    let target = if $pr == null { "the current branch" } else { $pr }
    error make {msg: $"could not load PR for ($target): ($result.stderr | str trim)"}
  }
  $result.stdout | from json
}

def parse_pr_url [url: string] {
  $url
  | parse --regex `https?://[^/]+/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<number>\d+)`
  | first
  | update number { into int }
}

# Approved when any reviewer's latest review is an approval. reviewDecision is
# not used: it reflects merge requirements and is empty when the base branch
# does not require reviews, e.g. a stacked PR.
def is_approved [pr: record] {
  $pr.latestReviews | any {|review| $review.state == "APPROVED" }
}

def unresolved_threads [pr: record] {
  let ref = (parse_pr_url $pr.url)
  (
    ^gh api graphql --paginate
    -f $"query=($THREADS_QUERY)"
    -F $"owner=($ref.owner)"
    -F $"repo=($ref.repo)"
    -F $"number=($ref.number)"
    --jq '.data.repository.pullRequest.reviewThreads.nodes[]'
  )
  | from json --objects
  | where {|thread| not $thread.isResolved }
}

def resolve_thread [thread_id: string] {
  ^gh api graphql -f $"query=($RESOLVE_MUTATION)" -F $"threadId=($thread_id)" | ignore
}

# Resolve unresolved review threads I started on an approved PR, without replying.
# Use --force to resolve on a PR that is not approved.
def main [
  pr?: string # PR number, URL, or branch (defaults to the PR for the current branch)
  --repo (-R): string # OWNER/REPO, when not run from inside the repo
  --dry-run (-n) # list the threads that would be resolved
  --force (-f) # resolve even when the PR is not approved
] {
  let pr = (load_pr $pr $repo)

  if $pr.state != "OPEN" {
    print -e $"PR #($pr.number) is ($pr.state | str lowercase), not open"
    exit 1
  }

  if not (is_approved $pr) {
    let msg = $"PR #($pr.number) is not approved"
    if not $force {
      print -e $"($msg); use --force to resolve anyway"
      exit 1
    }
    print -e $"warning: ($msg); resolving anyway due to --force"
  }

  let me = (^gh api user --jq .login | str trim)
  let threads = (
    unresolved_threads $pr
    | where {|thread| ($thread.comments.nodes | first | get author?.login?) == $me }
  )

  if ($threads | is-empty) {
    print $"no unresolved self-comments on PR #($pr.number)"
    return
  }

  print $"PR #($pr.number): ($pr.title)"
  for thread in $threads {
    let comment = ($thread.comments.nodes | first)
    let location = ([$thread.path $thread.line] | compact | str join ":")
    # skip blank lines and quoted lines such as the agent attribution line
    let summary = (
      $comment.body
      | lines
      | str trim
      | where {|line| $line != "" and not ($line | str starts-with ">") }
      | first
      | default ""
      | str substring 0..79
    )
    if $dry_run {
      print $"  would resolve ($location): ($summary)"
    } else {
      resolve_thread $thread.id
      print $"  resolved ($location): ($summary)"
    }
  }
}
