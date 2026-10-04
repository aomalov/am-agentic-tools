# brew-to-macports — English message catalogue (the base).
#
# Format: key = text. Placeholders are printf-style (%s), identical on the bash
# and python sides, so a string lives here once no matter which half prints it.
#
# This file is the fallback for every other language: a key missing from a
# translation renders in English rather than as an empty line. To add a
# language, copy this file to <code>.msg and translate what you can — a partial
# catalogue is already usable.

# ------------------------------------------------------------------ usage ---
usage.title     = upgrade-vendor-packages — vendor binaries instead of building from source in brew
usage.all       = check and upgrade everything
usage.check     = report only, change nothing
usage.only      = work on these tools only
usage.patch     = take patch releases as well
usage.rollback  = roll back to the previous version
usage.list      = what is installed right now
usage.preflight = Homebrew check only, no upgrades
usage.macports  = deep check of MacPorts archive readiness
usage.bootstrap = new machine: what migrates where
usage.tools     = Tools:
usage.prefix    = Prefix:
usage.symlinks  = (symlinks in %s)
usage.body1     = A plain run does everything at once: vendor binaries, brew casks,
usage.body2     = the Homebrew preflight, MacPorts upgrades (will ask for a sudo password)
usage.body3     = and a sweep for newly published archives.
usage.body4     = MacPorts is upgraded strictly through port -b (binary-only): a port with no
usage.body5     = archive for this platform stays as it is, and nothing gets compiled.
usage.casks     = Brew casks on the major-only policy:
usage.casks1    = They are held with brew pin, so brew upgrade never touches them.
usage.casks2    = This script unpins only for a major upgrade and pins them back
usage.casks3    = afterwards. --include-patch takes minor and patch releases too.

# ------------------------------------------------------------------ errors --
err.unknown_arg  = unknown argument: %s
err.unknown_arch = unsupported architecture: %s
err.no_tool      = missing utility: %s
err.no_py        = %s not found
err.no_bindir    = %s: could not find %s
err.no_tool_name = unknown tool: %s
err.no_version   = %s: could not get the version from the vendor
err.install      = %s: install failed, the old version is untouched
err.symlinks     = %s: could not create the symlinks
err.ffmpeg_arch  = ffmpeg: evermeet.cx builds for Intel only, and this is %s
err.gcloud_upd   = gcloud: components update failed, the directory stays at %s
err.no_previous  = %s: no previous version to roll back to (currently %s)
err.nothing      = nothing

# ------------------------------------------------------- vendor binaries ----
vendor.head        = Vendor binaries · %s · darwin %s
vendor.checkmode   = check mode — nothing will be changed
vendor.pruned      = removed old version %s %s
vendor.rolled_back = %s: rolled back %s → %s
vendor.not_present = not installed → %s
vendor.latest      = already latest (%s)
vendor.ours_newer  = vendor has %s, ours is newer (%s)
vendor.patch       = %s → %s (patch)
vendor.patch_skip  = %s → %s — patch only, skipping
vendor.minor       = %s → %s (minor)
vendor.major       = %s → %s (MAJOR)
vendor.odd_version = cannot compare versions: %s vs %s
vendor.unpacked    = version %s is already unpacked, switching the symlinks
vendor.downloading = downloading...
vendor.ready       = %s %s ready
vendor.gcloud_inplace = upgrading in place through gcloud components update

# ----------------------------------------------------------------- summary --
sum.would_install = (would be installed)
sum.installed     = installed
sum.skipped_patch = skipped as a patch (--include-patch to take it)
sum.request_error = — request failed
sum.install_error = — INSTALL FAILED
sum.symlink_error = — SYMLINK FAILED

# ----------------------------------------------------------------- shim -----
shim.format = rsvg-convert (resvg): format '%s' is not supported — resvg only writes png

