#!/usr/bin/env python3
"""Functional and negative contracts for the history-free source kit."""

from __future__ import annotations

import hashlib
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "cr6608_source_kit.py"
EPOCH = "1787356800"
SECRET = b"DELETED_HISTORY_SECRET_MUST_NOT_SHIP"


def run(*argv: str, cwd: pathlib.Path | None = None, ok: bool = True, env=None):
    result = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if ok and result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(argv)}\n"
            f"stdout:\n{result.stdout.decode('utf-8', 'replace')}\n"
            f"stderr:\n{result.stderr.decode('utf-8', 'replace')}"
        )
    if not ok and result.returncode == 0:
        raise AssertionError(f"command unexpectedly succeeded: {' '.join(argv)}")
    return result


def git(repo: pathlib.Path, *args: str, ok: bool = True, env=None):
    return run(
        "git",
        "-c",
        "core.autocrlf=false",
        "-C",
        str(repo),
        *args,
        ok=ok,
        env=env,
    )


def write(path: pathlib.Path, content: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    path.chmod(0o755 if executable else 0o644)


def commit(
    repo: pathlib.Path, message: str, *, amend: bool = False, add_all: bool = True
) -> str:
    if add_all:
        git(repo, "add", "-A")
    env = os.environ.copy()
    env.update(
        {
            "GIT_AUTHOR_NAME": "Source Kit Contract",
            "GIT_AUTHOR_EMAIL": "contract@example.invalid",
            "GIT_AUTHOR_DATE": "2026-08-22T00:00:00+00:00",
            "GIT_COMMITTER_NAME": "Source Kit Contract",
            "GIT_COMMITTER_EMAIL": "contract@example.invalid",
            "GIT_COMMITTER_DATE": "2026-08-22T00:00:00+00:00",
        }
    )
    args = ["commit", "-q", "--no-gpg-sign", "--no-verify", "-m", message]
    if amend:
        args.insert(1, "--amend")
    git(repo, *args, env=env)
    return git(repo, "rev-parse", "HEAD").stdout.decode("ascii").strip()


def verify(repo: pathlib.Path, base: str, auth: str, *, ok: bool = True):
    return run(
        sys.executable,
        "-I",
        "-B",
        str(TOOL),
        "verify",
        "--repo",
        str(repo),
        "--kit-base",
        base,
        "--auth-fix",
        auth,
        "--product-version",
        "v78",
        "--build-epoch",
        EPOCH,
        ok=ok,
    )


def verify_bundle(
    bundle: pathlib.Path,
    clone: pathlib.Path,
    base: str,
    auth: str,
    trusted: dict[str, str],
    *,
    bundle_sha256: str | None = None,
    ok: bool = True,
    env=None,
):
    return run(
        sys.executable,
        "-I",
        "-B",
        str(TOOL),
        "verify-bundle",
        "--bundle",
        str(bundle),
        "--clone-dir",
        str(clone),
        "--kit-base",
        base,
        "--auth-fix",
        auth,
        "--product-version",
        "v78",
        "--build-epoch",
        EPOCH,
        "--expected-bundle-sha256",
        bundle_sha256 or trusted["source_kit_bundle_sha256"],
        "--expected-original-commit",
        trusted["source_kit_original_commit"],
        "--expected-original-tree",
        trusted["source_kit_original_tree"],
        "--expected-container-commit",
        trusted["source_kit_container_commit"],
        "--expected-container-tree",
        trusted["source_kit_container_tree"],
        "--expected-payload-manifest-sha256",
        trusted["source_kit_payload_manifest_sha256"],
        ok=ok,
        env=env,
    )


def key_values(output: bytes) -> dict[str, str]:
    return dict(
        line.split("=", 1)
        for line in output.decode("ascii").splitlines()
        if "=" in line
    )


def make_history_repo(root: pathlib.Path) -> tuple[pathlib.Path, str, str, str]:
    repo = root / "reviewed"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    write(repo / ".gitignore", "ignored.tmp\n")
    write(repo / "files" / "etc" / "shadow", SECRET.decode() + "\n")
    write(repo / "README.md", "reviewed source\n")
    base = commit(repo, "reviewed baseline with deleted historical secret")

    (repo / "files" / "etc" / "shadow").unlink()
    write(repo / "AUTH-FIX", "present\n")
    auth = commit(repo, "authentication fix")

    background_escape = ""
    if os.name != "nt":
        background_escape = (
            "( while [ ! -e ../../source-kit-metadata.txt ]; do sleep 0.02; done; "
            "printf 'escaped' > ../../../BACKGROUND-REPRODUCTION-CHILD ) &\n"
        )
    write(
        repo / "build.sh",
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        "[ \"${CR6608_SOURCE_TEST_ONLY:-0}\" = 1 ]\n"
        "[ -z \"${CR6608_RESCUE_REAL_EVIDENCE:-}\" ]\n"
        "[ -z \"${CR6608_BROWSER_TEST_EVIDENCE:-}\" ]\n"
        "[ -z \"${CR6608_FACTORY38_BUILD_MODE:-}\" ]\n"
        "[ -z \"${CR6608_CALLER_UNKNOWN:-}\" ]\n"
        "[ \"${CR6608_NODE_BIN:-}\" = /trusted/node ]\n"
        "[ -z \"${GIT_NAMESPACE:-}\" ]\n"
        "[ -z \"${GIT_DEFAULT_HASH:-}\" ]\n"
        "if [ -f ../../reproduction-input.bundle ]; then\n"
        "  printf 'reproduction-child-must-not-touch-final' >> ../../reproduction-input.bundle\n"
        "fi\n"
        + background_escape
        + "printf 'source_tests=pass\\n'\n",
        executable=True,
    )
    if os.name != "nt":
        os.symlink("README.md", repo / "README.link")
    git(repo, "add", "-A")
    # core.filemode is normally false on Windows, so bind the executable mode
    # in the index explicitly. This makes the negative mode-tamper case real
    # and identical on Windows and Linux.
    git(repo, "update-index", "--chmod=+x", "build.sh")
    head = commit(repo, "candidate payload", add_all=False)
    return repo, base, auth, head


def object_payloads(repo: pathlib.Path) -> list[bytes]:
    records = git(repo, "rev-list", "--objects", "--all").stdout.splitlines()
    payloads: list[bytes] = []
    for record in records:
        oid = record.split(b" ", 1)[0].decode("ascii")
        if git(repo, "cat-file", "-t", oid).stdout.strip() == b"blob":
            payloads.append(git(repo, "cat-file", "blob", oid).stdout)
    return payloads


def copy_clone(source: pathlib.Path, destination: pathlib.Path) -> pathlib.Path:
    git(source, "clone", "-q", str(source), str(destination))
    git(destination, "remote", "remove", "origin")
    return destination


def main() -> int:
    if not TOOL.is_file():
        raise AssertionError(f"missing source-kit tool: {TOOL}")
    if shutil.which("bash") is None:
        print("source_kit_contract=skip_no_bash")
        return 0
    with tempfile.TemporaryDirectory(prefix="cr6608-source-kit-contract-") as temp_name:
        temp = pathlib.Path(temp_name)
        reviewed, base, auth, head = make_history_repo(temp)
        normal = key_values(verify(reviewed, base, auth).stdout)
        assert normal["source_repository_mode"] == "reviewed-history"
        assert normal["source_product_version"] == "v78"
        assert normal["source_build_epoch"] == EPOCH
        assert normal["source_original_commit"] == head

        (reviewed / "ignored.tmp").write_text("must fail\n", encoding="utf-8")
        verify(reviewed, base, auth, ok=False)
        (reviewed / "ignored.tmp").unlink()

        output = temp / "output"
        output.mkdir()
        create_env = os.environ.copy()
        create_env["CR6608_RESCUE_REAL_EVIDENCE"] = str(
            temp / "caller-private-rescue-evidence"
        )
        create_env["CR6608_BROWSER_TEST_EVIDENCE"] = str(
            temp / "caller-private-browser-evidence"
        )
        create_env["CR6608_FACTORY38_BUILD_MODE"] = "maintenance"
        create_env["CR6608_CALLER_UNKNOWN"] = "must-not-reach-reproduction"
        create_env["CR6608_NODE_BIN"] = "/trusted/node"
        create_env["GIT_NAMESPACE"] = "caller-controlled-namespace"
        create_env["GIT_DEFAULT_HASH"] = "sha256"
        created = key_values(run(
            sys.executable,
            "-I",
            "-B",
            str(TOOL),
            "create",
            "--repo",
            str(reviewed),
            "--output-dir",
            str(output),
            "--kit-base",
            base,
            "--auth-fix",
            auth,
            "--build-epoch",
            EPOCH,
            "--product-version",
            "v78",
            env=create_env,
        ).stdout)
        if os.name != "nt":
            time.sleep(0.5)
            assert not (output / "BACKGROUND-REPRODUCTION-CHILD").exists()
        assert created["source_kit_root_commit_count"] == "1"
        assert created["source_kit_reproduction_status"] == "pass"

        expected = {
            "cr6608-source-kit.bundle",
            "cr6608-source-kit.tar.xz",
            "source-kit-reproduction.txt",
            "source-kit-identity.txt",
            "source-kit-payload.tsv",
            "source-kit-metadata.txt",
        }
        assert {path.name for path in output.iterdir()} == expected
        metadata = dict(
            line.split("=", 1)
            for line in (output / "source-kit-metadata.txt").read_text(encoding="ascii").splitlines()
        )
        for name, key in (
            ("cr6608-source-kit.bundle", "source_kit_bundle_sha256"),
            ("cr6608-source-kit.tar.xz", "source_kit_archive_sha256"),
            ("source-kit-reproduction.txt", "source_kit_reproduction_log_sha256"),
        ):
            assert hashlib.sha256((output / name).read_bytes()).hexdigest() == metadata[key]

        heads = run(
            "git", "bundle", "list-heads", str(output / "cr6608-source-kit.bundle")
        ).stdout.decode("ascii").splitlines()
        assert heads == [f"{metadata['source_kit_container_commit']} refs/heads/source-kit"]

        hostile_env = os.environ.copy()
        hostile_env["GIT_DIR"] = str(temp / "caller-controlled-git-dir")
        hostile_env["GIT_OBJECT_DIRECTORY"] = str(temp / "caller-controlled-objects")
        hostile_env["GIT_CONFIG_COUNT"] = "1"
        hostile_env["GIT_CONFIG_KEY_0"] = "core.hooksPath"
        hostile_env["GIT_CONFIG_VALUE_0"] = str(temp / "caller-controlled-hooks")
        hostile_env["GIT_NAMESPACE"] = "caller-controlled-namespace"
        hostile_env["GIT_DEFAULT_HASH"] = "sha256"
        trusted_clone = temp / "trusted-clone"
        previous_umask = os.umask(0o002) if os.name != "nt" else None
        try:
            trusted_output = key_values(
                verify_bundle(
                    output / "cr6608-source-kit.bundle",
                    trusted_clone,
                    base,
                    auth,
                    metadata,
                    env=hostile_env,
                ).stdout
            )
        finally:
            if previous_umask is not None:
                os.umask(previous_umask)
        assert trusted_output["source_bundle_sha256"] == metadata["source_kit_bundle_sha256"]
        assert trusted_output["source_verified_clone"] == str(trusted_clone.resolve())
        assert not git(trusted_clone, "remote").stdout.strip()
        assert not (trusted_clone / ".git" / "objects" / "info" / "alternates").exists()
        if os.name != "nt":
            assert stat.S_IMODE((trusted_clone / "README.md").stat().st_mode) == 0o644
            assert stat.S_IMODE((trusted_clone / "build.sh").stat().st_mode) == 0o755

        canonical_output = temp / "canonical-output"
        canonical_output.mkdir()
        canonical_created = key_values(
            run(
                sys.executable,
                "-I",
                "-B",
                str(TOOL),
                "create",
                "--repo",
                str(trusted_clone),
                "--output-dir",
                str(canonical_output),
                "--kit-base",
                base,
                "--auth-fix",
                auth,
                "--build-epoch",
                EPOCH,
                "--product-version",
                "v78",
                "--canonical-bundle",
                str(output / "cr6608-source-kit.bundle"),
                "--expected-canonical-bundle-sha256",
                metadata["source_kit_bundle_sha256"],
                env=create_env,
            ).stdout
        )
        assert canonical_created["source_kit_bundle_role"] == "externally-trusted-build-input"
        assert canonical_created["source_kit_bundle_sha256"] == metadata["source_kit_bundle_sha256"]
        assert (
            (canonical_output / "cr6608-source-kit.bundle").read_bytes()
            == (output / "cr6608-source-kit.bundle").read_bytes()
        )

        hash_tamper = temp / "hash-tamper.bundle"
        shutil.copyfile(output / "cr6608-source-kit.bundle", hash_tamper)
        with hash_tamper.open("ab") as handle:
            handle.write(b"not-a-trusted-bundle")
        rejected_hash = verify_bundle(
            hash_tamper,
            temp / "hash-tamper-clone",
            base,
            auth,
            metadata,
            ok=False,
        )
        assert b"SHA-256 differs" in rejected_hash.stderr

        clone = temp / "clone"
        run(
            "git",
            "-c",
            "core.autocrlf=false",
            "clone",
            "-q",
            "--branch",
            "source-kit",
            str(output / "cr6608-source-kit.bundle"),
            str(clone),
        )
        assert git(clone, "rev-list", "--count", "--all").stdout.strip() == b"1"
        assert git(clone, "rev-list", "--parents", "-n", "1", "HEAD").stdout.decode().split() == [
            metadata["source_kit_container_commit"]
        ]
        sanitized = key_values(verify(clone, base, auth).stdout)
        assert sanitized["source_repository_mode"] == "sanitized-source-kit"
        assert sanitized["source_original_commit"] == head
        assert all(SECRET not in payload for payload in object_payloads(clone))
        assert not (clone / "files" / "etc" / "shadow").exists()

        unreachable = copy_clone(clone, temp / "unreachable-object")
        orphan = temp / "unreachable-object-payload"
        write(orphan, "must never be packed\n")
        git(unreachable, "hash-object", "-w", str(orphan))
        unreachable_result = verify(unreachable, base, auth, ok=False)
        assert b"object closure is not exact" in unreachable_result.stderr

        byte_tamper = copy_clone(clone, temp / "byte-tamper")
        write(byte_tamper / "README.md", "tampered byte\n")
        commit(byte_tamper, "tamper byte", amend=True)
        verify(byte_tamper, base, auth, ok=False)

        mode_tamper = copy_clone(clone, temp / "mode-tamper")
        git(mode_tamper, "update-index", "--chmod=-x", "build.sh")
        commit(mode_tamper, "tamper mode", amend=True, add_all=False)
        verify(mode_tamper, base, auth, ok=False)

        manifest_tamper = copy_clone(clone, temp / "manifest-tamper")
        with (manifest_tamper / ".cr6608-source-payload.tsv").open("a", encoding="utf-8") as handle:
            handle.write("source-file\t100644\t" + "0" * 64 + "\tghost\n")
        commit(manifest_tamper, "tamper manifest", amend=True)
        verify(manifest_tamper, base, auth, ok=False)

        identity_tamper = copy_clone(clone, temp / "identity-tamper")
        identity_path = identity_tamper / ".cr6608-source-identity"
        identity_text = identity_path.read_text(encoding="utf-8")
        identity_path.write_text(
            identity_text.replace(
                f"original_tree={metadata['source_kit_original_tree']}",
                "original_tree=" + "0" * 40,
            ),
            encoding="utf-8",
            newline="\n",
        )
        commit(identity_tamper, "tamper identity", amend=True)
        verify(identity_tamper, base, auth, ok=False)

        history_tamper = copy_clone(clone, temp / "history-tamper")
        write(history_tamper / "EXTRA", "second commit\n")
        commit(history_tamper, "forbidden second commit")
        verify(history_tamper, base, auth, ok=False)

        if os.name != "nt":
            link_tamper = copy_clone(clone, temp / "link-tamper")
            link = link_tamper / "README.link"
            link.unlink()
            os.symlink("AUTH-FIX", link)
            commit(link_tamper, "tamper symlink", amend=True)
            verify(link_tamper, base, auth, ok=False)

        forged_reviewed = copy_clone(reviewed, temp / "forged-reviewed")
        write(forged_reviewed / "README.md", "self-consistent forged descendant\n")
        forged_head = commit(forged_reviewed, "forged descendant payload")
        assert forged_head != head
        forged_output = temp / "forged-output"
        forged_output.mkdir()
        forged_created = key_values(
            run(
                sys.executable,
                "-I",
                "-B",
                str(TOOL),
                "create",
                "--repo",
                str(forged_reviewed),
                "--output-dir",
                str(forged_output),
                "--kit-base",
                base,
                "--auth-fix",
                auth,
                "--build-epoch",
                EPOCH,
                "--product-version",
                "v78",
                env=create_env,
            ).stdout
        )
        forged_clone = temp / "forged-generic-clone"
        run(
            "git",
            "-c",
            "core.autocrlf=false",
            "clone",
            "-q",
            "--branch",
            "source-kit",
            str(forged_output / "cr6608-source-kit.bundle"),
            str(forged_clone),
        )
        forged_generic = key_values(verify(forged_clone, base, auth).stdout)
        assert forged_generic["source_original_commit"] == forged_head
        forged_anchor = dict(metadata)
        forged_anchor["source_kit_container_commit"] = forged_created[
            "source_kit_container_commit"
        ]
        forged_anchor["source_kit_container_tree"] = forged_created[
            "source_kit_container_tree"
        ]
        forged_rejected = verify_bundle(
            forged_output / "cr6608-source-kit.bundle",
            temp / "forged-trusted-clone",
            base,
            auth,
            forged_anchor,
            bundle_sha256=forged_created["source_kit_bundle_sha256"],
            ok=False,
        )
        assert b"differs from the trusted value" in forged_rejected.stderr

    print("source_kit_contract=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
