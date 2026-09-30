# Rust style

Shared Rust tooling: Clippy, rustfmt, nextest, doctests, and
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

Use devenv 2.4+. `devenv shell` provides `fmt`, `lint`, `rust-test`, and `check`.
`devenv test` runs the full check. Ordinary Cargo builds use Mr. Boxington.

Activation overwrites `rustfmt.toml` and `clippy.toml`; ignore those two files
in Git. `lint` applies the shared lint rules. Nextest overrides go in
`.config/nextest.toml`. Commit `devenv.lock`.

Update with `devenv update rust-style`. The next activation applies the new rules.
