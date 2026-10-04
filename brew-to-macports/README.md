# brew-to-macports

Get off Homebrew on a Mac where Homebrew no longer ships bottles, so every
`brew install` compiles from source.

Homebrew dropped Intel x86_64 to Tier 3 and stopped building bottles for it.
On such a machine a routine upgrade is not a download — it is a build. A small
library costs minutes; anything that pulls `rust`, `llvm` or `lld` costs hours
and pegs every core, and `HOMEBREW_MAKE_JOBS` does not apply to rust's bootstrap
or to cmake-driven builds. Seen in practice: when `librsvg` 2.63.0 lost its Intel bottle, Homebrew pulled
rust in behind it and the machine was unusable for the better part of an hour.

The same pressure hits any Mac whose macOS has aged out of Homebrew's bottle
matrix, Intel or not.

## The algorithm

For every package, in this order, moving on only when the step above fails:

1. **Vendor binary.** The official build from the project itself. No compiler,
   no root. If the project publishes a `darwin/amd64` (or arm64) archive, that
   is the answer.
2. **MacPorts, always with `-b`.** `-b` is binary-only: a port with no archive
   for this exact platform is skipped instead of compiled.
3. **Homebrew — last resort**, and only after saying out loud what will be
   built from source and roughly how long it takes.

The tool computes the facts for all three steps. A human makes the calls.

## Quick start

```sh
./install.sh                              # symlinks the script, installs the skill
upgrade-vendor-packages --bootstrap       # changes nothing; shows what goes where
```

`--bootstrap` inventories Homebrew and sorts every installed formula into the
three routes above, flagging the ones that have no bottle — those are what the
next `brew upgrade` will compile. Then migrate one package at a time, verify the
replacement actually runs, and only then `brew uninstall`.

Running the script with no arguments on a machine that has no vendor state yet
sends you to `--bootstrap` rather than acting blindly.

## Modes

| mode | what it does |
|---|---|
| *(no args)* | install and upgrade everything: vendor binaries, major-only casks, brew preflight, MacPorts upgrade, archive watch |
| `--bootstrap` | new machine: inventory and three-way migration plan, read-only |
| `--check` | report only, change nothing |
| `--preflight` | Homebrew only: what would be built from source, and who still holds which formula |
| `--macports` | deep check of MacPorts archive readiness, with per-package migration commands |
| `--only gh,go` | restrict to these tools |
| `--include-patch` | take patch releases too (default policy is MAJOR/MINOR) |
| `--rollback node` | go back to the previous version |
| `--list` | what is installed now |

## How it decides

Bottles are read from Homebrew's **own** cache — the same file brew consults to
decide between pouring and building:

```
$(brew --cache)/api/internal/packages.<tag>.jws.json.payload
```

A formula with no `bottle_checksum` there will be built from source, full stop.

MacPorts archives are checked by **exact** name, not "is there any archive":

```
<port>-<version>_<revision><+default variants>.<darwin_N|darwin_any|any_any>.<arch|noarch>.tbz2
```

Anything looser gives false confidence. See [docs/GOTCHAS.md](docs/GOTCHAS.md) —
every entry there is a mistake this tool made once and now guards against.

## Language

Output is translated through message catalogues in `locale/`. The language is
picked from `BREW2MP_LANG`, falling back to `LC_ALL` / `LC_MESSAGES` / `LANG`,
then English:

```sh
BREW2MP_LANG=ru upgrade-vendor-packages --check
```

English is always loaded first and every other language is layered on top, so a
key a translation has not covered renders in English rather than as an empty
line — a partial catalogue is a usable catalogue.

To add a language, copy `locale/en.msg` to `locale/<code>.msg` and translate what
you want. Nothing else changes: both halves of the tool, bash and the embedded
python reports, read the same files, so a string exists once per language. Run
`tests/locale-check.sh` afterwards — it catches keys that do not exist in
English, keys the code never uses, and the one mistake that actually breaks at
runtime: a translation whose `%s` count differs from the original.

There is no gettext dependency and no `declare -A`, because `msgfmt` is not on a
stock macOS and the system bash is 3.2.

## Layout

```
bin/upgrade-vendor-packages.sh   the tool
lib/i18n.sh, lib/i18n.py         catalogue loaders, bash and python sides
locale/en.msg, locale/ru.msg     message catalogues
config/tools.conf.example        machine config: which vendors, which casks
skills/brew-to-macports/         thin agent orchestrator for the interactive migration
docs/GOTCHAS.md                  hard-won traps, each with the incident behind it
tests/py39-compat.sh             embedded report code must stay 3.9-compatible
tests/locale-check.sh            catalogues must stay consistent
```

## Requirements

macOS, bash, `curl`, and Apple's `/usr/bin/python3`. MacPorts is optional —
without it step 2 is skipped and the tool says so. Nothing needs `sudo` except
MacPorts operations, which the script delegates rather than performing silently.

Adding a vendor tool means three things in `bin/upgrade-vendor-packages.sh`: a
`latest_<tool>`, an `install_<tool>`, an entry in the architecture map, plus the
name in `ALL_TOOLS`. Listing a name in the config without those functions does
nothing.

## Status

Built while taking one Intel Mac off Homebrew entirely. On a machine where no
formula is installed and no cask declares a formula dependency, Homebrew has
nothing left it can drag into a source build — that is the end state this tool
aims at.
