#!/usr/bin/env python3
"""Apply shared Cargo lint policy during devenv activation."""

import argparse
from collections.abc import Mapping
import fnmatch
import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def read(path):
    return tomlkit.parse(path.read_text(encoding="utf-8"))


def workspace_manifests(root, document):
    workspace = document["workspace"]
    excluded = workspace.get("exclude", [])
    pending = [root / "Cargo.toml"]
    for pattern in workspace.get("members", []):
        pending.extend(path / "Cargo.toml" for path in root.glob(pattern))

    seen = set()
    manifests = {}
    while pending:
        candidate = pending.pop()
        path = candidate.resolve()
        if not path.is_relative_to(root):
            raise ValueError(f"workspace member is outside the project: {candidate}")
        if path in seen:
            continue
        seen.add(path)
        relative = path.parent.relative_to(root).as_posix()
        if any(fnmatch.fnmatchcase(relative, pattern) for pattern in excluded):
            continue
        member = document if path == root / "Cargo.toml" else read(path)
        if path != root / "Cargo.toml" and "workspace" in member:
            raise ValueError(f"nested workspace cannot inherit these lints: {path}")
        if "package" in member:
            manifests[path] = member

        # Cargo automatically includes path dependencies inside the workspace.
        sections = [member, *member.get("target", {}).values()]
        for section in sections:
            for kind in ["dependencies", "dev-dependencies", "build-dependencies"]:
                for name, dependency in section.get(kind, {}).items():
                    if not isinstance(dependency, Mapping):
                        continue
                    base = path.parent
                    if dependency.get("workspace"):
                        dependency = workspace.get("dependencies", {}).get(name, {})
                        base = root
                    if isinstance(dependency, Mapping) and "path" in dependency:
                        dependency_path = (base / dependency["path"]).resolve()
                        if dependency_path.is_relative_to(root):
                            pending.append(dependency_path / "Cargo.toml")
    return manifests


def atomic_write(path, content):
    mode = path.stat().st_mode & 0o777
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent,
            prefix=f".{path.name}.rust-style-", delete=False,
        ) as output:
            temporary = Path(output.name)
            output.write(content)
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--lints", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    path = root / "Cargo.toml"
    if path.is_symlink():
        raise ValueError("Cargo.toml must be a regular file, rather than a symlink")
    document = read(path)
    policy = read(args.lints).unwrap()
    outputs = {}

    if "workspace" in document:
        manifests = workspace_manifests(root, document)
        # Validate all members before writing any file. Explicit member lint
        # policies cannot be combined with Cargo's workspace inheritance.
        for member_path, member in manifests.items():
            current = member.get("lints", {})
            if member_path != path and current and current != {"workspace": True}:
                raise ValueError(
                    f"{member_path} defines its own lint policy; move shared exceptions "
                    "to .config/rust-style.toml and use [lints] workspace = true"
                )
        document["workspace"]["lints"] = policy
        for member_path, member in manifests.items():
            member["lints"] = {"workspace": True}
            outputs[member_path] = tomlkit.dumps(member)
    elif "package" in document:
        document["lints"] = policy
    else:
        raise ValueError("Cargo.toml must define a package or workspace")
    outputs[path] = tomlkit.dumps(document)

    changed = {
        candidate: content for candidate, content in outputs.items()
        if candidate.read_text(encoding="utf-8") != content
    }
    if args.check:
        return int(bool(changed))
    for candidate, content in changed.items():
        atomic_write(candidate, content)
        print(f"rust-style: configured {candidate.relative_to(root)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, tomlkit.exceptions.TOMLKitError) as error:
        print(f"rust-style: {error}", file=sys.stderr)
        sys.exit(2)
