#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FEED_TOOL = ROOT / "tools" / "cr6608-feed-cache.py"
TAG_GATE = ROOT / "tools" / "cr6608-openwrt-tag-gate.sh"
GIT = shutil.which("git") or "/usr/bin/git"


def run(*args: str, env: dict[str, str] | None = None, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if ok and result.returncode:
        raise AssertionError(f"command failed: {args}\n{result.stdout}\n{result.stderr}")
    if not ok and not result.returncode:
        raise AssertionError(f"command unexpectedly passed: {args}\n{result.stdout}")
    return result


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_feed(root: Path, origin: str) -> tuple[Path, str]:
    repository = root / "fixture-feed"
    repository.mkdir()
    run(GIT, "init", "-q", str(repository))
    run(GIT, "-C", str(repository), "config", "user.name", "Fixture")
    run(GIT, "-C", str(repository), "config", "user.email", "fixture@example.invalid")
    (repository / "Makefile").write_text("fixture\n", encoding="ascii")
    run(GIT, "-C", str(repository), "add", "Makefile")
    run(GIT, "-C", str(repository), "commit", "-qm", "fixture")
    run(GIT, "-C", str(repository), "remote", "add", "origin", origin)
    commit = run(GIT, "-C", str(repository), "rev-parse", "HEAD").stdout.strip()
    archive = root / "feed-fixture.tar.gz"
    with tarfile.open(archive, "w:gz") as output:
        for path in sorted(repository.rglob("*")):
            output.add(path, arcname=f"./{path.relative_to(repository).as_posix()}", recursive=False)
    return archive, commit


def feed_tests(root: Path) -> None:
    origin = "https://git.example.invalid/feed.git"
    archive, commit = make_feed(root, origin)
    restored = root / "restored"
    result = run(sys.executable, str(FEED_TOOL), str(archive), str(restored), sha(archive), commit, origin, GIT)
    assert result.stdout.strip() == f"feed_cache_restore=pass commit={commit}"
    assert run(GIT, "-C", str(restored), "status", "--porcelain").stdout == ""

    tampered = root / "tampered.tar.gz"
    tampered.write_bytes(archive.read_bytes() + b"tamper")
    tampered_out = root / "tampered-out"
    run(sys.executable, str(FEED_TOOL), str(tampered), str(tampered_out), sha(archive), commit, origin, GIT, ok=False)
    assert not tampered_out.exists()
    missing_out = root / "missing-out"
    run(sys.executable, str(FEED_TOOL), str(root / "missing.tar.gz"), str(missing_out), sha(archive), commit, origin, GIT, ok=False)
    assert not missing_out.exists()

    traversal = root / "traversal.tar.gz"
    with tarfile.open(traversal, "w:gz") as output:
        member = tarfile.TarInfo("../escape")
        member.size = 1
        output.addfile(member, io.BytesIO(b"x"))
    traversal_out = root / "traversal-out"
    run(sys.executable, str(FEED_TOOL), str(traversal), str(traversal_out), sha(traversal), commit, origin, GIT, ok=False)
    assert not (root / "escape").exists()
    assert not traversal_out.exists()

    absolute = root / "absolute.tar.gz"
    absolute_escape = root / "absolute-escape"
    with tarfile.open(absolute, "w:gz") as output:
        member = tarfile.TarInfo(str(absolute_escape))
        member.size = 1
        output.addfile(member, io.BytesIO(b"x"))
    absolute_out = root / "absolute-out"
    run(sys.executable, str(FEED_TOOL), str(absolute), str(absolute_out), sha(absolute), commit, origin, GIT, ok=False)
    assert not absolute_escape.exists()
    assert not absolute_out.exists()

    symlink = root / "symlink.tar.gz"
    with tarfile.open(symlink, "w:gz") as output:
        member = tarfile.TarInfo("unsafe-link")
        member.type = tarfile.SYMTYPE
        member.linkname = "../escape"
        output.addfile(member)
    symlink_out = root / "symlink-out"
    run(sys.executable, str(FEED_TOOL), str(symlink), str(symlink_out), sha(symlink), commit, origin, GIT, ok=False)
    assert not symlink_out.exists()

    wrong_commit_out = root / "wrong-commit"
    run(sys.executable, str(FEED_TOOL), str(archive), str(wrong_commit_out), sha(archive), "0" * 40, origin, GIT, ok=False)
    assert not wrong_commit_out.exists()
    wrong_origin_out = root / "wrong-origin"
    run(sys.executable, str(FEED_TOOL), str(archive), str(wrong_origin_out), sha(archive), commit, "https://wrong.invalid/feed.git", GIT, ok=False)
    assert not wrong_origin_out.exists()


def executable(path: Path, source: str) -> None:
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def tag_gate_tests(root: Path) -> None:
    mock = root / "mock"
    mock.mkdir()
    repository = root / "openwrt"
    (repository / ".git").mkdir(parents=True)
    key = root / "release.asc"
    key.write_text("fixture release key\n", encoding="ascii")
    commit = "1" * 40
    tag_object = "2" * 40
    signer = "A" * 40
    origin = "https://git.example.invalid/openwrt.git"
    executable(
        mock / "git",
        f"""#!/bin/sh
[ -z \"${{GIT_DIR:-}}\" ] && [ -z \"${{GIT_CONFIG_COUNT:-}}\" ] || exit 91
case \"$*\" in
  *\"remote get-url --all origin\"*)
    [ \"${{MOCK_ORIGIN:-ok}}\" = ok ] && printf '%s\\n' '{origin}' || printf '%s\\n' 'https://wrong.invalid/openwrt.git' ;;
  *\"cat-file -t refs/tags/v1\"*) printf 'tag\\n' ;;
  *\"rev-parse --verify refs/tags/v1^{{}}\"*)
    [ \"${{MOCK_COMMIT:-ok}}\" = ok ] && printf '%s\\n' '{commit}' || printf '%040d\\n' 0 ;;
  *\"rev-parse --verify refs/tags/v1\"*)
    [ \"${{MOCK_TAG_OBJECT:-ok}}\" = ok ] && printf '%s\\n' '{tag_object}' || printf '%040d\\n' 0 ;;
  *\"rev-parse --verify HEAD\"*)
    [ \"${{MOCK_COMMIT:-ok}}\" = ok ] && printf '%s\\n' '{commit}' || printf '%040d\\n' 0 ;;
  *\"verify-tag --raw refs/tags/v1\"*)
    if [ \"${{MOCK_SIGNATURE:-ok}}\" = ok ]; then
      printf '%s\\n' '[GNUPG:] VALIDSIG {signer} 2026-01-01 0 4 0 1 10 00 PRIMARY' >&2
    else
      printf '%s\\n' '[GNUPG:] BADSIG {signer} Fixture' >&2
      exit 1
    fi ;;
  *\"ls-remote {origin} refs/tags/v1 refs/tags/v1^{{}}\"*)
    case \"${{MOCK_REMOTE:-offline}}\" in
      offline) printf '%s\\n' 'fatal: unable to access: Could not resolve host' >&2; exit 128 ;;
      mismatch)
        printf '%s\\trefs/tags/v1\\n' '{tag_object}'
        printf '%040d\\trefs/tags/v1^{{}}\\n' 0 ;;
      tag-mismatch)
        printf '%040d\\trefs/tags/v1\\n' 0
        printf '%s\\trefs/tags/v1^{{}}\\n' '{commit}' ;;
      online)
        printf '%s\\trefs/tags/v1\\n' '{tag_object}'
        printf '%s\\trefs/tags/v1^{{}}\\n' '{commit}' ;;
    esac ;;
  *) printf 'unexpected git invocation: %s\\n' \"$*\" >&2; exit 90 ;;
esac
""",
    )
    executable(
        mock / "gpg",
        f"""#!/bin/sh
case \"$*\" in
  *\"--import-options show-only\"*) printf '%s\\n' 'fpr:::::::::{signer}:' ;;
  *\"--import\"*) exit 0 ;;
  *) exit 90 ;;
esac
""",
    )
    executable(mock / "timeout", "#!/bin/sh\nshift\nexec \"$@\"\n")

    base = [
        "bash", str(TAG_GATE), str(repository), origin, "v1", commit, tag_object,
        str(key), sha(key), signer,
    ]
    commands = [str(mock / "git"), str(mock / "gpg"), str(mock / "timeout")]
    poisoned_git_environment = {
        **os.environ,
        "GIT_DIR": "/definitely/not-the-fixture",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "core.repositoryformatversion",
        "GIT_CONFIG_VALUE_0": "99",
    }
    result = run(*base, "offline-only", "0", *commands, env=poisoned_git_environment)
    assert "remote=skipped" in result.stdout
    result = run(*base, "online-fallback", "0", *commands, env={**os.environ, "MOCK_REMOTE": "offline"})
    assert "remote=unavailable" in result.stdout
    run(*base, "online-fallback", "0", *commands, env={**os.environ, "MOCK_REMOTE": "mismatch"}, ok=False)
    run(*base, "online-fallback", "0", *commands, env={**os.environ, "MOCK_REMOTE": "tag-mismatch"}, ok=False)
    run(*base, "offline-only", "0", *commands, env={**os.environ, "MOCK_TAG_OBJECT": "wrong"}, ok=False)
    run(*base, "offline-only", "0", *commands, env={**os.environ, "MOCK_COMMIT": "wrong"}, ok=False)
    run(*base, "offline-only", "0", *commands, env={**os.environ, "MOCK_ORIGIN": "wrong"}, ok=False)
    run(*base, "offline-only", "0", *commands, env={**os.environ, "MOCK_SIGNATURE": "wrong"}, ok=False)


with tempfile.TemporaryDirectory(prefix="cr6608-offline-source-") as temporary:
    test_root = Path(temporary)
    feed_root = test_root / "feeds"
    tag_root = test_root / "tags"
    feed_root.mkdir()
    tag_root.mkdir()
    feed_tests(feed_root)
    tag_gate_tests(tag_root)

print("offline_source_fallback_tests=pass")
