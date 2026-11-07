from __future__ import annotations

import gzip
import io
import os
import shutil
import stat
import tarfile
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from enum import Enum
from pathlib import Path, PurePosixPath
from typing import IO, cast

import click
import zstandard
from tqdm import tqdm

CHUNK_SIZE = 1024 * 1024
ZIP_EXT = ".zip"
TAR_GZ_EXT = ".tar.gz"
TAR_ZST_EXT = ".tar.zst"
SUPPORTED_EXTENSIONS = (TAR_ZST_EXT, TAR_GZ_EXT, ZIP_EXT)


class ArchiveType(Enum):
    ZIP = (ZIP_EXT, "zip")
    TAR_GZ = (TAR_GZ_EXT, "tar.gz")
    TAR_ZST = (TAR_ZST_EXT, "tar.zst")

    def __init__(self, extension: str, label: str) -> None:
        self.extension = extension
        self.label = label

    @classmethod
    def from_path(cls, path: Path) -> ArchiveType:
        lower_name = path.name.lower()
        for archive_type in cls:
            if lower_name.endswith(archive_type.extension):
                return archive_type
        supported = ", ".join(SUPPORTED_EXTENSIONS)
        raise click.ClickException(
            f"unsupported archive extension for {path}: expected one of "
            f"{supported}"
        )

    @classmethod
    def from_extension_shorthand(cls, value: str) -> ArchiveType:
        for archive_type in cls:
            if value == archive_type.extension:
                return archive_type
        supported = ", ".join(SUPPORTED_EXTENSIONS)
        raise click.ClickException(
            f"unsupported archive extension shorthand {value!r}: expected "
            f"one of {supported}"
        )

    @classmethod
    def strip_archive_suffix(cls, filename: str) -> str:
        lower_name = filename.lower()
        for archive_type in cls:
            if lower_name.endswith(archive_type.extension):
                return filename[: -len(archive_type.extension)]
        supported = ", ".join(SUPPORTED_EXTENSIONS)
        raise click.ClickException(
            f"unsupported archive extension for {filename!r}: expected one "
            f"of {supported}"
        )


class EntryKind(Enum):
    DIRECTORY = "directory"
    FILE = "file"
    SYMLINK = "symlink"


@dataclass(frozen=True, slots=True)
class ArchiveEntry:
    source_path: Path
    relative_path: PurePosixPath
    kind: EntryKind
    mode: int
    size: int
    mtime: int
    link_target: str | None = None

    @property
    def archive_name(self) -> str:
        relative = self.relative_path.as_posix()
        if self.kind is EntryKind.DIRECTORY:
            return f"{relative}/"
        return relative


@dataclass(frozen=True, slots=True)
class CompressionRequest:
    source_directory: Path
    archive_path: Path
    archive_type: ArchiveType
    force: bool


@dataclass(frozen=True, slots=True)
class ExtractionRequest:
    archive_path: Path
    output_directory: Path
    archive_type: ArchiveType
    force: bool


class CountingReader(io.RawIOBase):
    def __init__(
        self,
        fileobj: IO[bytes],
        progress: tqdm,
        label: str | None = None,
    ) -> None:
        self._fileobj = fileobj
        self._progress = progress
        self._label = label

    def read(self, size: int = -1) -> bytes:
        if self._label is not None:
            self._progress.set_postfix_str(self._label, refresh=False)
        data = self._fileobj.read(size)
        if data:
            self._progress.update(len(data))
        return data

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return hasattr(self._fileobj, "seekable") and self._fileobj.seekable()

    def tell(self) -> int:
        return self._fileobj.tell()

    def seek(self, offset: int, whence: int = 0) -> int:
        return self._fileobj.seek(offset, whence)

    def close(self) -> None:
        self._fileobj.close()

    def __getattr__(self, name: str) -> object:
        return getattr(self._fileobj, name)


def default_worker_count() -> int:
    cpu_count = os.cpu_count() or 1
    return max(1, min(cpu_count, 8))


def create_progress(total: int, description: str) -> tqdm:
    return tqdm(
        total=total,
        desc=description,
        unit="B",
        unit_scale=True,
        dynamic_ncols=True,
        disable=not os.isatty(2),
    )


def clamp_zip_datetime(timestamp: int) -> tuple[int, int, int, int, int, int]:
    local_time = time.localtime(timestamp)
    year = max(1980, local_time.tm_year)
    return (
        year,
        local_time.tm_mon,
        local_time.tm_mday,
        local_time.tm_hour,
        local_time.tm_min,
        local_time.tm_sec,
    )


