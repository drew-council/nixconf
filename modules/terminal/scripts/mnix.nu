#!/usr/bin/env nu

let result = (
  manix "" | rg '^# ' | sed 's/^# \(.*\) (.*/\1/;s/ (.*//;s/^# //' | fzf --preview="manix '{}'" | complete
)

if ($result.stdout | is-empty) {
  print "No page selected."
} else {
  $result.stdout | str trim | manix $in
}
