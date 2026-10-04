#!/usr/bin/env bash
#
# Installs brew-to-macports: the script onto PATH, the skill where the agent
# looks for skills, and a config to edit. Idempotent; nothing needs sudo.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills}"
CONF_DIR="${CONF_DIR:-$HOME/.config/brew-to-macports}"

ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }

[ "$(uname -s)" = "Darwin" ] || { warn "this tool is macOS-only (uname -s = $(uname -s))"; exit 1; }
[ -x /usr/bin/python3 ] || { warn "/usr/bin/python3 missing — install Xcode Command Line Tools"; exit 1; }
command -v curl >/dev/null 2>&1 || { warn "curl not found"; exit 1; }

mkdir -p "$BIN_DIR" "$SKILL_DIR" "$CONF_DIR"

ln -sfn "$HERE/bin/upgrade-vendor-packages.sh" "$BIN_DIR/upgrade-vendor-packages"
ok "script → $BIN_DIR/upgrade-vendor-packages"

# Two traps here.
# 1. `ln -sfn` into a path that is already a REAL directory puts the link
#    *inside* it, silently yielding .../brew-to-macports/brew-to-macports.
# 2. A backup must not be left inside SKILL_DIR: every directory there is
#    loaded as a skill, so the copy would register as a duplicate skill with
#    the same description, and the agent would see two of them.
skill_target="$SKILL_DIR/brew-to-macports"
if [ -d "$skill_target" ] && [ ! -L "$skill_target" ]; then
    backup="${TMPDIR:-/tmp}/brew-to-macports.skill.bak.$(date +%Y%m%d%H%M%S)"
    mv "$skill_target" "$backup"
    warn "a real skill directory was already there; moved out of $SKILL_DIR to:"
    printf '    %s\n' "$backup"
fi
ln -sfn "$HERE/skills/brew-to-macports" "$skill_target"
ok "skill  → $skill_target"

# The config is copied, not symlinked: it is machine-specific and editing it
# must not dirty the repository.
if [ -f "$CONF_DIR/tools.conf" ]; then
    ok "config already present, left alone: $CONF_DIR/tools.conf"
else
    cp "$HERE/config/tools.conf.example" "$CONF_DIR/tools.conf"
    ok "config → $CONF_DIR/tools.conf  (edit ALL_TOOLS and MAJOR_ONLY_CASKS)"
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH — add it, e.g. in ~/.zshenv:"
       printf '    path=("%s" $path)\n' "$BIN_DIR" ;;
esac

if ! command -v port >/dev/null 2>&1 && [ ! -x /opt/local/bin/port ]; then
    warn "MacPorts not found — step 2 of the migration will be skipped"
    printf '    installer for your macOS: https://www.macports.org/install.php\n'
fi

printf '\n'
ok "done. Next: upgrade-vendor-packages --bootstrap   (changes nothing)"
