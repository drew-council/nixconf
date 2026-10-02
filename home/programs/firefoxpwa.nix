{
  lib,
  ...
}:
# Web apps run in a firefoxpwa (Gecko) runtime; links leaving an app's scope
# open in the default browser (Zen) via xdg-open.
let
  # ULIDs are arbitrary but must stay stable: they key the profile/site data
  # under ~/.local/share/firefoxpwa and the FFPWA-<ULID> window class.
  profileId = "01M3YHVYXDF48N92ED2WBVKGPV";

  sites = {
    "01M3YHVYXD0J4D8JYAMYMD2KKD" = {
      name = "Linear";
      url = "https://linear.app/";
    };
    "01M3YHVYXDQ4N0N8SY1SK8C5KG" = {
      name = "GitHub";
      url = "https://github.com/";
    };
    "01M3YHVYXDJAQ5ZNQY8Y3NR1DS" = {
      name = "Google Calendar";
      url = "https://calendar.google.com/";
    };
    "01M3YHVYXDMXDTX5WKAHYV6XXQ" = {
      name = "Google Chat";
      url = "https://chat.google.com/";
    };
  };

  # Hosts that stay inside the app window even though they are out of scope,
  # so sign-in redirects don't get bounced to Zen.
  allowedDomains = [
    "accounts.google.com"
    "accounts.youtube.com"
  ];

  prefs = {
    "firefoxpwa.openOutOfScopeInDefaultBrowser" = true;
    "firefoxpwa.allowedDomains" = lib.concatStringsSep "," allowedDomains;
    # force dark color scheme for web content
    "layout.css.prefers-color-scheme.content-override" = 0;
  };
in
{
  programs.firefoxpwa = {
    enable = true;
    settings.config.runtime_enable_wayland = true;
    profiles.${profileId} = {
      name = "Web Apps";
      sites = lib.mapAttrs (
        _: site:
        site
        // {
          # The HM module writes the manifest directly without fetching it, so
          # fields firefoxpwa normally derives (scope, display) must be set.
          settings.manifest = {
            scope = site.url;
            display = "standalone";
          };
        }
      ) sites;
    };
  };

  xdg.dataFile."firefoxpwa/profiles/${profileId}/user.js".text = lib.concatStrings (
    lib.mapAttrsToList (
      name: value: "user_pref(${builtins.toJSON name}, ${builtins.toJSON value});\n"
    ) prefs
  );
}
