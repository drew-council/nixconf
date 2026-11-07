from __future__ import annotations

import importlib.util
import io
import shutil
import stat
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest
from click.testing import CliRunner

ROOT = Path(__file__).resolve().parents[1]


def load_archive_module():
    module_path = ROOT / "pkgs/archive/main.py"
    spec = importlib.util.spec_from_file_location("archive_main", module_path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load archive module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def archive_module():
    return load_archive_module()


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


def create_sample_tree(root: Path) -> Path:
    source = root / "sample"
    source.mkdir()
    (source / "nested").mkdir()
    (source / "nested" / "deep").mkdir()
    (source / "hello.txt").write_text("hello world\n", encoding="utf-8")
    script = source / "nested" / "run.sh"
    script.write_text("#!/bin/sh\necho hi\n", encoding="utf-8")
    script.chmod(0o755)
    (source / "nested" / "deep" / "note.txt").write_text(
        "deep file\n", encoding="utf-8"
    )
    (source / "empty").mkdir()
    (source / "link.txt").symlink_to("hello.txt")
    return source


def assert_extracted_tree(extracted: Path) -> None:
    assert (extracted / "hello.txt").read_text(encoding="utf-8") == (
        "hello world\n"
    )
    assert (extracted / "nested" / "deep" / "note.txt").read_text(
        encoding="utf-8"
    ) == "deep file\n"
    assert (extracted / "empty").is_dir()
    assert (extracted / "link.txt").is_symlink()
    assert os_readlink(extracted / "link.txt") == "hello.txt"
    assert (extracted / "nested" / "run.sh").stat().st_mode & stat.S_IXUSR
    assert not (extracted / "sample").exists()


def test_archive_type_helpers(archive_module) -> None:
    archive_type = archive_module.ArchiveType

    assert archive_type.from_path(Path("example.zip")) is archive_type.ZIP
    assert (
        archive_type.from_path(Path("example.tar.gz")) is archive_type.TAR_GZ
    )
    assert (
        archive_type.from_path(Path("example.tar.zst")) is archive_type.TAR_ZST
    )
    assert archive_type.strip_archive_suffix("example.tar.zst") == "example"
    assert (
        archive_type.from_extension_shorthand(".tar.gz") is archive_type.TAR_GZ
    )

    with pytest.raises(Exception, match="unsupported archive extension"):
        archive_type.from_path(Path("example.tar"))


def test_default_compress_target_uses_tar_zst(
    archive_module,
    tmp_path: Path,
) -> None:
    source = tmp_path / "sample"
    source.mkdir()

    request = archive_module.resolve_compression_request(
        str(source), None, False
    )

    assert request.archive_type == archive_module.ArchiveType.TAR_ZST
    assert request.archive_path.name == "sample.tar.zst"


def test_compress_extension_shorthand_resolves_from_directory_name(
    archive_module,
    tmp_path: Path,
) -> None:
    source = tmp_path / "sample"
    source.mkdir()

    request = archive_module.resolve_compression_request(
        str(source), ".zip", False
    )

    assert request.archive_type == archive_module.ArchiveType.ZIP
    assert request.archive_path.name == "sample.zip"


def test_extract_default_output_directory_is_inferred(
    archive_module,
    tmp_path: Path,
) -> None:
    archive = tmp_path / "example.tar.gz"
    archive.write_bytes(b"placeholder")

    request = archive_module.resolve_extraction_request(
        str(archive), None, False
    )

    assert request.output_directory.name == "example"


def test_round_trip_for_each_supported_format(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    formats = [
        archive_module.ArchiveType.ZIP,
        archive_module.ArchiveType.TAR_GZ,
        archive_module.ArchiveType.TAR_ZST,
    ]
    source = create_sample_tree(tmp_path)

    for archive_type in formats:
        archive_path = tmp_path / f"sample{archive_type.extension}"
        result = runner.invoke(
            archive_module.cli,
            ["compress", str(source), str(archive_path)],
        )
        assert result.exit_code == 0, result.output
        assert archive_path.exists()

        extract_root = tmp_path / f"extract-{archive_type.label}"
        result = runner.invoke(
            archive_module.cli,
            [
                "extract",
                str(archive_path),
                str(extract_root),
            ],
        )
        assert result.exit_code == 0, result.output
        assert_extracted_tree(extract_root)
        shutil.rmtree(extract_root)


def test_compress_fails_when_archive_exists_without_force(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    source = create_sample_tree(tmp_path)
    archive_path = tmp_path / "sample.zip"
    archive_path.write_bytes(b"existing")

    result = runner.invoke(
        archive_module.cli,
        ["compress", str(source), str(archive_path)],
    )

    assert result.exit_code != 0
    assert "archive already exists" in result.output


def test_compress_force_replaces_existing_archive(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    source = create_sample_tree(tmp_path)
    archive_path = tmp_path / "sample.zip"
    archive_path.write_bytes(b"existing")

    result = runner.invoke(
        archive_module.cli,
        ["compress", "--force", str(source), str(archive_path)],
    )

    assert result.exit_code == 0, result.output
    assert archive_path.stat().st_size > len(b"existing")


def test_extract_fails_when_output_directory_exists_without_force(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    source = create_sample_tree(tmp_path)
    archive_path = tmp_path / "sample.zip"
    compress_result = runner.invoke(
        archive_module.cli,
        ["compress", str(source), str(archive_path)],
    )
    assert compress_result.exit_code == 0, compress_result.output

    output_directory = tmp_path / "existing-output"
    output_directory.mkdir()
    result = runner.invoke(
        archive_module.cli,
        ["extract", str(archive_path), str(output_directory)],
    )

    assert result.exit_code != 0
    assert "output directory already exists" in result.output


def test_extract_force_replaces_existing_output_directory(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    source = create_sample_tree(tmp_path)
    archive_path = tmp_path / "sample.tar.zst"
    compress_result = runner.invoke(
        archive_module.cli,
        ["compress", str(source), str(archive_path)],
    )
    assert compress_result.exit_code == 0, compress_result.output

    output_directory = tmp_path / "restored"
    output_directory.mkdir()
    (output_directory / "stale.txt").write_text("stale\n", encoding="utf-8")

    result = runner.invoke(
        archive_module.cli,
        [
            "extract",
            "--force",
            str(archive_path),
            str(output_directory),
        ],
    )

    assert result.exit_code == 0, result.output
    assert not (output_directory / "stale.txt").exists()
    assert_extracted_tree(output_directory)


def test_extract_rejects_zip_path_traversal(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    archive_path = tmp_path / "unsafe.zip"
    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("../evil.txt", "bad")

    result = runner.invoke(
        archive_module.cli,
        ["extract", str(archive_path), str(tmp_path / "out")],
    )

    assert result.exit_code != 0
    assert "must not escape the output directory" in result.output


def test_extract_rejects_tar_path_traversal(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    archive_path = tmp_path / "unsafe.tar.gz"
    with tarfile.open(archive_path, "w:gz") as archive:
        data = b"bad"
        info = tarfile.TarInfo("../evil.txt")
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))

    result = runner.invoke(
        archive_module.cli,
        ["extract", str(archive_path), str(tmp_path / "out")],
    )

    assert result.exit_code != 0
    assert "must not escape the output directory" in result.output


def test_extract_rejects_unsafe_symlink_entries(
    archive_module,
    runner: CliRunner,
    tmp_path: Path,
) -> None:
    archive_path = tmp_path / "unsafe.tar.zst"
    writer = io.BytesIO()
    compressor = archive_module.zstandard.ZstdCompressor()
    with (
        compressor.stream_writer(writer, closefd=False) as compressed,
        tarfile.open(fileobj=compressed, mode="w|") as archive,
    ):
        info = tarfile.TarInfo("link.txt")
        info.type = tarfile.SYMTYPE
        info.linkname = "../escape.txt"
        archive.addfile(info)
    archive_path.write_bytes(writer.getvalue())

    result = runner.invoke(
        archive_module.cli,
        ["extract", str(archive_path), str(tmp_path / "out")],
    )

    assert result.exit_code != 0
    assert "symlink target" in result.output


def test_help_lists_subcommands(
    archive_module,
    runner: CliRunner,
) -> None:
    result = runner.invoke(archive_module.cli, ["--help"])

    assert result.exit_code == 0, result.output
    assert "compress" in result.output
    assert "extract" in result.output


def os_readlink(path: Path) -> str:
    return str(path.readlink())
