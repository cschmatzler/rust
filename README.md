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

```bash
cargo build
cargo test --workspace
cargo nextest run --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all -- --check
```

Activation overwrites `rustfmt.toml` and `clippy.toml`; ignore those two files
in Git. Nextest overrides go in
`.config/nextest.toml`. Commit `devenv.lock`.

Update with `devenv update rust-style`. The next activation applies the new rules.
