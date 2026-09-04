#!/usr/bin/env python3
"""Create and verify a history-free, reproducible CR6608 source kit."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import lzma
import os
import pathlib
import re
import signal
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence


IDENTITY_NAME = ".cr6608-source-identity"
PAYLOAD_NAME = ".cr6608-source-payload.tsv"
IDENTITY_SCHEMA = "cr6608-sanitized-source-identity-v3"
MANIFEST_HEADER = "kind\tmode\tsha256_or_target\tpath\n"
ALLOWED_IGNORED_PREFIXES = (
    ".mobile-layout/",
    ".router-mobile-ui/",
    "release-evidence/",
)
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
SAFE_VERSION = re.compile(r"v[0-9]+\Z")


class SourceKitError(RuntimeError):
    """A fail-closed source-kit validation or creation error."""


@dataclass(frozen=True)
class SourceIdentity:
    mode: str
    product_version: str
    build_epoch: str
    original_commit: str
    original_tree: str
    container_commit: str
    container_tree: str
    kit_base_commit: str
    auth_fix_commit: str
    payload_manifest_sha256: str


def isolated_git_env(source: Mapping[str, str] | None = None) -> dict[str, str]:
    """Return a Git environment isolated from caller-controlled object/config state."""
    env = dict(os.environ if source is None else source)
    for key in tuple(env):
        # Git has repository, namespace, object, ref, config, protocol, hook,
        # tracing, and future environment switches. An allowlist would become
        # unsafe as Git grows, so inherit no caller GIT_* value at all.
        if key.startswith("GIT_"):
            env.pop(key, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_SYSTEM"] = os.devnull
    env["GIT_ATTR_NOSYSTEM"] = "1"
    env["GIT_NO_REPLACE_OBJECTS"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["LC_ALL"] = "C"
    return env


def run(
    argv: Sequence[str],
    *,
    cwd: pathlib.Path | None = None,
    env: Mapping[str, str] | None = None,
    input_bytes: bytes | None = None,
    capture: bool = True,
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            list(argv),
            cwd=cwd,
            env=None if env is None else dict(env),
            input=input_bytes,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = ""
        if isinstance(exc, subprocess.CalledProcessError):
            stderr = (exc.stderr or b"").decode("utf-8", "replace").strip()
            if stderr:
                detail = f": {stderr}"
        raise SourceKitError(f"command failed: {' '.join(argv)}{detail}") from exc


def git(repo: pathlib.Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    return run(
        ("git", "-c", "core.autocrlf=false", "-C", str(repo), *args),
        env=isolated_git_env(),
        input_bytes=input_bytes,
    ).stdout


def decode_line(value: bytes, label: str) -> str:
    try:
        text = value.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SourceKitError(f"{label} is not UTF-8") from exc
    if "\n" in text or "\r" in text or "\t" in text:
        raise SourceKitError(f"{label} contains an unsupported control character")
    return text


def resolve_repo(path: str) -> pathlib.Path:
    repo = pathlib.Path(path).resolve(strict=True)
    if not repo.is_dir():
        raise SourceKitError(f"source repository is not a directory: {repo}")
    if git(repo, "rev-parse", "--is-inside-work-tree").strip() != b"true":
        raise SourceKitError(f"source path is not a Git work tree: {repo}")
    top = pathlib.Path(git(repo, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    if top != repo:
        raise SourceKitError(f"source path must be the Git work-tree root: {repo}")
    return repo


def require_hex40(value: str, label: str) -> None:
    if not HEX40.fullmatch(value):
        raise SourceKitError(f"{label} must be a lowercase 40-hex object id")


def require_hex64(value: str, label: str) -> None:
    if not HEX64.fullmatch(value):
        raise SourceKitError(f"{label} must be a lowercase 64-hex SHA-256")


def require_product_version(value: str) -> None:
    if not SAFE_VERSION.fullmatch(value):
        raise SourceKitError("product version must have canonical vNN form")


def require_build_epoch(value: int) -> None:
    if value < 1_577_836_800 or value > 2_145_916_800:
        raise SourceKitError("build epoch is outside the accepted range")


def require_clean_source(repo: pathlib.Path) -> None:
    status = git(repo, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        raise SourceKitError("source work tree has tracked or untracked changes")

    ignored = git(
        repo,
        "ls-files",
        "-z",
        "--others",
        "--ignored",
        "--exclude-standard",
    )
    rejected: list[str] = []
    for raw in ignored.split(b"\0"):
        if not raw:
            continue
        path = decode_line(raw, "ignored source path")
        allowed = path.startswith(ALLOWED_IGNORED_PREFIXES) or (
            "/" not in path and path.startswith("inspect-image.sh.pre-")
        )
        if not allowed:
            rejected.append(path)
    if rejected:
        rendered = ", ".join(rejected[:8])
        if len(rejected) > 8:
            rendered += f", ... ({len(rejected)} total)"
        raise SourceKitError(f"source contains rejected ignored files: {rendered}")


def ls_tree_entries(repo: pathlib.Path, commit: str) -> list[tuple[str, str, str, str]]:
    output = git(repo, "ls-tree", "-r", "-z", "--full-tree", commit)
    entries: list[tuple[str, str, str, str]] = []
    for record in output.split(b"\0"):
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b"\t", 1)
            raw_mode, raw_type, raw_oid = metadata.split(b" ", 2)
        except ValueError as exc:
            raise SourceKitError("Git tree emitted a malformed record") from exc
        path = decode_line(raw_path, "tracked source path")
        mode = raw_mode.decode("ascii", "strict")
        obj_type = raw_type.decode("ascii", "strict")
        oid = raw_oid.decode("ascii", "strict")
        if path.startswith("/") or path == ".." or path.startswith("../") or "/../" in path:
            raise SourceKitError(f"tracked source path is unsafe: {path}")
        if obj_type != "blob" or mode not in ("100644", "100755", "120000"):
            raise SourceKitError(f"unsupported tracked entry {mode} {obj_type}: {path}")
        require_hex40(oid, f"object id for {path}")
        entries.append((mode, obj_type, oid, path))
    if not entries:
        raise SourceKitError("source Git tree is empty")
    return entries


def normalize_checkout_modes(repo: pathlib.Path, commit: str) -> None:
    """Materialize the exact regular-file modes represented by the Git tree."""
    for mode, _obj_type, _oid, path in ls_tree_entries(repo, commit):
        materialized = repo / path
        if mode == "120000":
            if not materialized.is_symlink():
                raise SourceKitError(
                    f"verified checkout lost tracked symlink type: {path}"
                )
            continue
        if materialized.is_symlink() or not materialized.is_file():
            raise SourceKitError(
                f"verified checkout lost tracked regular-file type: {path}"
            )
        materialized.chmod(0o755 if mode == "100755" else 0o644)


def payload_manifest(repo: pathlib.Path, commit: str) -> bytes:
    lines = [MANIFEST_HEADER]
    seen: set[str] = set()
    for mode, _obj_type, oid, path in ls_tree_entries(repo, commit):
        if path in (IDENTITY_NAME, PAYLOAD_NAME):
            continue
        if path in seen:
            raise SourceKitError(f"duplicate tracked source path: {path}")
        seen.add(path)
        content = git(repo, "cat-file", "blob", oid)
        if mode == "120000":
            target = decode_line(content, f"symlink target for {path}")
            if not target:
                raise SourceKitError(f"symlink has an empty target: {path}")
            lines.append(f"source-symlink\t{mode}\t{target}\t{path}\n")
        else:
            digest = hashlib.sha256(content).hexdigest()
            lines.append(f"source-file\t{mode}\t{digest}\t{path}\n")
    return "".join(lines).encode("utf-8")


def tree_without_metadata(repo: pathlib.Path, commit: str) -> str:
    with tempfile.TemporaryDirectory(prefix="cr6608-source-index-") as temp:
        temp_root = pathlib.Path(temp)
        index_path = temp_root / "index"
        object_path = temp_root / "objects"
        object_path.mkdir(mode=0o700)
        repo_object_path = pathlib.Path(
            git(repo, "rev-parse", "--git-path", "objects").decode("utf-8").strip()
        )
        if not repo_object_path.is_absolute():
            repo_object_path = repo / repo_object_path
        repo_object_path = repo_object_path.resolve(strict=True)
        env = isolated_git_env()
        env["GIT_INDEX_FILE"] = str(index_path)
        # write-tree must not inject a metadata-free, unreachable tree into
        # the repository being verified. Read source objects as alternates and
        # direct every newly written object to this private temporary store.
        env["GIT_OBJECT_DIRECTORY"] = str(object_path)
        env["GIT_ALTERNATE_OBJECT_DIRECTORIES"] = str(repo_object_path)
        run(
            ("git", "-c", "core.autocrlf=false", "-C", str(repo), "read-tree", commit),
            env=env,
        )
        run(
            (
                "git",
                "-c",
                "core.autocrlf=false",
                "-C",
                str(repo),
                "update-index",
                "--force-remove",
                "--",
                IDENTITY_NAME,
                PAYLOAD_NAME,
            ),
            env=env,
        )
        tree = run(
            ("git", "-c", "core.autocrlf=false", "-C", str(repo), "write-tree"),
            env=env,
        ).stdout.decode("ascii").strip()
    require_hex40(tree, "payload tree")
    return tree


def parse_identity(content: bytes) -> dict[str, str]:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SourceKitError("source identity is not UTF-8") from exc
    expected_keys = (
        "schema",
        "product_version",
        "build_epoch",
        "original_commit",
        "original_tree",
        "kit_base_commit",
        "auth_fix_commit",
        "payload_manifest",
        "payload_manifest_sha256",
    )
    values: dict[str, str] = {}
    for line in text.splitlines():
        if not line or "=" not in line:
            raise SourceKitError("source identity has a malformed line")
        key, value = line.split("=", 1)
        if key not in expected_keys or key in values or not value:
            raise SourceKitError("source identity has an unknown, duplicate, or empty field")
        if any(char in value for char in "\t\r\n"):
            raise SourceKitError("source identity has an unsupported field value")
        values[key] = value
    if tuple(values) != expected_keys:
        raise SourceKitError("source identity fields are missing or out of canonical order")
    return values


def canonical_root_commit_object(tree: str, product_version: str, build_epoch: int) -> bytes:
    require_hex40(tree, "sanitized source tree")
    require_product_version(product_version)
    require_build_epoch(build_epoch)
    return (
        f"tree {tree}\n"
        "author CR6608 Release Builder <release@cr6608.invalid> "
        f"{build_epoch} +0000\n"
        "committer CR6608 Release Builder <release@cr6608.invalid> "
        f"{build_epoch} +0000\n"
        "\n"
        f"CR6608 {product_version} sanitized source kit\n"
    ).encode("utf-8")


def verify_source(
    repo: pathlib.Path,
    kit_base_commit: str,
    auth_fix_commit: str,
    *,
    require_clean: bool = True,
    require_closed: bool = True,
    expected_product_version: str | None = None,
    expected_build_epoch: int | None = None,
) -> SourceIdentity:
    require_hex40(kit_base_commit, "reviewed baseline commit")
    require_hex40(auth_fix_commit, "authentication fix commit")
    if expected_product_version is not None:
        require_product_version(expected_product_version)
    if expected_build_epoch is not None:
        require_build_epoch(expected_build_epoch)
    if require_clean:
        require_clean_source(repo)

    head = git(repo, "rev-parse", "HEAD").decode("ascii").strip()
    head_tree = git(repo, "rev-parse", "HEAD^{tree}").decode("ascii").strip()
    require_hex40(head, "source HEAD")
    require_hex40(head_tree, "source HEAD tree")
    if git(repo, "rev-parse", "--show-object-format").strip() != b"sha1":
        raise SourceKitError("source repository must use Git SHA-1 object format")

    entry_map = {path: (mode, obj_type, oid) for mode, obj_type, oid, path in ls_tree_entries(repo, head)}
    has_identity = IDENTITY_NAME in entry_map
    has_manifest = PAYLOAD_NAME in entry_map
    if has_identity != has_manifest:
        raise SourceKitError("sanitized source metadata is incomplete")

    if not has_identity:
        for ancestor, label in (
            (kit_base_commit, "reviewed baseline"),
            (auth_fix_commit, "authentication fix"),
        ):
            try:
                git(repo, "merge-base", "--is-ancestor", ancestor, head)
            except SourceKitError as exc:
                raise SourceKitError(f"source does not descend from the {label}") from exc
        return SourceIdentity(
            mode="reviewed-history",
            product_version=expected_product_version or "",
            build_epoch="" if expected_build_epoch is None else str(expected_build_epoch),
            original_commit=head,
            original_tree=head_tree,
            container_commit=head,
            container_tree=head_tree,
            kit_base_commit=kit_base_commit,
            auth_fix_commit=auth_fix_commit,
            payload_manifest_sha256=hashlib.sha256(payload_manifest(repo, head)).hexdigest(),
        )

    if entry_map[IDENTITY_NAME][0] != "100644" or entry_map[PAYLOAD_NAME][0] != "100644":
        raise SourceKitError("sanitized source metadata must be regular mode-100644 files")
    parents = git(repo, "rev-list", "--parents", "-n", "1", head).decode("ascii").split()
    if parents != [head] or git(repo, "rev-list", "--count", "--all").strip() != b"1":
        raise SourceKitError("sanitized source must contain exactly one root commit across all refs")
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD").decode("utf-8").strip()
    if branch != "source-kit":
        raise SourceKitError("sanitized source must be checked out on source-kit")

    identity_blob = git(repo, "cat-file", "blob", entry_map[IDENTITY_NAME][2])
    manifest_blob = git(repo, "cat-file", "blob", entry_map[PAYLOAD_NAME][2])
    values = parse_identity(identity_blob)
    if values["schema"] != IDENTITY_SCHEMA:
        raise SourceKitError("sanitized source identity schema is unsupported")
    require_product_version(values["product_version"])
    try:
        identity_build_epoch = int(values["build_epoch"], 10)
    except ValueError as exc:
        raise SourceKitError("identity build epoch is not a decimal integer") from exc
    if str(identity_build_epoch) != values["build_epoch"]:
        raise SourceKitError("identity build epoch is not canonical decimal")
    require_build_epoch(identity_build_epoch)
    if (
        expected_product_version is not None
        and values["product_version"] != expected_product_version
    ):
        raise SourceKitError("sanitized source product version differs from the trusted value")
    if expected_build_epoch is not None and identity_build_epoch != expected_build_epoch:
        raise SourceKitError("sanitized source build epoch differs from the trusted value")
    if values["payload_manifest"] != PAYLOAD_NAME:
        raise SourceKitError("sanitized source identity names the wrong payload manifest")
    if values["kit_base_commit"] != kit_base_commit or values["auth_fix_commit"] != auth_fix_commit:
        raise SourceKitError("sanitized source identity disagrees with reviewed commit pins")
    require_hex40(values["original_commit"], "identity original commit")
    require_hex40(values["original_tree"], "identity original tree")
    if not HEX64.fullmatch(values["payload_manifest_sha256"]):
        raise SourceKitError("identity payload manifest hash is malformed")
    manifest_sha = hashlib.sha256(manifest_blob).hexdigest()
    if manifest_sha != values["payload_manifest_sha256"]:
        raise SourceKitError("sanitized source payload manifest hash mismatch")
    expected_manifest = payload_manifest(repo, head)
    if manifest_blob != expected_manifest:
        raise SourceKitError("sanitized source payload manifest content mismatch")
    if tree_without_metadata(repo, head) != values["original_tree"]:
        raise SourceKitError("sanitized source payload tree differs from the original tree")
    commit_object = git(repo, "cat-file", "commit", head)
    expected_commit_object = canonical_root_commit_object(
        head_tree, values["product_version"], identity_build_epoch
    )
    if commit_object != expected_commit_object:
        raise SourceKitError("sanitized source root commit metadata is not canonical")
    if require_closed:
        assert_closed_sanitized_repository(repo, head, require_single_ref=False)

    return SourceIdentity(
        mode="sanitized-source-kit",
        product_version=values["product_version"],
        build_epoch=values["build_epoch"],
        original_commit=values["original_commit"],
        original_tree=values["original_tree"],
        container_commit=head,
        container_tree=head_tree,
        kit_base_commit=kit_base_commit,
        auth_fix_commit=auth_fix_commit,
        payload_manifest_sha256=manifest_sha,
    )


def identity_bytes(identity: SourceIdentity) -> bytes:
    return (
        f"schema={IDENTITY_SCHEMA}\n"
        f"product_version={identity.product_version}\n"
        f"build_epoch={identity.build_epoch}\n"
        f"original_commit={identity.original_commit}\n"
        f"original_tree={identity.original_tree}\n"
        f"kit_base_commit={identity.kit_base_commit}\n"
        f"auth_fix_commit={identity.auth_fix_commit}\n"
        f"payload_manifest={PAYLOAD_NAME}\n"
        f"payload_manifest_sha256={identity.payload_manifest_sha256}\n"
    ).encode("utf-8")


def safe_remove_work_dir(work: pathlib.Path, output: pathlib.Path) -> None:
    resolved_work = work.resolve(strict=True)
    resolved_output = output.resolve(strict=True)
    if resolved_work.parent != resolved_output or not resolved_work.name.startswith(".source-kit-work-"):
        raise SourceKitError(f"refusing unsafe source-kit work cleanup: {resolved_work}")
    def remove_readonly(function, path, _error):
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        function(path)

    shutil.rmtree(resolved_work, onerror=remove_readonly)


def extract_payload(repo: pathlib.Path, commit: str, destination: pathlib.Path) -> None:
    archive = subprocess.Popen(
        ("git", "-c", "core.autocrlf=false", "-C", str(repo), "archive", "--format=tar", commit),
        env=isolated_git_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert archive.stdout is not None
    untar = subprocess.run(
        ("tar", "-xf", "-", "-C", str(destination)),
        stdin=archive.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    archive.stdout.close()
    archive_stderr = archive.stderr.read() if archive.stderr is not None else b""
    archive_status = archive.wait()
    if archive_status != 0 or untar.returncode != 0:
        detail = (archive_stderr + untar.stderr).decode("utf-8", "replace").strip()
        raise SourceKitError(f"failed to materialize exact source payload: {detail}")


def write_file(path: pathlib.Path, content: bytes, mode: int = 0o644) -> None:
    if path.exists() or path.is_symlink():
        raise SourceKitError(f"refusing to overwrite source-kit file: {path}")
    path.write_bytes(content)
    path.chmod(mode)


def make_root_commit(repo: pathlib.Path, tree: str, build_epoch: int, product_version: str) -> str:
    timestamp = dt.datetime.fromtimestamp(build_epoch, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S +0000")
    env = isolated_git_env()
    env.update(
        {
            "GIT_AUTHOR_NAME": "CR6608 Release Builder",
            "GIT_AUTHOR_EMAIL": "release@cr6608.invalid",
            "GIT_AUTHOR_DATE": timestamp,
            "GIT_COMMITTER_NAME": "CR6608 Release Builder",
            "GIT_COMMITTER_EMAIL": "release@cr6608.invalid",
            "GIT_COMMITTER_DATE": timestamp,
        }
    )
    message = f"CR6608 {product_version} sanitized source kit\n"
    commit = run(
        ("git", "-C", str(repo), "commit-tree", tree),
        env=env,
        input_bytes=message.encode("utf-8"),
    ).stdout.decode("ascii").strip()
    require_hex40(commit, "sanitized source commit")
    if git(repo, "cat-file", "commit", commit) != canonical_root_commit_object(
        tree, product_version, build_epoch
    ):
        raise SourceKitError("Git emitted non-canonical sanitized root commit metadata")
    git(repo, "update-ref", "refs/heads/source-kit", commit)
    git(repo, "symbolic-ref", "HEAD", "refs/heads/source-kit")
    git(repo, "reset", "--mixed", commit)
    return commit


def create_archive(repo: pathlib.Path, destination: pathlib.Path) -> None:
    archive = subprocess.Popen(
        (
            "git",
            "-c",
            "core.autocrlf=false",
            "-C",
            str(repo),
            "archive",
            "--format=tar",
            "--prefix=cr6608-source-kit/",
            "HEAD",
        ),
        env=isolated_git_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert archive.stdout is not None
    try:
        with lzma.open(destination, "xb", preset=9) as output:
            shutil.copyfileobj(archive.stdout, output, length=1024 * 1024)
    finally:
        archive.stdout.close()
    archive_stderr = archive.stderr.read() if archive.stderr is not None else b""
    archive_status = archive.wait()
    if archive_status != 0:
        destination.unlink(missing_ok=True)
        detail = archive_stderr.decode("utf-8", "replace").strip()
        raise SourceKitError(f"failed to create source inspection archive: {detail}")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def snapshot_regular_file(
    source_arg: str,
    destination: pathlib.Path,
    expected_sha256: str,
    label: str,
) -> str:
    """Copy and hash one opened inode, then use only the private snapshot."""
    require_hex64(expected_sha256, f"trusted {label} SHA-256")
    if any(character in source_arg for character in "\t\r\n"):
        raise SourceKitError(f"{label} path contains a control character")
    source = pathlib.Path(source_arg).absolute()
    try:
        before = source.lstat()
    except OSError as exc:
        raise SourceKitError(f"{label} cannot be inspected: {source}") from exc
    if not stat.S_ISREG(before.st_mode):
        raise SourceKitError(f"{label} must be a regular non-symlink file")
    if destination.exists() or destination.is_symlink():
        raise SourceKitError(f"refusing to overwrite private {label} snapshot")
    flags = os.O_RDONLY
    flags |= getattr(os, "O_BINARY", 0)
    flags |= getattr(os, "O_CLOEXEC", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(source, flags)
    except OSError as exc:
        raise SourceKitError(f"{label} could not be opened without following links") from exc
    digest = hashlib.sha256()
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode) or (
            (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino)
        ):
            raise SourceKitError(f"{label} changed before its trusted snapshot")
        with os.fdopen(descriptor, "rb", closefd=False) as source_handle:
            with destination.open("xb") as output_handle:
                for block in iter(lambda: source_handle.read(1024 * 1024), b""):
                    digest.update(block)
                    output_handle.write(block)
                output_handle.flush()
                os.fsync(output_handle.fileno())
        after = os.fstat(descriptor)
        if (
            (opened.st_dev, opened.st_ino, opened.st_size)
            != (after.st_dev, after.st_ino, after.st_size)
            or getattr(opened, "st_mtime_ns", None)
            != getattr(after, "st_mtime_ns", None)
        ):
            raise SourceKitError(f"{label} changed while its trusted snapshot was copied")
    finally:
        os.close(descriptor)
    actual_sha256 = digest.hexdigest()
    if actual_sha256 != expected_sha256:
        destination.unlink(missing_ok=True)
        raise SourceKitError(f"{label} SHA-256 differs from the trusted value")
    destination.chmod(0o400)
    return actual_sha256


def repository_git_path(repo: pathlib.Path, relative: str) -> pathlib.Path:
    candidate = pathlib.Path(
        git(repo, "rev-parse", "--git-path", relative).decode("utf-8").strip()
    )
    if not candidate.is_absolute():
        candidate = repo / candidate
    return candidate.resolve(strict=False)


def assert_bundle_shape(
    bundle: pathlib.Path, expected_commit: str, repository: pathlib.Path
) -> None:
    git(repository, "bundle", "verify", str(bundle))
    heads = run(
        ("git", "bundle", "list-heads", str(bundle)), env=isolated_git_env()
    ).stdout.decode("ascii").splitlines()
    if heads != [f"{expected_commit} refs/heads/source-kit"]:
        raise SourceKitError("source bundle does not expose exactly one source-kit head")


def assert_closed_sanitized_repository(
    repo: pathlib.Path, expected_commit: str, *, require_single_ref: bool = True
) -> None:
    """Reject hidden refs, replacements, shallow state, alternates, and unreachable objects."""
    refs = git(repo, "for-each-ref", "--format=%(objectname) %(refname)").decode(
        "ascii"
    ).splitlines()
    if require_single_ref:
        if refs != [f"{expected_commit} refs/heads/source-kit"]:
            raise SourceKitError("sanitized repository exposes hidden or unexpected refs")
    elif not refs or any(
        not ref.startswith(f"{expected_commit} ") for ref in refs
    ):
        raise SourceKitError("sanitized repository refs expose an unexpected object")
    if git(repo, "rev-parse", "--is-shallow-repository").strip() != b"false":
        raise SourceKitError("sanitized repository must not be shallow")
    if git(repo, "replace", "-l").strip():
        raise SourceKitError("sanitized repository contains replacement refs")
    for relative, label in (
        ("objects/info/alternates", "object alternates"),
        ("info/grafts", "legacy grafts"),
        ("shallow", "shallow boundary"),
    ):
        candidate = repository_git_path(repo, relative)
        if candidate.exists() or candidate.is_symlink():
            raise SourceKitError(f"sanitized repository contains forbidden {label}")
    fsck = run(
        (
            "git",
            "-c",
            "core.autocrlf=false",
            "-C",
            str(repo),
            "fsck",
            "--full",
            "--no-reflogs",
            "--unreachable",
            "--no-progress",
        ),
        env=isolated_git_env(),
    )
    if fsck.stdout.strip() or fsck.stderr.strip():
        detail = (fsck.stdout + fsck.stderr).decode("utf-8", "replace").strip()
        raise SourceKitError(f"sanitized repository object closure is not exact: {detail}")


def prune_temporary_git_objects(repo: pathlib.Path) -> None:
    """Drop assembly-only trees/blobs before a sanitized repository is bundled."""
    git(repo, "reflog", "expire", "--expire=now", "--all")
    git(repo, "gc", "--prune=now", "--quiet")


def assert_expected_identity(
    identity: SourceIdentity,
    *,
    product_version: str,
    build_epoch: int,
    original_commit: str,
    original_tree: str,
    container_commit: str,
    container_tree: str,
    payload_manifest_sha256: str,
) -> None:
    expected = {
        "product version": product_version,
        "build epoch": str(build_epoch),
        "original commit": original_commit,
        "original tree": original_tree,
        "container commit": container_commit,
        "container tree": container_tree,
        "payload manifest SHA-256": payload_manifest_sha256,
    }
    actual = {
        "product version": identity.product_version,
        "build epoch": identity.build_epoch,
        "original commit": identity.original_commit,
        "original tree": identity.original_tree,
        "container commit": identity.container_commit,
        "container tree": identity.container_tree,
        "payload manifest SHA-256": identity.payload_manifest_sha256,
    }
    for label, trusted_value in expected.items():
        if actual[label] != trusted_value:
            raise SourceKitError(f"bundle {label} differs from the trusted value")


def verify_bundle_to_clone(
    bundle_arg: str,
    clone_arg: str,
    kit_base_commit: str,
    auth_fix_commit: str,
    *,
    expected_bundle_sha256: str,
    product_version: str,
    build_epoch: int,
    original_commit: str,
    original_tree: str,
    container_commit: str,
    container_tree: str,
    payload_manifest_sha256: str,
) -> tuple[pathlib.Path, SourceIdentity, str]:
    """Verify an externally pinned bundle before checkout and retain that exact clone."""
    require_hex40(kit_base_commit, "reviewed baseline commit")
    require_hex40(auth_fix_commit, "authentication fix commit")
    require_hex64(expected_bundle_sha256, "trusted source bundle SHA-256")
    require_product_version(product_version)
    require_build_epoch(build_epoch)
    for value, label in (
        (original_commit, "trusted original commit"),
        (original_tree, "trusted original tree"),
        (container_commit, "trusted container commit"),
        (container_tree, "trusted container tree"),
    ):
        require_hex40(value, label)
    require_hex64(payload_manifest_sha256, "trusted payload manifest SHA-256")

    if any(character in clone_arg for character in "\t\r\n"):
        raise SourceKitError("verified clone path contains a control character")
    raw_clone = pathlib.Path(clone_arg)
    if raw_clone.exists() or raw_clone.is_symlink():
        raise SourceKitError("verified clone destination already exists")
    clone_parent = raw_clone.parent.resolve(strict=True)
    if not clone_parent.is_dir():
        raise SourceKitError("verified clone parent is not a directory")
    clone_destination = (clone_parent / raw_clone.name).resolve(strict=False)
    if clone_destination.parent != clone_parent or clone_destination.name in ("", ".", ".."):
        raise SourceKitError("verified clone destination is unsafe")

    work = pathlib.Path(
        tempfile.mkdtemp(prefix=".cr6608-bundle-verify-", dir=clone_parent)
    )
    bundle = work / "trusted-input.bundle"
    clone = work / "verified-clone"
    template = work / "empty-git-template"
    template.mkdir(mode=0o700)
    try:
        # The byte hash is the trust bootstrap. Copy and hash one opened inode,
        # then let Git parse only this private immutable snapshot, closing the
        # hash/path replacement race.
        actual_bundle_sha256 = snapshot_regular_file(
            bundle_arg,
            bundle,
            expected_bundle_sha256,
            "source bundle",
        )
        heads = run(
            ("git", "bundle", "list-heads", str(bundle)), env=isolated_git_env()
        ).stdout.decode("ascii").splitlines()
        if heads != [f"{container_commit} refs/heads/source-kit"]:
            raise SourceKitError("source bundle ref differs from the trusted container commit")
        clone_env = isolated_git_env()
        clone_env["GIT_ALLOW_PROTOCOL"] = "file"
        run(
            (
                "git",
                "-c",
                "core.autocrlf=false",
                "clone",
                "-q",
                "--no-checkout",
                "--single-branch",
                "--branch",
                "source-kit",
                "--no-tags",
                "--no-local",
                "--template",
                str(template),
                "--config",
                f"core.hooksPath={os.devnull}",
                str(bundle),
                str(clone),
            ),
            env=clone_env,
        )
        git(clone, "remote", "remove", "origin")
        assert_bundle_shape(bundle, container_commit, clone)
        before_checkout = verify_source(
            clone,
            kit_base_commit,
            auth_fix_commit,
            require_clean=False,
            expected_product_version=product_version,
            expected_build_epoch=build_epoch,
        )
        assert_expected_identity(
            before_checkout,
            product_version=product_version,
            build_epoch=build_epoch,
            original_commit=original_commit,
            original_tree=original_tree,
            container_commit=container_commit,
            container_tree=container_tree,
            payload_manifest_sha256=payload_manifest_sha256,
        )
        assert_closed_sanitized_repository(clone, container_commit)

        git(clone, "checkout", "--force", "source-kit", "--")
        # Git records only the executable bit and otherwise applies the caller's
        # umask.  Normalize the private verified checkout before any bundled
        # source executes so a group-writable umask cannot weaken or destabilize
        # source contracts.
        normalize_checkout_modes(clone, container_commit)
        after_checkout = verify_source(
            clone,
            kit_base_commit,
            auth_fix_commit,
            expected_product_version=product_version,
            expected_build_epoch=build_epoch,
        )
        if after_checkout != before_checkout:
            raise SourceKitError("source identity changed while materializing verified clone")
        assert_closed_sanitized_repository(clone, container_commit)
        if clone_destination.exists() or clone_destination.is_symlink():
            raise SourceKitError("verified clone destination appeared during verification")
        clone.rename(clone_destination)
        return clone_destination, after_checkout, actual_bundle_sha256
    finally:
        if work.exists():
            resolved_work = work.resolve(strict=True)
            if (
                resolved_work.parent != clone_parent
                or not resolved_work.name.startswith(".cr6608-bundle-verify-")
            ):
                raise SourceKitError(f"refusing unsafe verified-clone cleanup: {resolved_work}")

            def remove_readonly(function, path, _error):
                os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
                function(path)

            shutil.rmtree(resolved_work, onerror=remove_readonly)


def run_source_reproduction(
    clone: pathlib.Path,
    build_env: Mapping[str, str],
    reproduction_log: pathlib.Path,
) -> int:
    """Run source tests in a dedicated POSIX process group and reap descendants."""
    with reproduction_log.open("xb") as log_handle:
        process = subprocess.Popen(
            ("bash", "./build.sh"),
            cwd=clone,
            env=dict(build_env),
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=(os.name == "posix"),
        )
        try:
            return_code = process.wait(timeout=7200)
        except subprocess.TimeoutExpired as exc:
            return_code = 124
            if os.name != "posix":
                process.kill()
                process.wait()
            raise SourceKitError("source-only reproduction exceeded two hours") from exc
        finally:
            if os.name == "posix":
                for group_signal in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(process.pid, group_signal)
                    except ProcessLookupError:
                        break
                    except OSError as exc:
                        raise SourceKitError(
                            "source-only reproduction descendants could not be terminated"
                        ) from exc
                    if group_signal == signal.SIGTERM:
                        time.sleep(0.2)
                if process.poll() is None:
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired as exc:
                        raise SourceKitError(
                            "source-only reproduction leader could not be reaped"
                        ) from exc
    return return_code


def create_source_kit(
    repo: pathlib.Path,
    output: pathlib.Path,
    kit_base_commit: str,
    auth_fix_commit: str,
    build_epoch: int,
    product_version: str,
    canonical_bundle: str | None = None,
    expected_canonical_bundle_sha256: str | None = None,
) -> dict[str, str]:
    require_product_version(product_version)
    require_build_epoch(build_epoch)
    if (canonical_bundle is None) != (expected_canonical_bundle_sha256 is None):
        raise SourceKitError(
            "canonical bundle and its trusted SHA-256 must be supplied together"
        )
    if expected_canonical_bundle_sha256 is not None:
        require_hex64(
            expected_canonical_bundle_sha256,
            "trusted canonical source bundle SHA-256",
        )
    output = output.resolve(strict=True)
    if not output.is_dir() or output.is_symlink():
        raise SourceKitError("source-kit output must be an existing non-symlink directory")
    final_names = (
        "cr6608-source-kit.bundle",
        "cr6608-source-kit.tar.xz",
        "source-kit-reproduction.txt",
        "source-kit-identity.txt",
        "source-kit-payload.tsv",
        "source-kit-metadata.txt",
    )
    for name in final_names:
        candidate = output / name
        if candidate.exists() or candidate.is_symlink():
            raise SourceKitError(f"refusing to overwrite source-kit output: {candidate}")

    verified = verify_source(
        repo,
        kit_base_commit,
        auth_fix_commit,
        expected_product_version=product_version,
        expected_build_epoch=build_epoch,
    )
    work = pathlib.Path(tempfile.mkdtemp(prefix=".source-kit-work-", dir=output))
    try:
        container = work / "container"
        container.mkdir(mode=0o755)
        extract_payload(repo, verified.container_commit, container)
        for metadata_name in (IDENTITY_NAME, PAYLOAD_NAME):
            metadata_path = container / metadata_name
            if metadata_path.exists() or metadata_path.is_symlink():
                if not metadata_path.is_file() or metadata_path.is_symlink():
                    raise SourceKitError(f"source metadata payload has an unsafe type: {metadata_name}")
                metadata_path.unlink()

        run(
            ("git", "init", "-q", "-b", "source-kit", str(container)),
            env=isolated_git_env(),
        )
        git(container, "config", "core.autocrlf", "false")
        git(container, "add", "-A")
        # Do not trust the extraction filesystem to preserve executable bits
        # (notably on Windows). Rebind regular-file modes from the verified Git
        # tree, and fail closed if a tracked symlink was materialized as a
        # regular file rather than a symlink.
        for mode, _obj_type, _oid, path in ls_tree_entries(
            repo, verified.container_commit
        ):
            if path in (IDENTITY_NAME, PAYLOAD_NAME):
                continue
            materialized = container / path
            if mode == "120000":
                if not materialized.is_symlink():
                    raise SourceKitError(
                        f"materialized source lost tracked symlink type: {path}"
                    )
            elif mode == "100755":
                git(container, "update-index", "--chmod=+x", "--", path)
            elif mode == "100644":
                git(container, "update-index", "--chmod=-x", "--", path)
        payload_tree = git(container, "write-tree").decode("ascii").strip()
        if payload_tree != verified.original_tree:
            raise SourceKitError("materialized payload tree differs from the verified original tree")

        manifest = payload_manifest(repo, verified.container_commit)
        manifest_sha = hashlib.sha256(manifest).hexdigest()
        if manifest_sha != verified.payload_manifest_sha256:
            raise SourceKitError("source payload manifest changed during source-kit assembly")
        kit_identity = SourceIdentity(
            mode="sanitized-source-kit",
            product_version=product_version,
            build_epoch=str(build_epoch),
            original_commit=verified.original_commit,
            original_tree=verified.original_tree,
            container_commit="",
            container_tree="",
            kit_base_commit=kit_base_commit,
            auth_fix_commit=auth_fix_commit,
            payload_manifest_sha256=manifest_sha,
        )
        write_file(container / PAYLOAD_NAME, manifest)
        identity_content = identity_bytes(kit_identity)
        write_file(container / IDENTITY_NAME, identity_content)
        git(container, "add", "--", IDENTITY_NAME, PAYLOAD_NAME)
        container_tree = git(container, "write-tree").decode("ascii").strip()
        require_hex40(container_tree, "sanitized source tree")
        container_commit = make_root_commit(
            container, container_tree, build_epoch, product_version
        )
        assembled = verify_source(
            container,
            kit_base_commit,
            auth_fix_commit,
            expected_product_version=product_version,
            expected_build_epoch=build_epoch,
            require_closed=False,
        )
        if (
            assembled.original_commit != verified.original_commit
            or assembled.original_tree != verified.original_tree
            or assembled.container_commit != container_commit
            or assembled.container_tree != container_tree
        ):
            raise SourceKitError("assembled sanitized source identity changed during verification")
        prune_temporary_git_objects(container)
        assert_closed_sanitized_repository(container, container_commit)

        # This bundle is reproduction input only. The source-only build is
        # permitted to write within its temporary parent, so never publish an
        # artifact that existed while bundle code was executing.
        reproduction_bundle = work / "reproduction-input.bundle"
        run(
            (
                "git",
                "-C",
                str(container),
                "bundle",
                "create",
                str(reproduction_bundle),
                "refs/heads/source-kit",
            ),
            env=isolated_git_env(),
        )
        assert_bundle_shape(reproduction_bundle, container_commit, container)
        reproduction_root = work / "reproduction"
        reproduction_root.mkdir(mode=0o755)
        clone = reproduction_root / "cr6608-source-kit"
        reproduction_bundle_sha256 = sha256_file(reproduction_bundle)
        verified_clone, clone_identity, _bundle_sha256 = verify_bundle_to_clone(
            str(reproduction_bundle),
            str(clone),
            kit_base_commit,
            auth_fix_commit,
            expected_bundle_sha256=reproduction_bundle_sha256,
            product_version=product_version,
            build_epoch=build_epoch,
            original_commit=verified.original_commit,
            original_tree=verified.original_tree,
            container_commit=container_commit,
            container_tree=container_tree,
            payload_manifest_sha256=manifest_sha,
        )
        if verified_clone != clone.resolve(strict=True):
            raise SourceKitError("trusted verifier retained the wrong reproduction clone")
        if clone_identity != assembled:
            raise SourceKitError("bundle clone identity differs from assembled source kit")

        reproduction_log = work / "source-kit-reproduction.txt"
        build_env = isolated_git_env()
        node_runtime = build_env.get("CR6608_NODE_BIN")
        for environment_name in tuple(build_env):
            if environment_name.startswith("CR6608_"):
                build_env.pop(environment_name, None)
        # Source-only reproduction is public and self-contained. Never let
        # caller-private evidence, maintenance inputs, or future CR6608 knobs
        # become undeclared dependencies. The explicit Node selector is the
        # sole retained host-runtime locator; its browser artifacts are hashed
        # by build.sh.
        build_env["CR6608_SOURCE_TEST_ONLY"] = "1"
        if node_runtime:
            build_env["CR6608_NODE_BIN"] = node_runtime
        build_env["SMARTAP_BUILD_EPOCH"] = str(build_epoch)
        build_env["CR6608_VERIFIED_SOURCE_BUNDLE"] = str(reproduction_bundle)
        build_env["CR6608_EXPECTED_SOURCE_BUNDLE_SHA256"] = reproduction_bundle_sha256
        build_env["CR6608_EXPECTED_ORIGINAL_COMMIT"] = verified.original_commit
        build_env["CR6608_EXPECTED_ORIGINAL_TREE"] = verified.original_tree
        build_env["CR6608_EXPECTED_CONTAINER_COMMIT"] = container_commit
        build_env["CR6608_EXPECTED_CONTAINER_TREE"] = container_tree
        build_env["CR6608_EXPECTED_PAYLOAD_MANIFEST_SHA256"] = manifest_sha
        reproduction_status = run_source_reproduction(
            clone, build_env, reproduction_log
        )
        if reproduction_status != 0:
            raise SourceKitError(
                "source-only reproduction from sanitized bundle failed with exit "
                f"{reproduction_status}"
            )
        if b"source_tests=pass\n" not in reproduction_log.read_bytes():
            raise SourceKitError("source-only reproduction log lacks its final pass marker")
        clone_after = verify_source(
            clone,
            kit_base_commit,
            auth_fix_commit,
            require_clean=False,
            expected_product_version=product_version,
            expected_build_epoch=build_epoch,
        )
        if clone_after != clone_identity:
            raise SourceKitError("source identity changed during source-only reproduction")
        tracked_status = git(clone, "status", "--porcelain=v1", "--untracked-files=no")
        if tracked_status:
            raise SourceKitError("source-only reproduction changed tracked source files")

        # Re-verify the immutable source repository after the child exits,
        # then generate publishable artifacts in a directory that did not
        # exist while bundle code was running.
        container_after = verify_source(
            container,
            kit_base_commit,
            auth_fix_commit,
            expected_product_version=product_version,
            expected_build_epoch=build_epoch,
        )
        if container_after != assembled:
            raise SourceKitError("assembled source changed during bundle reproduction")
        assert_closed_sanitized_repository(container, container_commit)
        final_artifacts = work / "final-artifacts"
        final_artifacts.mkdir(mode=0o700)
        rebuilt_bundle = final_artifacts / "rebuilt-source-kit.bundle"
        run(
            (
                "git",
                "-c",
                "pack.threads=1",
                "-c",
                "pack.compression=9",
                "-C",
                str(container),
                "bundle",
                "create",
                str(rebuilt_bundle),
                "refs/heads/source-kit",
            ),
            env=isolated_git_env(),
        )
        assert_bundle_shape(rebuilt_bundle, container_commit, container)
        rebuilt_bundle_sha256 = sha256_file(rebuilt_bundle)
        bundle_temp = final_artifacts / "cr6608-source-kit.bundle"
        if canonical_bundle is None:
            rebuilt_bundle.replace(bundle_temp)
            canonical_bundle_role = "locally-rebuilt-canonical"
        else:
            assert expected_canonical_bundle_sha256 is not None
            snapshot_regular_file(
                canonical_bundle,
                bundle_temp,
                expected_canonical_bundle_sha256,
                "canonical source bundle",
            )
            canonical_check_root = work / "canonical-bundle-verification"
            canonical_check_root.mkdir(mode=0o700)
            _canonical_clone, canonical_identity, _canonical_sha256 = (
                verify_bundle_to_clone(
                    str(bundle_temp),
                    str(canonical_check_root / "verified-clone"),
                    kit_base_commit,
                    auth_fix_commit,
                    expected_bundle_sha256=expected_canonical_bundle_sha256,
                    product_version=product_version,
                    build_epoch=build_epoch,
                    original_commit=verified.original_commit,
                    original_tree=verified.original_tree,
                    container_commit=container_commit,
                    container_tree=container_tree,
                    payload_manifest_sha256=manifest_sha,
                )
            )
            if canonical_identity != assembled:
                raise SourceKitError(
                    "externally trusted canonical bundle differs from assembled source"
                )
            canonical_bundle_role = "externally-trusted-build-input"
        assert_bundle_shape(bundle_temp, container_commit, container)
        archive_temp = final_artifacts / "cr6608-source-kit.tar.xz"
        create_archive(container, archive_temp)

        identity_copy = work / "source-kit-identity.txt"
        payload_copy = work / "source-kit-payload.tsv"
        identity_copy.write_bytes(identity_content)
        payload_copy.write_bytes(manifest)
        identity_copy.chmod(0o644)
        payload_copy.chmod(0o644)

        metadata_values = {
            "source_kit_schema": IDENTITY_SCHEMA,
            "source_kit_product_version": product_version,
            "source_kit_build_epoch": str(build_epoch),
            "source_kit_build_time_utc": dt.datetime.fromtimestamp(
                build_epoch, tz=dt.timezone.utc
            ).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "source_kit_original_commit": verified.original_commit,
            "source_kit_original_commit_object": "not_embedded_privacy_v1",
            "source_kit_original_tree": verified.original_tree,
            "source_kit_container_commit": container_commit,
            "source_kit_container_tree": container_tree,
            "source_kit_root_commit_count": "1",
            "source_kit_bundle_ref": "refs/heads/source-kit",
            "source_kit_bundle_ref_count": "1",
            "source_kit_bundle_role": canonical_bundle_role,
            "source_kit_git_version": run(
                ("git", "--version"), env=isolated_git_env()
            ).stdout.decode("ascii").strip(),
            "source_kit_identity_sha256": hashlib.sha256(identity_content).hexdigest(),
            "source_kit_payload_manifest_sha256": manifest_sha,
            "source_kit_bundle_sha256": sha256_file(bundle_temp),
            "source_kit_rebuilt_bundle_sha256": rebuilt_bundle_sha256,
            "source_kit_archive_sha256": sha256_file(archive_temp),
            "source_kit_reproduction_log_sha256": sha256_file(reproduction_log),
            "source_kit_reproduction_status": "pass",
        }
        metadata_content = "".join(
            f"{key}={value}\n" for key, value in metadata_values.items()
        ).encode("ascii")
        metadata_temp = work / "source-kit-metadata.txt"
        metadata_temp.write_bytes(metadata_content)
        metadata_temp.chmod(0o644)

        moves = (
            (bundle_temp, output / "cr6608-source-kit.bundle"),
            (archive_temp, output / "cr6608-source-kit.tar.xz"),
            (reproduction_log, output / "source-kit-reproduction.txt"),
            (identity_copy, output / "source-kit-identity.txt"),
            (payload_copy, output / "source-kit-payload.tsv"),
            (metadata_temp, output / "source-kit-metadata.txt"),
        )
        for source, destination in moves:
            source.replace(destination)
            destination.chmod(0o644)
        assert_bundle_shape(
            output / "cr6608-source-kit.bundle", container_commit, container
        )
        if (
            sha256_file(output / "cr6608-source-kit.bundle")
            != metadata_values["source_kit_bundle_sha256"]
        ):
            raise SourceKitError("published source bundle changed after final assembly")
        return metadata_values
    finally:
        if work.exists():
            safe_remove_work_dir(work, output)


def emit_identity(identity: SourceIdentity) -> None:
    values = (
        ("source_repository_mode", identity.mode),
        ("source_product_version", identity.product_version),
        ("source_build_epoch", identity.build_epoch),
        ("source_original_commit", identity.original_commit),
        ("source_original_tree", identity.original_tree),
        ("source_container_commit", identity.container_commit),
        ("source_container_tree", identity.container_tree),
        ("source_kit_base_commit", identity.kit_base_commit),
        ("source_auth_fix_commit", identity.auth_fix_commit),
        ("source_payload_manifest_sha256", identity.payload_manifest_sha256),
    )
    for key, value in values:
        print(f"{key}={value}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    verify = commands.add_parser("verify", help="verify reviewed or sanitized source")
    verify.add_argument("--repo", required=True)
    verify.add_argument("--kit-base", required=True)
    verify.add_argument("--auth-fix", required=True)
    verify.add_argument("--product-version")
    verify.add_argument("--build-epoch", type=int)

    create = commands.add_parser("create", help="create and reproduce a sanitized source kit")
    create.add_argument("--repo", required=True)
    create.add_argument("--output-dir", required=True)
    create.add_argument("--kit-base", required=True)
    create.add_argument("--auth-fix", required=True)
    create.add_argument("--build-epoch", required=True, type=int)
    create.add_argument("--product-version", required=True)
    create.add_argument("--canonical-bundle")
    create.add_argument("--expected-canonical-bundle-sha256")

    verify_bundle = commands.add_parser(
        "verify-bundle",
        help="verify externally pinned bundle bytes and retain the exact verified clone",
    )
    verify_bundle.add_argument("--bundle", required=True)
    verify_bundle.add_argument("--clone-dir", required=True)
    verify_bundle.add_argument("--kit-base", required=True)
    verify_bundle.add_argument("--auth-fix", required=True)
    verify_bundle.add_argument("--product-version", required=True)
    verify_bundle.add_argument("--build-epoch", required=True, type=int)
    verify_bundle.add_argument("--expected-bundle-sha256", required=True)
    verify_bundle.add_argument("--expected-original-commit", required=True)
    verify_bundle.add_argument("--expected-original-tree", required=True)
    verify_bundle.add_argument("--expected-container-commit", required=True)
    verify_bundle.add_argument("--expected-container-tree", required=True)
    verify_bundle.add_argument(
        "--expected-payload-manifest-sha256", required=True
    )
    return root


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "verify":
            if (args.product_version is None) != (args.build_epoch is None):
                raise SourceKitError(
                    "verify requires product version and build epoch together"
                )
            repo = resolve_repo(args.repo)
            emit_identity(
                verify_source(
                    repo,
                    args.kit_base,
                    args.auth_fix,
                    expected_product_version=args.product_version,
                    expected_build_epoch=args.build_epoch,
                )
            )
        elif args.command == "create":
            repo = resolve_repo(args.repo)
            output = pathlib.Path(args.output_dir).resolve(strict=True)
            values = create_source_kit(
                repo,
                output,
                args.kit_base,
                args.auth_fix,
                args.build_epoch,
                args.product_version,
                args.canonical_bundle,
                args.expected_canonical_bundle_sha256,
            )
            for key, value in values.items():
                print(f"{key}={value}")
        else:
            clone, identity, bundle_sha256 = verify_bundle_to_clone(
                args.bundle,
                args.clone_dir,
                args.kit_base,
                args.auth_fix,
                expected_bundle_sha256=args.expected_bundle_sha256,
                product_version=args.product_version,
                build_epoch=args.build_epoch,
                original_commit=args.expected_original_commit,
                original_tree=args.expected_original_tree,
                container_commit=args.expected_container_commit,
                container_tree=args.expected_container_tree,
                payload_manifest_sha256=args.expected_payload_manifest_sha256,
            )
            print(f"source_bundle_sha256={bundle_sha256}")
            print(f"source_verified_clone={clone}")
            emit_identity(identity)
        return 0
    except SourceKitError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
