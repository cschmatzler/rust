# Rust house style

A private flake for the Rust tools, lint policy, formatting, tests, and compiler
cache shared by `cschmatzler` projects. Consuming projects only need one line of
Nix. Configuration is applied automatically when devenv activates.

## Adopt it

Use Nix with flakes enabled, devenv 2.4 or newer, and GitHub SSH access to this
private repository. In an existing Cargo project, create `devenv.nix`:

```nix
{ inputs, ... }: { imports = [ inputs.rust-style.devenvModules.default ]; }
```

Add the shared input to `devenv.yaml`:

```yaml
inputs:
  rust-style:
    url: git+ssh://git@github.com/cschmatzler/rust
  nixpkgs:
    follows: rust-style/nixpkgs
```

Alternatively, scaffold these files with:

```sh
nix flake init --template git+ssh://git@github.com/cschmatzler/rust
```

The SSH reference uses your existing GitHub SSH credentials. A
`github:cschmatzler/rust` reference also works when Nix has a GitHub access token
with access to the private repo. Keep credentials outside tracked files.

For automatic activation through direnv, the template includes `.envrc`:

```sh
eval "$(devenv direnvrc)"
use devenv
```

Add `/rustfmt.toml`, `/clippy.toml`, `/.devenv/`, and `/.direnv/` to the project's
`.gitignore`. The formatter and Clippy files are managed copies, refreshed on
activation. Move existing project exceptions to `.config/rust-style.toml`
before adopting: these two files are overwritten by the shared policy.
Commit `devenv.lock` and the Cargo manifest changes produced by initial activation.

## Run the tools

```sh
devenv shell
fmt                       # Format every workspace crate.
lint                      # Clippy across the workspace and all targets.
rust-test                 # Nextest, followed by Cargo doctests.
check                     # Formatting check, lint, and all tests.
cargo build               # Ordinary Cargo commands use Mr. Boxington too.
```

`rust-test` avoids the shell's built-in `test` command. Outside an interactive
shell, use `devenv shell lint`, `devenv shell cargo build`, or `devenv test`.
`devenv test` activates the environment and runs `check`, including automatic
configuration. CI selects nextest's `ci` profile when `CI` is set.

## Shared defaults

- **Rust:** 1.98.1 with Clippy, rustfmt, rust-analyzer, Rust sources, and LLVM tools.
  An existing project `rust-toolchain.toml` keeps its channel, profile, targets,
  and extra components; the required house-style components are added.
- **Lint policy:** Rust warnings and a curated Clippy set, including unsafe-code
  documentation, locks held across await, panic paths, unwrap, and expect.
  `lint` treats warnings as errors. Unwrap, expect, and panic are allowed in tests.
- **Formatting:** stable rustfmt options, the 2024 style edition, Unix newlines,
  and shorthand fields and try expressions.
- **Tests:** nextest, zero retries, a three-minute slow-test limit, all tests run
  after failures in CI, and a JUnit report in the nextest output directory.
  Doctests always run separately through Cargo.
- **Build cache:** [Mr. Boxington](https://mr-boxington.jdx.dev), pinned to 1.21.0
  using verified release archive hashes. The devenv Cargo shim enables local
  shared caching without running `mbx setup` or changing global configuration.
  Existing compiler wrappers are left for mbx to chain or bypass according to
  its compatibility rules. Remote cache credentials remain machine/CI settings.
  Cargo uses its native linker selection: mbx 1.21 skips library caching when
  devenv's explicit Clang linker is enabled.
- **Other tools:** cargo-llvm-cov, pkg-config, and OpenSSL are available.

Cargo gets the lint rules in its native manifest tables. Workspaces receive
`[workspace.lints]`, and their members receive `[lints] workspace = true`.
Single-package projects receive `[lints]`. These tables are managed by the shared
policy, including removal of rules deleted from that policy; the remaining
manifest data and comments are preserved. Explicit lint tables on member crates
cause activation to stop before any manifests are written: consolidate shared
exceptions in the override file first. Workspace members must be inside the
project directory. Excluded packages are left alone.

Supported platforms: Linux x86-64, Linux ARM64, and macOS Apple Silicon.

## Project exceptions

The import stays one line. Optional project exceptions go in
`.config/rust-style.toml`:

```toml
[rustfmt]
max_width = 120

[lints.clippy]
unwrap_used = "allow"

[cargo]
features = ["postgres"]
# Alternatively: all-features = true
# Or: no-default-features = true
```

The `clippy` table overrides Clippy parameters, while `lints.rust` and
`lints.clippy` select lint levels. Each override replaces that setting from the
shared defaults. Cargo feature settings apply to lint, nextest, and doctests.
If a `Cargo.lock` exists, those commands use `--locked`.

Nextest exceptions remain in the standard `.config/nextest.toml`; it takes
precedence over the shared tool configuration for corresponding profile settings.

## Update the style

```sh
devenv update rust-style
```

The next environment activation applies the new configuration automatically.
Review and commit the updated `devenv.lock` and Cargo lint tables. There is no
manual sync command in consuming projects.

## Validate this repository

```sh
nix flake check
python3 tests/integration.py
```

The flake checks the configuration helper's file-update contracts. Integration
validation imports the actual module into a temporary Cargo workspace, runs the
gate through devenv, checks failure propagation, and measures actual mbx cache
hits across two fresh target directories. It leaves existing projects and
global configuration alone. CI runs both checks.
