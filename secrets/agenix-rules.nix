# Recipients for each agenix secret.
# The keys are the per-machine `~/.ssh/id_ed25519_git` public keys
# (modules/terminal/git.nix); print one with `cat ~/.ssh/id_ed25519_git.pub`.
# A host MUST be listed for every secret its configuration declares,
# or its agenix user service fails.
# After changing a recipient list, run `agenix -r` in this directory
# on a machine that can already decrypt, then commit the re-encrypted files.
let
  igneous = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEDHqOXNAQurrWBQG80oOwYmTc6eSmfSE2FLStraFw4";
  macos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGsgeyPDvT0rQurNbO2cGmr9ayITEWzOAt9rwLA48wzL";
  theseus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1VtwhTILKCntPpjcOsJxMXrOdD7baX3fICtbNYT9G0";

in
{
  # Hosts with `my.nixCache.push`.
  "niks3-token.age".publicKeys = [ igneous ];
  # Hosts with the `voxtype` feature.
  "voxtype-openai.age".publicKeys = [
    igneous
    macos
    theseus
  ];
}
