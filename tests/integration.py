#!/usr/bin/env python3
"""Exercise the real flake import, devenv gate, and Cargo cache in isolation."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib


SOURCE = '''/// Return the answer.
///
/// ```
/// assert_eq!(style_consumer::answer(), 42);
/// ```
pub fn answer() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn answers_the_question() {
        assert_eq!(super::answer(), 42);
    }
}
'''

UNWRAP_SOURCE = SOURCE.replace(
    "#[cfg(test)]",
    'pub fn risky(value: Option<u32>) -> u32 {\n    value.unwrap()\n}\n\n#[cfg(test)]',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--style-ref", help="Optional remote flake reference to validate")
    args = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="rust-style-consumer-") as directory:
        temporary = Path(directory)
        root = temporary / "workspace"
        root.mkdir()
        shutil.copy(repository / "template/devenv.nix", root / "devenv.nix")
        reference = args.style_ref or f"path:{repository}"
        (root / "devenv.yaml").write_text(
            f"inputs:\n  rust-style:\n    url: {reference}\n"
            "  nixpkgs:\n    follows: rust-style/nixpkgs\n"
        )
        (root / "Cargo.toml").write_text(
            '[workspace]\nmembers = ["crates/example"]\nresolver = "3"\n'
        )
        crate = root / "crates/example"
        (crate / "src").mkdir(parents=True)
        (crate / "Cargo.toml").write_text(
            '[package]\nname = "style-consumer"\nversion = "0.1.0"\nedition = "2024"\n'
        )
        source = crate / "src/lib.rs"
        source.write_text(SOURCE)
        environment = os.environ.copy()
        environment.update(
            DEVENV_TUI="false", MBX_CACHE_DIR=str(temporary / "cache"),
            MBX_TARGET_VIEWS="false", MBX_INCREMENTAL="0", MBX_SUMMARY="short",
        )

        def run(*command, expected_failure=None):
            print(f"Running: {' '.join(command)}", flush=True)
            result = subprocess.run(
                command, cwd=root, env=environment,
                capture_output=True, text=True, check=False,
            )
            output = result.stdout + result.stderr
            if expected_failure is None:
                if result.returncode != 0:
                    raise RuntimeError(output)
            elif result.returncode == 0 or expected_failure not in output:
                raise RuntimeError(f"Expected failure containing {expected_failure!r}:\n{output}")
            print(output[-2500:], flush=True)
            return output

        # First entry must configure the workspace before running its gate.
        run("devenv", "test")
        run("devenv", "shell", "cargo", "--version")
        metadata = run("devenv", "--quiet", "shell", "cargo", "metadata",
                       "--offline", "--no-deps", "--format-version", "1")
        # Devenv logs go to stderr; locate Cargo's JSON document in the combined output.
        line = next(line for line in metadata.splitlines() if line.startswith('{"packages"'))
        assert len(json.loads(line)["workspace_members"]) == 1
        root_manifest = tomllib.loads((root / "Cargo.toml").read_text())
        member_manifest = tomllib.loads((crate / "Cargo.toml").read_text())
        assert root_manifest["workspace"]["lints"]["clippy"]["unwrap_used"] == "warn"
        assert member_manifest["lints"] == {"workspace": True}
        assert (root / "rustfmt.toml").is_file()
        assert (root / "clippy.toml").is_file()
        assert not (root / "clippy.toml").is_symlink()

        # Warming the same target would only test Cargo freshness. Use two empty targets.
        first = temporary / "target-first"
        second = temporary / "target-second"
        run("devenv", "shell", "cargo", "build", "--workspace", "--target-dir", str(first))
        cache_output = run("devenv", "shell", "cargo", "build", "--workspace",
                           "--target-dir", str(second))
        hits = re.search(r"mbx\[cache\]:\s+(\d+) hits", cache_output)
        if hits is None or int(hits.group(1)) == 0:
            explanation = run("devenv", "shell", "mbx", "explain", "--last")
            raise RuntimeError(f"The second fresh build reported no mbx hits:\n{explanation}")
        print(f"Verified {hits.group(1)} actual mbx cache hits in a fresh target.", flush=True)

        # Failed nextest runs must not be hidden by a later successful doctest run.
        source.write_text(SOURCE.replace("super::answer(), 42", "super::answer(), 0"))
        run("devenv", "test", expected_failure="answers_the_question")

        # A doctest-only failure must also fail the same gate.
        source.write_text(SOURCE.replace("style_consumer::answer(), 42", "style_consumer::answer(), 0"))
        run("devenv", "test", expected_failure="Doc-tests")

        # The lint gate catches production unwraps under the shared policy.
        source.write_text(UNWRAP_SOURCE)
        run("devenv", "shell", "lint", expected_failure="unwrap")

        # Formatter checks fail without mutating the offending source.
        source.write_text(SOURCE.replace("pub fn answer() -> u32 {\n    42\n}", "pub fn answer()->u32{42}"))
        malformed = source.read_bytes()
        run("devenv", "test", expected_failure="Diff in")
        assert source.read_bytes() == malformed

        # Exceptions live in data, while the original one-line import remains sufficient.
        (root / ".config").mkdir()
        (root / ".config/rust-style.toml").write_text('[lints.clippy]\nunwrap_used = "allow"\n')
        source.write_text(UNWRAP_SOURCE)
        run("devenv", "shell", "lint")
        print("Real consumer activation, test/lint/format failures, overrides, and cache reuse passed.", flush=True)


if __name__ == "__main__":
    main()
