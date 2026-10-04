# Gotchas

Every entry is a mistake this tool made once. The tool now guards against each
one; the incident is kept because the guard is only obvious after you have been
burned.

## Checking "is there an archive" is not enough

MacPorts archive names are
`<port>-<version>_<revision><+default variants>.<darwin_N|darwin_any|any_any>.<arch|noarch>.tbz2`.

A check that accepts *any* archive for the port reported `tesseract` as ready.
The ports tree wanted `5.4.1_5`; the mirror had `5.5.3_0`. `port install` found
no matching archive and compiled from source instead. Always build the expected
name from `port info --version --revision` plus the **default** variants from
`port variants`, and require an exact prefix match.

Corollary: run `sudo port selfupdate` first. A stale ports tree asks for a
version the mirror does not have, and that alone sends the port off to compile.

## A non-default variant changes the archive name

`gnupg2` failed with a 404 on archivefetch. The local tree defaulted to
`+pinentry`, the buildbot had built `+pinentry_mac`. Different variants, different
file name, no archive.

Worse, a failed build records the variants it started with, so retrying with the
right ones errors out with *"Requested variants do not match those the build was
started with"* until you `sudo port clean <port>`.

The same applies in reverse: asking for an extra variant can lose an archive that
exists for the default set. `google-cloud-sdk` has an Intel archive, but only
without variants — `+cloud_run_proxy` has none, so `-b` aborts.

## `brew uses --installed` returns empty output on timeout

On a loaded machine it regularly exceeds 20 seconds and exits with **no output**,
which reads exactly like "nothing depends on this". A sweep built on it will
happily propose deleting libraries that several installed packages depend on.

Build the dependency graph from `brew info --json=v2 --installed`, or from
Homebrew's cache payload. Never decide a package is unused from that command.

## Casks declare formula dependencies, and the formula graph cannot see them

A cask's `depends_on.formula` is invisible to any formula-only graph. This is how
`python@3.14` can be removed from under a `gcloud-cli` cask that requires it —
and, conversely, how a single line of cask metadata can turn out to be the only
thing keeping a whole subtree of formulae installed.

Read `brew info --cask --json=v2` and merge both sides before calling anything an
orphan.

## The cache payload is two lines, and it is not NDJSON

```
$(brew --cache)/api/internal/packages.<tag>.jws.json.payload
```

Line 1 is a JWS envelope (`protected`, `signature`). The data is in **line 2** —
`.splitlines()[1]`, with keys `metadata` / `formulae` / `casks`. Parsing the file
as NDJSON silently yields an empty graph in which every package looks like a
leaf, and the resulting report is confidently wrong.

`metadata.bottle_tag` says which platform the file is for (`tahoe` is Intel
macOS 26; Apple Silicon would be `arm64_tahoe`), so the file is already filtered
to this machine. A formula with no `bottle_checksum` will be built from source.

## Pick the newest payload, not the alphabetically first

Several payloads can sit in the cache: after a macOS upgrade `packages.sonoma`
stays next to `packages.tahoe`. `sorted(glob(...))[0]` then hands you the payload
of a **different OS** and every bottle verdict is computed against the wrong
platform. Sort by mtime.

## Uninstalling a pinned formula needs `unpin` first

`brew uninstall` refuses outright:

> `<formula> is pinned. You must unpin it to uninstall.`

The pin itself only gates `brew upgrade`. The danger is the gap: between `unpin`
and `uninstall`, any `brew upgrade` will build the now-unprotected formula from
source. Run the two commands back to back with nothing in between.

## Read a cask's `artifacts` before removing it

`gcloud-cli` carries a `zap` stanza that deletes
`/usr/local/share/google-cloud-sdk` — the real SDK, including every component
installed into it. It only runs with `--zap`, while plain `uninstall` just
trashes the Caskroom symlink. Passing the flag by reflex costs the installation.

Its `postflight` also rebuilds the gcloud virtualenv against Homebrew's python.
A cask reinstall therefore undoes a migration silently.

## `auto_updates: true` means the Caskroom version is fiction

The `gcloud-cli` Caskroom directory said 534.0.0 while the installed SDK had
self-updated to 587.0.0. Brew was never managing the version. Check what the tool
reports about itself, not what the package manager claims.

## MacPorts' `port -y` and `rdeps` details

`port -y install` writes to the registry and fails as a normal user with
*"attempt to write a readonly database"*. Use `port rdeps` to inspect instead.

`port rdeps` **without** `--no-build` inflates counts about threefold — it
counted 66 incoming dependencies for `tesseract` where the true runtime number
was 0.

## This shell is zsh, and zsh does not word-split

`for f in $LIST` iterates **once**, with the whole string as a single item. The
loop appears to run and reports success having done nothing. This produced a
cleanup that claimed to remove 15 packages and removed none — twice.

Wrap loops in `bash -c '...'`, or use zsh's explicit `${=VAR}`. Prefer `bash -c`:
it is harder to forget.

A non-matching glob is also fatal in zsh (`no matches found`) instead of passing
through, so guard globs with `(N)` or test the path first.

## Keep the embedded report code 3.9-compatible

The script runs its reports through Apple's `/usr/bin/python3`, which is 3.9 on
current macOS and older still on older releases. Using 3.10+ syntax breaks the
tool exactly on the old machines that need it most. `tests/py39-compat.sh`
extracts every embedded block and compiles it against 3.9.
