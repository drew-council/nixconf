{ buildGo126Module, lib }:

buildGo126Module {
  pname = "archive";
  version = "0.1.0";

  src = ./.;
  vendorHash = "sha256-ORMtYXnVZfn8lX8MMVIR2gMingtxw3WnJM3Y1GimBeA=";

  meta = {
    description = "Compress and extract zip, tar.gz, and tar.zst archives";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "archive";
  };
}
