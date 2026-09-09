#!/usr/bin/env nu

# list make targets by scanning the Makefile for `target:` lines, the same
# way nu_scripts' make completion does; `## description` comments are shown
def make-targets []: nothing -> table<name: string, description: string> {
  open Makefile
  | lines
  | parse --regex '^(?<name>[\w.-]+)\s*:(?!=)(?<rest>.*)$'
  | where {|t| not ($t.name | str starts-with ".") }
  | each {|t|
    let desc = ($t.rest | parse --regex '##\s*(?<d>.*)$' | get -o 0.d | default "")
    {name: $t.name description: $desc}
  }
  | uniq-by name
}

# flatten mask's --introspect json into "sub command" paths with descriptions
def mask-commands []: nothing -> table<name: string, description: string> {
  def walk [commands: list prefix: string] {
    $commands
    | each {|cmd|
      let name = (if $prefix == "" { $cmd.name } else { $"($prefix) ($cmd.name)" })
      let args = (
        ($cmd.required_args | each {|a| $"<($a.name)>" })
        ++ ($cmd.optional_args | each {|a| $"[($a.name)]" })
        | str join " "
      )
      let self = (
        if $cmd.script == null {
          []
        } else {
          [{name: $name description: ($cmd.description | default "") args: $args}]
        }
      )
      $self ++ (walk $cmd.subcommands $name)
    }
    | flatten
  }

  walk (^mask --introspect | from json | get commands) ""
  | each {|c|
    let desc = (if $c.args == "" { $c.description } else { $"($c.description) ($c.args)" | str trim })
    {name: $c.name description: $desc}
  }
}

# pick one entry with fzf, showing descriptions on the right; returns the name
def pick [entries: table<name: string, description: string> tool: string]: nothing -> string {
  if ($entries | is-empty) {
    print $"no ($tool) targets found"
    exit 1
  }
  let width = ($entries | get name | each { str length } | math max)
  let selected = (
    $entries
    | each {|e| $"($e.name | fill --width $width)\t($e.description)" }
    | str join "\n"
    | ^fzf --prompt $"($tool)> " --delimiter "\t" --nth 1 --accept-nth 1
    | complete
  )
  if $selected.exit_code != 0 {
    exit $selected.exit_code
  }
  $selected.stdout | str trim
}

# run `make` or `mask` depending on which file exists in the cwd
# with no args, choose a target interactively with fzf
def main [...args: string] {
  let has_makefile = ("Makefile" | path exists)
  let has_maskfile = ("maskfile.md" | path exists)

  if $has_makefile and $has_maskfile {
    print "both Makefile and maskfile.md exist, defaulting to make"
  }

  if $has_makefile {
    if ($args | is-empty) {
      let target = (pick (make-targets) "make")
      ^make $target
    } else {
      ^make ...$args
    }
  } else if $has_maskfile {
    if ($args | is-empty) {
      let target = (pick (mask-commands) "mask")
      ^mask ...($target | split row " ")
    } else {
      ^mask ...$args
    }
  } else {
    print "no Makefile or maskfile.md in current directory"
    exit 1
  }
}
