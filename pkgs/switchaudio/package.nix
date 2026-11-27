{
  buildGo126Module,
  lib,
}:

# pactl, wpctl, and fuzzel come from the ambient PATH,
# so they match the running PipeWire and the user's fuzzel.
buildGo126Module {
  pname = "switchaudio";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  meta = {
    description = "Switch the default PipeWire sink by ALSA name or from a fuzzel picker";
    license = lib.licenses.mit;
    mainProgram = "switchaudio";
  };
}
