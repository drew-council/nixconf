# XPS Hermes maintenance

- XPS is dedicated to Hermes. Full access to this machine is intentional; a
  separate Linux user is not required as a security boundary.
- Hermes's 1Password service account is read-only and scoped solely to the
  **Agent Access** vault. Never broaden its permissions or request the user's
  1Password account password.
- Authenticated application page contents, especially medical data, belong only
  in Hermes's context under the user's chosen ZDR provider policy. Do not fetch
  private browser snapshots, screenshots, page text, records, or Hermes private
  session transcripts into maintenance-assistant contexts. External validation
  should use service health and generic login/verification status signals only.
- Batch interactive local `op` operations into one Bash invocation when possible
  to minimize desktop authentication prompts. Scoped service-account reads on
  XPS do not require interactive authentication.
