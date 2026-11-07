{ python3Packages, writers }:
writers.writePython3Bin "archive" {
  libraries = with python3Packages; [
    click
    tqdm
    zstandard
  ];
  doCheck = false;
} (builtins.readFile ./main.py)
