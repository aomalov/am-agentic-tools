# Changelog

## Unreleased

### Added

- `bun` as a vendor tool, installed from the upstream `darwin-x64` zip. Its
  brew formula compiles through zig and llvm on Intel. The release tag is
  `bun-v<version>`, and the zip holds `bun-darwin-<arch>/bun`, not a bare
  binary. The version policy is `always`, because bun stays on 1.x for months
  and its fixes ship as patches.

### Security

- ffmpeg is installed only after its `.sig` verifies against the evermeet.cx
  signing key, which is pinned in `keys/` (fingerprint
  `20F6EA3E0CFD6B4C53447A73476C4B611A660874`, cross-checked with
  keys.openpgp.org). Verification uses only that key file and accepts only a
  signature whose primary key matches the fingerprint. Without gpg/gpgv, the
  install refuses to proceed rather than skipping the check. evermeet.cx now
  redirects every download to an unannounced third-party host, so the signature
  is what links the binary to its author.

### Fixed

- A failed ffmpeg download now names the host the redirect leads to. Before,
  `curl: (28)` looked like a local network problem, while the mirror was down.
- `install_ffmpeg` left its temporary directory behind on every failure path.
- A dead vendor host took a full minute to time out on every run, because
  `fetch` had only `--max-time 60`. It now also has `--connect-timeout 15`, so an
  unreachable host is caught in seconds while a slow download keeps its minute.
- An unreachable vendor download is now a skip, not a failure: a yellow line,
  `vendor source unreachable, will retry` in the summary, and exit code 0. The
  old version stays, and the next run tries again. Real install failures,
  including a bad signature, still print ✗ and exit 1.

## 0.1.0 — 2026-10-04

First published version, extracted from a complete migration off Homebrew.

### Added

- `--bootstrap`: read-only inventory of Homebrew that sorts every installed
  formula into the three migration routes (vendor binary / MacPorts / stays),
  flagging formulae with no bottle. Running with no arguments on a machine with
  no vendor state sends you here instead of acting blindly.
- `brew_orphan_watch`: holder graph across both formulae and cask
  `depends_on.formula`, naming the root that only a cask holds and warning about
  installed formulae that are neither bottled nor pinned.
- `brew_preflight`: forecasts which pending upgrades pour a bottle and which
  compile, following build dependencies to flag heavy toolchains.
- MacPorts service: `selfupdate`, `-b upgrade outdated`, inactive-version prune,
  and a self-rebuilding watchlist of ports whose Intel archive has appeared.
- Vendor installers for a starting set of common CLI tools. Two of them carry
  special handling worth noting: `resvg` ships an `rsvg-convert` compatibility
  shim so callers expecting librsvg keep working, and `gcloud` upgrades in place
  through its own component updater instead of being re-extracted, which would
  drop installed components.
- Major-only cask policy: unpin, upgrade, pin again — for apps that ship a
  full-size installer on almost every patch release.
- Translated output. Message catalogues in `locale/`, read by both the bash and
  the python halves from the same files, so a string exists once per language.
  Language comes from `BREW2MP_LANG` or the usual locale variables; English is
  the base layer, so an untranslated key falls back instead of blanking a line.
  No gettext and no bash 4 required. Ships English and Russian.
- `--wheels <pkg>`: resolves a package closure with wheels only and reports what
  pip would otherwise compile. Plus a python-wheel section in the preflight that
  checks whether `PIP_ONLY_BINARY` is in effect and whether `pip3` belongs to the
  same interpreter `python3` points at — it does not, on the machine this was
  written on, and that silently installs packages into the wrong python.
- Thin agent orchestrator in `skills/brew-to-macports/`.
- `config/tools.conf.example`, `install.sh`, `docs/GOTCHAS.md`, `AGENTS.md`,
  and two tests: `tests/py39-compat.sh` and `tests/locale-check.sh`.

### Fixed

- Brew cache payload was selected alphabetically, so after a macOS upgrade the
  payload of a **different OS** could be read and every bottle verdict computed
  against the wrong platform. Now selected by mtime, with `bottle_tag` shown.
- MacPorts archive check matched any archive for a port rather than the exact
  expected name, once reporting `tesseract` as ready when the ports tree wanted a
  version the mirror did not have.
- MacPorts prefix was hardcoded to `/opt/local`; now derived from the located
  `port` binary.
- `ALL_TOOLS` and `MAJOR_ONLY_CASKS` were baked into the script; now config.
- Empty watchlist left stale cached state on screen, printing a week-old verdict
  as current.
- In the holder report, a comprehension variable was named `t`, shadowing the
  translate function inside it.