def is_supported_extension_shorthand(value: str) -> bool:
    return value in SUPPORTED_EXTENSIONS


def normalize_archive_member(name: str) -> PurePosixPath:
    if name == "":
        raise click.ClickException("archive member name cannot be empty")

    pure_path = PurePosixPath(name)
    if pure_path.is_absolute():
        raise click.ClickException(
            f"archive member {name!r} must not use an absolute path"
        )

    normalized_parts = [
        part for part in pure_path.parts if part not in ("", ".")
    ]
    if any(part == ".." for part in normalized_parts):
        raise click.ClickException(
            f"archive member {name!r} must not escape the output directory"
        )
    if not normalized_parts:
        raise click.ClickException(
            f"archive member {name!r} must not resolve to the archive root"
        )
    return PurePosixPath(*normalized_parts)


def resolve_member_destination(output_directory: Path, name: str) -> Path:
    member_path = normalize_archive_member(name)
    return output_directory.joinpath(*member_path.parts)


def ensure_real_directory(path: Path, output_root: Path) -> None:
    current = output_root
    relative = path.relative_to(output_root)
    for part in relative.parts:
        current = current / part
        if current.exists():
            if current.is_symlink() or not current.is_dir():
                raise click.ClickException(
                    f"refusing to write through non-directory path {current}"
                )
            continue
        current.mkdir()


def validate_link_target(
    output_root: Path, link_path: Path, target: str
) -> None:
    target_path = Path(target)
    if target_path.is_absolute():
        raise click.ClickException(
            f"refusing to create absolute symlink target {target!r}"
        )

    resolved_target = (link_path.parent / target_path).resolve(strict=False)
    try:
        resolved_target.relative_to(output_root.resolve())
    except ValueError as error:
        raise click.ClickException(
            f"symlink target {target!r} escapes {output_root}"
        ) from error


