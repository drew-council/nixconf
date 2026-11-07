def main [
  app_name: string
  settings_option: string
  source_config: path
  executable: path
  setsid: path
  expected_failure: string
  ...arguments: string
] {
  let validation_dir = (
    $nu.temp-dir
    | path join $"lazy-app-config-validation-(random chars --length 16)"
  )
  let config_dir = $validation_dir | path join "config"
  let candidate_config = $config_dir | path join "config.yml"

  mkdir $validation_dir

  let validation = try {
    ["config" "home" "xdg-config" "state" "cache"]
    | each {|directory| mkdir ($validation_dir | path join $directory) }
    | ignore
    cp $source_config $candidate_config

    let app_result = with-env {
      HOME: ($validation_dir | path join "home")
      XDG_CONFIG_HOME: ($validation_dir | path join "xdg-config")
      XDG_STATE_HOME: ($validation_dir | path join "state")
      XDG_CACHE_HOME: ($validation_dir | path join "cache")
      CONFIG_DIR: $config_dir
      LG_CONFIG_FILE: $candidate_config
      DOCKER_HOST: $"unix://($validation_dir | path join 'missing-docker.sock')"
      TERM: "dumb"
    } {
      hide-env --ignore-errors GIT_DIR GIT_WORK_TREE
      do { ^$setsid --fork --wait $executable ...$arguments } | complete
    }

    let configured = open $source_config
    let loaded = open $candidate_config

    if $configured != $loaded {
      {
        ok: false
        message: (
          [
            $"($app_name)'s generated config requires migration by ($executable)."
            $"Update ($settings_option) before activating this generation."
            ""
            "Configured YAML:"
            ($configured | to yaml)
            "Migrated YAML:"
            ($loaded | to yaml)
          ]
          | str join "\n"
        )
      }
    } else if (
      $app_result.exit_code == 0
      or not ($app_result.stderr | str contains $expected_failure)
    ) {
      {
        ok: false
        message: (
          [
            $"($app_name) rejected its generated config:"
            $app_result.stdout
            $app_result.stderr
          ]
          | compact
          | str join "\n"
          | str trim
        )
      }
    } else {
      {ok: true message: ""}
    }
  } catch {|error|
    {
      ok: false
      message: $"Could not validate ($app_name)'s generated config: ($error.msg)"
    }
  }

  do --ignore-errors { rm --recursive --force $validation_dir }

  if not $validation.ok {
    print --stderr $validation.message
    exit 1
  }
}
