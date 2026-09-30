"""Contracts for the activation helper's observable file updates."""

from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

SCRIPT = Path(sys.argv.pop(1))


class ConfigureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project"
        self.root.mkdir()
        self.policy = Path(self.temporary.name) / "policy.toml"
        self.policy.write_text('[rust]\nunused_results = "warn"\n[clippy]\nunwrap_used = "warn"\n')

    def write(self, path, text):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run_configure(self, *arguments, expected=0):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root),
             "--lints", str(self.policy), *arguments],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_package_policy_updates_preserve_package_data_and_do_not_touch_current_files(self):
        manifest = self.write("Cargo.toml", '# Keep this comment.\n[package]\nname = "example"\nversion = "0.1.0"\n[dependencies]\nserde = "1"\n')
        before = manifest.read_bytes()
        self.run_configure("--check", expected=1)
        self.assertEqual(manifest.read_bytes(), before)
        self.run_configure()
        document = tomllib.loads(manifest.read_text())
        self.assertEqual(document["package"]["name"], "example")
        self.assertEqual(document["dependencies"], {"serde": "1"})
        self.assertIn("# Keep this comment.", manifest.read_text())
        self.assertEqual(document["lints"]["clippy"]["unwrap_used"], "warn")
        modified = manifest.stat().st_mtime_ns
        self.run_configure()
        self.run_configure("--check")
        self.assertEqual(manifest.stat().st_mtime_ns, modified)

        # Removing a house rule must remove its generated Cargo setting too.
        self.policy.write_text('[rust]\nunused_results = "deny"\n')
        self.run_configure()
        updated = tomllib.loads(manifest.read_text())["lints"]
        self.assertEqual(updated["rust"]["unused_results"], "deny")
        self.assertNotIn("clippy", updated)

    def test_workspace_enables_glob_and_implicit_members_without_modifying_excluded_packages(self):
        manifest = self.write("Cargo.toml", '[workspace]\nmembers = ["crates/*"]\nexclude = ["crates/excluded"]\n[workspace.dependencies]\nhelper = { path = "helper" }\n')
        first = self.write("crates/first/Cargo.toml", '[package]\nname = "first"\nversion = "0.1.0"\n[dependencies]\nhelper.workspace = true\n')
        helper = self.write("helper/Cargo.toml", '[package]\nname = "helper"\nversion = "0.1.0"\n')
        excluded = self.write("crates/excluded/Cargo.toml", '[package]\nname = "excluded"\nversion = "0.1.0"\n')
        excluded_before = excluded.read_bytes()
        self.run_configure()
        root = tomllib.loads(manifest.read_text())
        self.assertEqual(root["workspace"]["lints"]["rust"]["unused_results"], "warn")
        for member in [first, helper]:
            self.assertEqual(tomllib.loads(member.read_text())["lints"], {"workspace": True})
        self.assertEqual(excluded.read_bytes(), excluded_before)
        self.run_configure("--check")

    def test_incompatible_member_lints_fail_before_any_manifest_is_written(self):
        manifest = self.write("Cargo.toml", '[workspace]\nmembers = ["member"]\n')
        member = self.write("member/Cargo.toml", '[package]\nname = "member"\nversion = "0.1.0"\n[lints.rust]\nunsafe_code = "forbid"\n')
        originals = {path: path.read_bytes() for path in [manifest, member]}
        result = self.run_configure(expected=2)
        self.assertIn("defines its own lint policy", result.stderr)
        for path, original in originals.items():
            self.assertEqual(path.read_bytes(), original)

    def test_symlinked_member_outside_workspace_is_rejected_without_writing(self):
        manifest = self.write("Cargo.toml", '[workspace]\nmembers = ["outside"]\n')
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        external = outside / "Cargo.toml"
        external.write_text('[package]\nname = "outside"\nversion = "0.1.0"\n')
        (self.root / "outside").symlink_to(outside, target_is_directory=True)
        before = {path: path.read_bytes() for path in [manifest, external]}
        self.run_configure(expected=2)
        for path, original in before.items():
            self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