# --------------------------------------------------------------- MacPorts ---
mp.head_upgrade   = MacPorts · upgrading ports
mp.head_watch     = MacPorts · watching for archives
mp.head_ready     = MacPorts · archive readiness
mp.checkmode      = check mode: not updating the ports tree, reporting current state
mp.selfupdate     = updating the ports tree...
mp.no_root        = MacPorts: not root, and no way to ask for a password
mp.run_manually   = run manually: sudo port selfupdate && sudo port -b upgrade outdated
mp.selfupdate_bad = MacPorts: selfupdate did not finish, continuing with the old tree
mp.upgrading      = upgrading (binary-only, nothing will be compiled)...
mp.upgrade_failed = %s: upgrade failed
mp.sum_upgraded   = ports upgraded: %s
mp.sum_failed     = not upgraded:%s
mp.pruning        = removing inactive port versions: %s
mp.pruned         = inactive versions removed
mp.prune_failed   = MacPorts: could not remove the inactive versions
mp.archive_yes    = archive available
mp.archive_wait   = waiting for an archive
mp.cached_today   = (today's data; --macports re-checks deeply)

# ------------------------------------------------------------------- brew ---
brew.head_preflight = Homebrew preflight
brew.head_holders   = Homebrew · what still holds which formula
cask.head           = Brew casks · major versions only
cask.no_data        = %s: brew returned no data for the cask
cask.not_installed  = not installed
cask.install_hint   = to install: brew install --cask %s
cask.latest         = already latest (%s)
cask.ours_newer     = upstream has %s, ours is newer (%s)
cask.major          = %s → %s (MAJOR)
cask.taken_patch    = %s → %s (%s, taken because of --include-patch)
cask.not_major      = %s → %s — not a major, skipping
cask.odd_version    = cannot compare versions: %s vs %s
cask.would_upgrade  = (would be upgraded)
cask.unpinning      = unpinning and upgrading...
cask.upgraded       = %s %s ready
cask.upgrade_failed = %s: brew upgrade failed
cask.pinned         = pinned
cask.pinned_note    = pinned: brew upgrade will not touch it again
cask.not_pinned     = %s is not pinned — a plain run will do brew pin --cask %s
cask.pin_failed     = %s: could not pin it (brew pin --cask %s)
cask.sum_skipped    = skipped: not a major (--include-patch to take it)
cask.sum_upgraded   = upgraded
cask.sum_error      = — UPGRADE FAILED

# ------------------------------------------------------------------- list ---
list.head   = Installed in %s
list.empty  = nothing here
list.header = TOOL         VERSION          UPDATED              PATH

# -------------------------------------------------------------- bootstrap ---
boot.head        = New migration · inventory
boot.platform    = platform:
boot.macports    = MacPorts:
boot.mp_prefix   = (prefix %s)
boot.mp_missing  = not installed
boot.mp_skipped  = — step 2 will be skipped
boot.mp_pkg      = installer for this macOS: https://www.macports.org/install.php
boot.state       = vendors in state.tsv:
boot.config      = config:
boot.no_config   = not found
boot.defaults    = — running with the built-in defaults
boot.no_brew     = Homebrew is not installed here — nothing to migrate from

# ----------------------------------------------------------- fresh machine --
fresh.warn   = no vendor state found — this looks like a new machine
fresh.hint1  = start with: %s --bootstrap
fresh.hint2  = it changes nothing, it only shows what migrates where
fresh.hint3  = then come back here, or ask the brew-to-macports skill to walk you through

# ----------------------------------------------------------------- result ---
result.head    = Result
result.nothing = everything is current, nothing to do

# ------------------------------------------- MacPorts: outdated ports report -
mpr.up_to_date    = ports are up to date
mpr.outdated      = ports needing an upgrade: %s
mpr.archive_yes   = archive available:
mpr.archive_no    = no archive for this platform:
mpr.skipped_by_b  = -b will skip them; they upgrade once the buildbot catches up
mpr.uncheckable   = could not be checked:

# --------------------------------------------- MacPorts: migration watchlist -
mpc.nothing_left  = nothing left to migrate out of brew
mpc.remaining     = still in brew: %s formulae, %s casks
mpc.held_by_cask  = %s is held by cask %s — it cannot migrate,
mpc.held_note     = the cask depends on the brew formula itself; the rest is its support tree
mpc.target        = target: %s   ports watched: %s
mpc.why_building  = brew is ALREADY building from source
mpc.why_bottle    = brew still pours a bottle
mpc.why_absent    = not installed in brew
mpc.new           = ← NEW
mpc.has_archive   = archive %s
mpc.no_mp_compare = MacPorts not installed — did not compare against the ports tree
mpc.stale_archive = an archive exists, but not for the version in the tree
mpc.need_selfupd  = run sudo port selfupdate, otherwise port will BUILD
mpc.on_server     = on the server: %s
mpc.no_archive    = no archive
mpc.deep_head     = Deep check: readiness of the dependency tree
mpc.deep_ports    = %s/%s ports
mpc.deep_waiting  = waiting for: %s
mpc.deep_waiting_n = waiting for %s more, including: %s
mpc.ready_title   = Ready to migrate to MacPorts: %s
mpc.mp_missing    = MacPorts is not installed yet:
mpc.mp_step1      = 1. installer for macOS %s: https://www.macports.org/install.php
mpc.mp_step2      = 2. sudo port selfupdate
mpc.pulls_in      = pulls in %s more ports
mpc.say_migrate   = Say "migrate %s"
mpc.say_migrate2  = and I will do it: install the ports, check they came as binaries,
mpc.say_migrate3  = remove them from brew and clean up what is orphaned.
mpc.b_required    = The -b flag is mandatory: binary-only, it aborts instead of building.
mpc.point_of_it   = Why migrate: MacPorts lives in %s with its own copies of
mpc.point_of_it2  = the libraries, does not depend on the system ones, and keeps a platform alive for years.
mpc.none_ready    = no ports are ready to migrate yet
mpc.tree_behind   = The ports tree is behind the server: %s
mpc.tree_behind2  = Archives exist, but for other versions. Run sudo port selfupdate first.
mpc.urgent        = urgent (brew is already compiling and the port is not ready): %s

# ------------------------------------------- MacPorts: watchlist maintenance -
mpw.rebuilt       = list rebuilt from brew leaves: %s entries —
mpw.locked_out    = cannot migrate: %s — casks require them
mpw.no_port_name  = could not match a port name: %s
mpw.naming_note   = (brew and MacPorts name packages differently — libpq is postgresql18;
mpw.naming_note2  = if you need one, add it to MACPORTS_WATCH by hand)

# ---------------------------------------------------------- brew preflight ---
pf.no_cache       = brew cache not found — preflight skipped (run brew update)
pf.cache_unread   = could not read the brew cache: %s
pf.nothing        = brew: nothing to upgrade
pf.pending        = pending upgrades: %s
pf.from_source    = from source: %s
pf.heavy          = ← HEAVY TOOLCHAIN: %s
pf.will_pour      = pours a bottle
pf.held           = pinned and will not be touched: %s
pf.dont_upgrade   = Do not run a full brew upgrade.
pf.heavy_note1    = A heavy toolchain builds for hours and takes every core — rust's
pf.heavy_note2    = bootstrap and the LLVM build ignore HOMEBREW_MAKE_JOBS.
pf.heavy_note3    = Pin the culprit:
pf.heavy_cmd      = brew pin <formula>
pf.minutes        = There are source builds, but no heavy toolchain — that means minutes.

# ------------------------------------------------------ brew holder report ---
ow.none_left      = no formulae left in brew — nothing to hold
ow.info_unread    = could not read brew info: %s
ow.holder_formula = formula %s
ow.holder_cask    = cask %s
ow.installed      = formulae installed: %s
ow.no_holders     = nothing holds them — safe to remove:
ow.cask_only      = %s is held only by a cask: %s
ow.cask_only_note = no formula references it; at runtime the cask uses its own interpreter
ow.pulls          = pulls in: %s
ow.no_bottle      = no bottle for this platform; a reinstall would build from source:
ow.order_matters  = remove it like this — order matters, do not run brew upgrade in between:
ow.will_return    = it comes back on brew upgrade --cask %s — pin it again then
ow.risky          = no bottle and NOT pinned — the next brew upgrade will build these:
ow.all_safe       = everything is pinned or bottled — no surprise builds

# ------------------------------------------------------------- bootstrap -----
bs.brew_empty     = nothing is installed in Homebrew — nothing to migrate
bs.inventory      = Homebrew: %s formulae, %s casks
bs.bottle_tag     = , bottle_tag %s
bs.cache_unread   = brew cache not read — nothing to say about bottles, run brew update
bs.probing        = checking %s formulae against MacPorts...
bs.bottled        = bottled
bs.not_bottled    = NO BOTTLE — will be built from source
bs.only_casks     = no formulae in brew — nothing to migrate, only casks remain
bs.route1         = 1. Vendor binary — %s
bs.route1_note    = this script installs them itself; no compiler and no root needed
bs.after_check    = ← after you have checked it
bs.route2         = 2. MacPorts — %s, an archive for this platform exists
bs.route2_note    = strictly with -b: with no archive the port is skipped, not compiled
bs.route3         = 3. Stays in brew for now — %s
bs.why_no_port    = no such port in MacPorts
bs.why_no_archive = the port exists, but has no archive for this platform
bs.why_stale      = an archive exists, but not for the version the ports tree wants
bs.why_no_mp      = MacPorts is not installed
bs.nobody_holds   = ← nothing holds it, safe to remove
bs.risky1         = These will be built from source on the very next brew upgrade.
bs.risky2         = Pin them until a replacement is found:
bs.cask_pulls     = casks that pull formulae — their migration is blocked by the cask, not the formula:
bs.order1         = Order: step 1 first, then 2, and only what is left — step 3.
bs.order2         = After each step check that the tool works, and only then remove it from brew.
