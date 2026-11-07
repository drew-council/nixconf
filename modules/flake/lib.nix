{ inputs, lib, ... }:
{
  options.my.liveLink = lib.mkOption {
    type = lib.types.functionTo (lib.types.functionTo lib.types.anything);
    readOnly = true;
    default =
      hmConfig: path:
      hmConfig.lib.file.mkOutOfStoreSymlink "${hmConfig.my.user.flakePath}/${lib.removePrefix "${toString inputs.self}/" (toString path)}";
    description = ''
      Links a repo file into the home directory through the live checkout, so
      edits apply without a rebuild. Call as `my.liveLink config ./file` with
      the Home Manager `config`.
    '';
  };
}
