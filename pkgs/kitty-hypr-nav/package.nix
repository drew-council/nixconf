{
  buildGo126Module,
  kitty,
  lib,
  makeWrapper,
}:
buildGo126Module {
  pname = "kitty-hypr-nav";
  version = "0.1.0";

  src = ./.;
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/kitty-hypr-nav" \
      --prefix PATH : "${lib.makeBinPath [ kitty ]}"
  '';

  meta = with lib; {
    description = "Kitty tab navigation helper with Hyprland edge fallback";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "kitty-hypr-nav";
  };
}
