#!/usr/bin/env nu

let releases = (
  gh release list --json createdAt,isDraft,isLatest,name,publishedAt,tagName
  | from json
)

def get-tag [] {
  let parsed_latest = (
    $releases
    | where "isLatest"
    | first
    | get tagName
    | parse "v{date}.{version}"
    | first
  )

  let latest = {
    date: ($parsed_latest.date)
    version: ($parsed_latest.version | into int)
  }

  let today = (date now | format date "%Y-%m-%d")
  let new_version = if ($today == $latest.date) { $parsed_latest.vesrion + 1 } else { 0 }

  $"v($today).($new_version)"
}

get-tag | print

