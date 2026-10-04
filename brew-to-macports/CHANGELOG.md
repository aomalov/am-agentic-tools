# Changelog

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