def remove_existing_path(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
        return
    path.unlink()


def ensure_output_target(path: Path, *, force: bool, kind_label: str) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if not force:
        raise click.ClickException(f"{kind_label} already exists: {path}")
    remove_existing_path(path)


def basename_for_directory(path: Path) -> str:
    return path.resolve().name


def style_path(path: Path) -> str:
    return click.style(path.as_posix(), fg="cyan")


def resolve_compression_request(
    directory_name: str,
    archive_file: str | None,
    force: bool,
) -> CompressionRequest:
    source_directory = Path(directory_name).expanduser()
    if not source_directory.exists():
        raise click.ClickException(
            f"directory does not exist: {source_directory}"
        )
    if not source_directory.is_dir():
        raise click.ClickException(
            f"source path is not a directory: {source_directory}"
        )

    directory_basename = basename_for_directory(source_directory)
    if archive_file is None:
        archive_path = Path.cwd() / f"{directory_basename}{TAR_ZST_EXT}"
    elif is_supported_extension_shorthand(archive_file):
        archive_type = ArchiveType.from_extension_shorthand(archive_file)
        archive_path = (
            Path.cwd() / f"{directory_basename}{archive_type.extension}"
        )
    else:
        archive_path = Path(archive_file).expanduser()

    archive_type = ArchiveType.from_path(archive_path)
    archive_path = archive_path.resolve(strict=False)
    ensure_output_target(archive_path, force=force, kind_label="archive")

    click.echo(
        f"Compressing {style_path(source_directory)} to {style_path(archive_path)}"
    )

    return CompressionRequest(
        source_directory=source_directory.resolve(),
        archive_path=archive_path,
        archive_type=archive_type,
        force=force,
    )


def resolve_extraction_request(
    archive_file: str,
    output_directory_name: str | None,
    force: bool,
) -> ExtractionRequest:
    archive_path = Path(archive_file).expanduser()
    if not archive_path.exists():
        raise click.ClickException(f"archive does not exist: {archive_path}")
    if not archive_path.is_file():
        raise click.ClickException(
            f"archive path is not a file: {archive_path}"
        )

    archive_path = archive_path.resolve()
    archive_type = ArchiveType.from_path(archive_path)

    if output_directory_name is None:
        stripped_name = ArchiveType.strip_archive_suffix(archive_path.name)
        if stripped_name == "":
            raise click.ClickException(
                f"unable to infer output directory from {archive_path.name!r}"
            )
        output_directory = Path.cwd() / stripped_name
    else:
        output_directory = Path(output_directory_name).expanduser()

    output_directory = output_directory.resolve(strict=False)
    ensure_output_target(
        output_directory, force=force, kind_label="output directory"
    )

    click.echo(
        f"Extracting {style_path(archive_path)} to {style_path(output_directory)}"
    )

    return ExtractionRequest(
        archive_path=archive_path,
        output_directory=output_directory,
        archive_type=archive_type,
        force=force,
    )


def list_candidate_paths(source_directory: Path) -> list[Path]:
    candidates: list[Path] = []

    def visit(path: Path) -> None:
        for child in sorted(path.iterdir(), key=lambda entry: entry.name):
            candidates.append(child)
            if child.is_dir() and not child.is_symlink():
                visit(child)

    visit(source_directory)
    return candidates


def build_archive_entry(source_directory: Path, path: Path) -> ArchiveEntry:
    stat_result = path.lstat()
    relative_path = PurePosixPath(
        path.relative_to(source_directory).as_posix()
    )

    if stat.S_ISDIR(stat_result.st_mode):
        return ArchiveEntry(
            source_path=path,
            relative_path=relative_path,
            kind=EntryKind.DIRECTORY,
            mode=stat_result.st_mode,
            size=0,
            mtime=int(stat_result.st_mtime),
        )

    if stat.S_ISREG(stat_result.st_mode):
        return ArchiveEntry(
            source_path=path,
            relative_path=relative_path,
            kind=EntryKind.FILE,
            mode=stat_result.st_mode,
            size=stat_result.st_size,
            mtime=int(stat_result.st_mtime),
        )

    if stat.S_ISLNK(stat_result.st_mode):
        link_target = os.readlink(path)
        if Path(link_target).is_absolute():
            raise click.ClickException(
                f"refusing to archive absolute symlink target {link_target!r} "
                f"from {path}"
            )
        resolved_target = (path.parent / link_target).resolve(strict=False)
        if not resolved_target.exists():
            raise click.ClickException(
                f"refusing to archive broken symlink {path} -> {link_target}"
            )
        try:
            resolved_target.relative_to(source_directory.resolve())
        except ValueError as error:
            raise click.ClickException(
                f"refusing to archive symlink {path} -> {link_target} because "
                f"it escapes {source_directory}"
            ) from error
        return ArchiveEntry(
            source_path=path,
            relative_path=relative_path,
            kind=EntryKind.SYMLINK,
            mode=stat_result.st_mode,
            size=0,
            mtime=int(stat_result.st_mtime),
            link_target=link_target,
        )

    raise click.ClickException(f"unsupported file type for {path}")


def build_archive_manifest(
    source_directory: Path,
) -> tuple[list[ArchiveEntry], int]:
    candidate_paths = list_candidate_paths(source_directory)
    if not candidate_paths:
        return [], 0

    with ThreadPoolExecutor(max_workers=default_worker_count()) as executor:
        entries = list(
            executor.map(
                lambda path: build_archive_entry(source_directory, path),
                candidate_paths,
            )
        )

    entries.sort(key=lambda entry: entry.relative_path.as_posix())
    total_size = sum(
        entry.size for entry in entries if entry.kind is EntryKind.FILE
    )
    return entries, total_size


def copy_stream(
    source: IO[bytes], destination: IO[bytes], progress: tqdm, label: str
) -> None:
    progress.set_postfix_str(label, refresh=False)
    while True:
        chunk = source.read(CHUNK_SIZE)
        if not chunk:
            return
        destination.write(chunk)
        progress.update(len(chunk))


def create_zip_info(entry: ArchiveEntry) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(
        filename=entry.archive_name,
        date_time=clamp_zip_datetime(entry.mtime),
    )
    info.create_system = 3
    info.external_attr = (entry.mode & 0xFFFF) << 16
    if entry.kind is EntryKind.DIRECTORY:
        info.external_attr |= 0x10
        info.compress_type = zipfile.ZIP_STORED
    elif entry.kind is EntryKind.SYMLINK:
        info.compress_type = zipfile.ZIP_STORED
    else:
        info.compress_type = zipfile.ZIP_DEFLATED
        info.file_size = entry.size
    return info


def write_zip_archive(
    request: CompressionRequest, entries: list[ArchiveEntry]
) -> None:
    total_size = sum(
        entry.size for entry in entries if entry.kind is EntryKind.FILE
    )
    with (
        create_progress(total_size, "compress") as progress,
        zipfile.ZipFile(
            request.archive_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            allowZip64=True,
        ) as archive,
    ):
        for entry in entries:
            progress.set_postfix_str(entry.archive_name, refresh=False)
            info = create_zip_info(entry)
            if entry.kind is EntryKind.DIRECTORY:
                archive.writestr(info, b"")
                continue
            if entry.kind is EntryKind.SYMLINK:
                assert entry.link_target is not None
                archive.writestr(info, entry.link_target.encode("utf-8"))
                continue
            with (
                entry.source_path.open("rb") as source_file,
                archive.open(info, mode="w", force_zip64=True) as dest,
            ):
                copy_stream(
                    source_file,
                    dest,
                    progress,
                    entry.relative_path.as_posix(),
                )


def make_tar_info(entry: ArchiveEntry) -> tarfile.TarInfo:
    info = tarfile.TarInfo(entry.relative_path.as_posix())
    info.mode = stat.S_IMODE(entry.mode)
    info.mtime = entry.mtime
    if entry.kind is EntryKind.DIRECTORY:
        info.type = tarfile.DIRTYPE
        info.size = 0
    elif entry.kind is EntryKind.SYMLINK:
        info.type = tarfile.SYMTYPE
        info.size = 0
        assert entry.link_target is not None
        info.linkname = entry.link_target
    else:
        info.type = tarfile.REGTYPE
        info.size = entry.size
    return info


def add_entries_to_tar(
    archive: tarfile.TarFile, entries: list[ArchiveEntry], progress: tqdm
) -> None:
    for entry in entries:
        progress.set_postfix_str(entry.archive_name, refresh=False)
        info = make_tar_info(entry)
        if entry.kind is EntryKind.FILE:
            with (
                entry.source_path.open("rb") as source_file,
                CountingReader(
                    source_file,
                    progress,
                    entry.relative_path.as_posix(),
                ) as reader,
            ):
                archive.addfile(info, fileobj=reader)
            continue
        archive.addfile(info)


def write_tar_gz_archive(
    request: CompressionRequest, entries: list[ArchiveEntry]
) -> None:
    total_size = sum(
        entry.size for entry in entries if entry.kind is EntryKind.FILE
    )
    with (
        create_progress(total_size, "compress") as progress,
        request.archive_path.open("wb") as raw_file,
        gzip.GzipFile(fileobj=raw_file, mode="wb") as gzip_file,
        tarfile.open(fileobj=gzip_file, mode="w|") as archive,
    ):
        add_entries_to_tar(archive, entries, progress)


def write_tar_zst_archive(
    request: CompressionRequest, entries: list[ArchiveEntry]
) -> None:
    total_size = sum(
        entry.size for entry in entries if entry.kind is EntryKind.FILE
    )
    compressor = zstandard.ZstdCompressor(threads=default_worker_count())
    with (
        create_progress(total_size, "compress") as progress,
        request.archive_path.open("wb") as raw_file,
        compressor.stream_writer(raw_file) as zstd_writer,
        tarfile.open(fileobj=zstd_writer, mode="w|") as archive,
    ):
        add_entries_to_tar(archive, entries, progress)


def apply_permissions(path: Path, mode: int) -> None:
    if path.is_symlink():
        return
    path.chmod(stat.S_IMODE(mode))


def extract_zip_archive(request: ExtractionRequest) -> None:
    with zipfile.ZipFile(request.archive_path, mode="r") as archive:
        members = archive.infolist()
        total_size = sum(
            info.file_size
            for info in members
            if not info.is_dir()
            and not stat.S_ISLNK((info.external_attr >> 16) & 0o170000)
        )
        with create_progress(total_size, "extract") as progress:
            for info in members:
                destination = resolve_member_destination(
                    request.output_directory, info.filename
                )
                mode = (info.external_attr >> 16) & 0xFFFF
                if info.is_dir():
                    ensure_real_directory(
                        destination, request.output_directory
                    )
                    apply_permissions(destination, mode or 0o755)
                    continue

                ensure_real_directory(
                    destination.parent, request.output_directory
                )
                if stat.S_ISLNK(mode):
                    link_target = archive.read(info).decode("utf-8")
                    validate_link_target(
                        request.output_directory, destination, link_target
                    )
                    if destination.exists() or destination.is_symlink():
                        remove_existing_path(destination)
                    destination.symlink_to(link_target)
                    continue

                progress.set_postfix_str(info.filename, refresh=False)
                with (
                    archive.open(info, mode="r") as source_file,
                    destination.open("wb") as dest_file,
                ):
                    copy_stream(
                        source_file,
                        dest_file,
                        progress,
                        info.filename,
                    )
                if mode != 0:
                    apply_permissions(destination, mode)


def extract_tar_member(
    archive: tarfile.TarFile,
    member: tarfile.TarInfo,
    request: ExtractionRequest,
) -> None:
    destination = resolve_member_destination(
        request.output_directory, member.name
    )
    if member.isdir():
        ensure_real_directory(destination, request.output_directory)
        apply_permissions(destination, member.mode)
        return

    ensure_real_directory(destination.parent, request.output_directory)

    if member.issym():
        validate_link_target(
            request.output_directory, destination, member.linkname
        )
        if destination.exists() or destination.is_symlink():
            remove_existing_path(destination)
        destination.symlink_to(member.linkname)
        return

    if member.islnk():
        raise click.ClickException(
            f"hard link entries are not supported: {member.name}"
        )

    if not member.isfile():
        raise click.ClickException(
            f"unsupported tar member type for {member.name!r}"
        )

    extracted = archive.extractfile(member)
    if extracted is None:
        raise click.ClickException(
            f"unable to extract file data for {member.name}"
        )

    with extracted, destination.open("wb") as dest_file:
        while True:
            chunk = extracted.read(CHUNK_SIZE)
            if not chunk:
                break
            dest_file.write(chunk)
    apply_permissions(destination, member.mode)


def extract_tar_stream(
    archive: tarfile.TarFile,
    request: ExtractionRequest,
    progress: tqdm,
) -> None:
    while True:
        member = archive.next()
        if member is None:
            return
        progress.set_postfix_str(member.name, refresh=False)
        extract_tar_member(archive, member, request)


def extract_tar_gz_archive(request: ExtractionRequest) -> None:
    total_size = request.archive_path.stat().st_size
    with (
        create_progress(total_size, "extract") as progress,
        request.archive_path.open("rb") as raw_file,
        CountingReader(raw_file, progress) as reader,
        gzip.GzipFile(fileobj=reader, mode="rb") as gzip_file,
        tarfile.open(fileobj=gzip_file, mode="r|") as archive,
    ):
        extract_tar_stream(archive, request, progress)


def extract_tar_zst_archive(request: ExtractionRequest) -> None:
    total_size = request.archive_path.stat().st_size
    decompressor = zstandard.ZstdDecompressor()
    with (
        create_progress(total_size, "extract") as progress,
        request.archive_path.open("rb") as raw_file,
        CountingReader(raw_file, progress) as reader,
        decompressor.stream_reader(cast(IO[bytes], reader)) as zstd_reader,
        tarfile.open(fileobj=zstd_reader, mode="r|") as archive,
    ):
        extract_tar_stream(archive, request, progress)


def compress_archive(request: CompressionRequest) -> None:
    entries, _total_size = build_archive_manifest(request.source_directory)
    request.archive_path.parent.mkdir(parents=True, exist_ok=True)

    if request.archive_type is ArchiveType.ZIP:
        write_zip_archive(request, entries)
    elif request.archive_type is ArchiveType.TAR_GZ:
        write_tar_gz_archive(request, entries)
    else:
        write_tar_zst_archive(request, entries)

    archive_label = request.archive_type.label
    click.echo(f"created {archive_label} archive at {request.archive_path}")


def extract_archive(request: ExtractionRequest) -> None:
    request.output_directory.mkdir(parents=True, exist_ok=False)
    try:
        if request.archive_type is ArchiveType.ZIP:
            extract_zip_archive(request)
        elif request.archive_type is ArchiveType.TAR_GZ:
            extract_tar_gz_archive(request)
        else:
            extract_tar_zst_archive(request)
    except Exception:
        remove_existing_path(request.output_directory)
        raise

    click.echo(f"extracted archive into {request.output_directory}")


@click.group()
def cli() -> None:
    """Compress and extract archive files."""


@cli.command()
@click.option(
    "--force",
    is_flag=True,
    help="Replace the destination archive if it already exists.",
)
@click.argument("directory_name", type=str)
@click.argument("archive_file", required=False, type=str)
def compress(
    directory_name: str, archive_file: str | None, force: bool
) -> None:
    """Compress DIRECTORY_NAME into an archive."""

    request = resolve_compression_request(directory_name, archive_file, force)
    compress_archive(request)


@cli.command()
@click.option(
    "--force",
    is_flag=True,
    help="Replace the output directory if it already exists.",
)
@click.argument("archive_file", type=str)
@click.argument("output_directory_name", required=False, type=str)
def extract(
    archive_file: str,
    output_directory_name: str | None,
    force: bool,
) -> None:
    """Extract ARCHIVE_FILE into a directory."""

    request = resolve_extraction_request(
        archive_file, output_directory_name, force
    )
    extract_archive(request)


if __name__ == "__main__":
    cli()
