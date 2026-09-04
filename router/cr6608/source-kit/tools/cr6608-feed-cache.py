#!/usr/bin/env python3
"""Verify and atomically restore one pinned OpenWrt feed archive.

The archive is an external build cache, never a trust root.  Its complete
SHA-256, every member path/type, and the resulting Git identity are verified
before the destination becomes visible.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")


class CacheError(RuntimeError):
    pass


def fail(message: str) -> "None":
    raise CacheError(message)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def normalized_member(name: str) -> str:
    if not name or "\x00" in name or "\\" in name:
        fail("archive member has an invalid name")
    path = PurePosixPath(name)
    if path.is_absolute():
        fail(f"archive contains an absolute path: {name!r}")
    parts = tuple(part for part in path.parts if part not in ("", "."))
    if ".." in parts:
        fail(f"archive contains parent traversal: {name!r}")
    return PurePosixPath(*parts).as_posix() if parts else "."


def validate_members(members: list[tarfile.TarInfo]) -> None:
    if not members:
        fail("archive is empty")
    seen: set[str] = set()
    for member in members:
        normalized = normalized_member(member.name)
        if normalized in seen:
            fail(f"archive contains a duplicate path: {normalized!r}")
        seen.add(normalized)
        if not (member.isdir() or member.isfile()):
            fail(f"archive contains a non-regular entry: {member.name!r}")
        if member.mode & 0o7000:
            fail(f"archive member has unsafe special mode bits: {member.name!r}")


def git_output(git: str, repository: Path, *arguments: str) -> str:
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("GIT_")
    }
    environment.update(
        {
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_ATTR_NOSYSTEM": "1",
            "GIT_NO_REPLACE_OBJECTS": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_NO_LAZY_FETCH": "1",
            "LC_ALL": "C",
        }
    )
    result = subprocess.run(
        [git, "-C", os.fspath(repository), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    if result.returncode:
        detail = result.stderr.strip().splitlines()
        fail(f"git {' '.join(arguments)} failed: {detail[-1] if detail else result.returncode}")
    return result.stdout.rstrip("\n")


def verify_git(repository: Path, expected_commit: str, expected_origin: str, git: str) -> None:
    git_directory = repository / ".git"
    if not git_directory.is_dir() or git_directory.is_symlink():
        fail("extracted feed is not a real Git checkout")
    origins = git_output(git, repository, "remote", "get-url", "--all", "origin").splitlines()
    if origins != [expected_origin]:
        fail("extracted feed origin mismatch")
    head = git_output(git, repository, "rev-parse", "--verify", "HEAD")
    if head != expected_commit:
        fail("extracted feed commit mismatch")
    git_output(git, repository, "cat-file", "-e", f"{expected_commit}^{{commit}}")
    missing = [
        line
        for line in git_output(
            git, repository, "rev-list", "--objects", "--missing=print", expected_commit
        ).splitlines()
        if line.startswith("?")
    ]
    if missing:
        fail("extracted feed Git object closure is incomplete")
    # The pinned caches were produced on a different host.  Treat their Git
    # object database as the input and reconstruct the worktree from the pinned
    # commit so CRLF/file-mode differences cannot enter the build.
    git_output(git, repository, "reset", "--hard", expected_commit)
    git_output(git, repository, "clean", "-ffdx")
    if git_output(git, repository, "rev-parse", "--verify", "HEAD") != expected_commit:
        fail("normalized feed commit mismatch")
    if git_output(git, repository, "status", "--porcelain", "--untracked-files=all"):
        fail("normalized feed worktree is not clean")


def main() -> int:
    if len(sys.argv) not in (6, 7):
        print(
            "usage: cr6608-feed-cache.py ARCHIVE DEST SHA256 COMMIT ORIGIN [GIT]",
            file=sys.stderr,
        )
        return 64
    archive = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    expected_hash, expected_commit, expected_origin = sys.argv[3:6]
    git = sys.argv[6] if len(sys.argv) == 7 else "/usr/bin/git"
    if not HEX64.fullmatch(expected_hash):
        fail("expected archive SHA-256 is malformed")
    if not HEX40.fullmatch(expected_commit):
        fail("expected feed commit is malformed")
    if not expected_origin.startswith("https://") or any(c in expected_origin for c in "\r\n\t"):
        fail("expected feed origin is malformed")
    if not archive.is_file() or archive.is_symlink():
        fail("feed cache archive is missing or unsafe")
    if digest(archive) != expected_hash:
        fail("feed cache archive SHA-256 mismatch")
    if destination.exists() or destination.is_symlink():
        fail("feed destination must not exist before extraction")
    parent = destination.parent
    if not parent.is_dir() or parent.is_symlink():
        fail("feed destination parent is missing or unsafe")

    temporary = Path(tempfile.mkdtemp(prefix=f".{destination.name}.cache.", dir=parent))
    try:
        with tarfile.open(archive, mode="r:gz") as source:
            members = source.getmembers()
            validate_members(members)
            source.extractall(temporary, members=members, numeric_owner=False)
        verify_git(temporary, expected_commit, expected_origin, git)
        os.rename(temporary, destination)
        temporary = Path()
    finally:
        if temporary != Path() and temporary.exists():
            shutil.rmtree(temporary)
    print(f"feed_cache_restore=pass commit={expected_commit}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CacheError, OSError, tarfile.TarError) as error:
        print(f"feed_cache_restore=fail reason={error}", file=sys.stderr)
        raise SystemExit(1)
