# Rust style

Shared Rust tooling: Clippy, rustfmt, nextest, and
[Mr. Boxington](https://mr-boxington.jdx.dev) caching.

`devenv.nix`:

```nix
{ inputs, ... }: { imports = [ inputs.rust-style.devenvModules.default ]; }
```

`devenv.yaml` (requires GitHub SSH access to this private repo):

```yaml
inputs:
  rust-style:
    url: git+ssh://git@github.com/cschmatzler/rust
  nixpkgs:
    follows: rust-style/nixpkgs
```

Enter `devenv shell` and invoke Cargo directly. The shell wraps `cargo` in
Mr. Boxington and forwards every command and argument unchanged.
Use `cargo nextest run` when you want nextest.

Blaze is installed and enabled through mbx (`MBX_BLAZE=1`). Development
`cargo build`, `run`, `test`, and `check` commands use its experimental fast
rebuilds with Blaze's pinned nightly toolchain. Release builds, explicit profiles,
and other unsupported invocations continue through mbx with the project toolchain.
Set `MBX_BLAZE=0` to use the project toolchain for all commands.

```bash
cargo build
cargo test --workspace
cargo nextest run --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all -- --check
```

Activation overwrites `rustfmt.toml`, `clippy.toml`, and `.config/nextest.toml`;
ignore those three files in Git. Commit `devenv.lock`.

Update with `devenv update rust-style`. The next activation applies the new rules.
