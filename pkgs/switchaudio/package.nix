{
  makeWrapper,
  symlinkJoin,
  writeTextDir,
  writers,
}:
let
  sharedPythonLib = writeTextDir "lib/nixconf_audio/__init__.py" (
    builtins.readFile ./nixconf_audio/__init__.py
  );
  rawScript = writers.writePython3Bin "switchaudio" {
    libraries = [ ];
  } (builtins.readFile ./main.py);
in
symlinkJoin {
  name = "switchaudio";
  paths = [
    rawScript
    sharedPythonLib
  ];
  nativeBuildInputs = [ makeWrapper ];
  meta.mainProgram = "switchaudio";
  postBuild = ''
    wrapProgram "$out/bin/switchaudio" \
      --prefix PYTHONPATH : "$out/lib"
  '';
}
