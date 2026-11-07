{
  kitty,
  writeShellScriptBin,
}:
writeShellScriptBin "icat" ''
  exec ${kitty.kitten}/bin/kitten icat "$@"
''
