# Rules for an agent using this tool

These are hard rules, not preferences. Each exists because breaking it cost real
time on a real machine.

## Never install through Homebrew without asking

**Never run `brew install`, `brew upgrade` or `brew reinstall` without explicit
permission.** On a platform Homebrew no longer bottles, each of those is a build
from source. Small libraries take minutes. Anything pulling `rust`, `llvm` or
`lld` takes hours and pegs every core — `HOMEBREW_MAKE_JOBS` does not apply to
rust's bootstrap or to cmake-driven builds.

Before proposing any package operation, run `upgrade-vendor-packages --preflight`.
It reports exactly what would be built from source and flags heavy toolchains.

## Order of preference

1. **Vendor binary** — add it to `bin/upgrade-vendor-packages.sh` rather than
   installing it through any package manager. That means a `latest_<tool>`, an
   `install_<tool>`, an entry in the architecture map, and the name in
   `ALL_TOOLS`.
2. **MacPorts, always `sudo port -b install`.** `-b` is binary-only and aborts
   instead of compiling when no archive matches. Never omit it. Run
   `sudo port selfupdate` first: a stale ports tree asks for a version the mirror
   does not have, and that alone sends the port off to compile.
3. **Homebrew, last resort, with explicit approval**, after stating what will be
   built and roughly how long it takes.

## Verify, do not assume

- Check MacPorts archives by **exact** name, never "is there any archive". See
  [docs/GOTCHAS.md](docs/GOTCHAS.md).
- Do not use `brew uses --installed`: it times out and returns empty output,
  which reads as "nothing depends on this".
- Casks declare formula dependencies separately (`depends_on.formula`); a
  formula-only graph cannot see them.
- Read a cask's `artifacts` before uninstalling it — `zap` stanzas delete data.
- After migrating a package, **run** the replacement before uninstalling the old
  one. `command -v` is not verification.

## This shell is zsh

zsh does not word-split unquoted parameter expansions: `for f in $LIST` iterates
once with the whole string as a single item, and the loop reports success having
done nothing. Wrap loops in `bash -c '...'`. A non-matching glob aborts the whole
command (`no matches found`) instead of passing through — guard with `(N)`.

## Keep the embedded python at 3.9

Reports run through Apple's `/usr/bin/python3`. Using 3.10+ syntax breaks the
tool on exactly the old machines that need it. Run `tests/py39-compat.sh` after
touching any embedded block.

## Machine-specific values go in the config

`ALL_TOOLS` and `MAJOR_ONLY_CASKS` belong in `config/tools.conf`, not in the
script. Do not hardcode a prefix either: Homebrew's differs by architecture and
MacPorts' is set at build time.
