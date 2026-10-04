#!/usr/bin/env bash
#
# The script runs its reports through Apple's /usr/bin/python3, which is 3.9 on
# current macOS and older on older releases. 3.10+ syntax would break the tool
# exactly on the old machines that need it most. This extracts every embedded
# python block and compiles it against the system interpreter.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HERE/../bin/upgrade-vendor-packages.sh}"
PY="${PY:-/usr/bin/python3}"

[ -f "$TARGET" ] || { echo "no such file: $TARGET" >&2; exit 1; }

printf 'interpreter: %s (%s)\n' "$PY" "$("$PY" -V 2>&1)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

awk -v d="$work" '
    /<<.PYEOF.$/ { f = 1; n++; next }
    /^PYEOF$/    { f = 0; next }
    f            { print > (d "/chunk" n ".py") }
' "$TARGET"

count=$(find "$work" -name 'chunk*.py' | wc -l | tr -d ' ')
if [ "$count" = "0" ]; then
    echo "no embedded python blocks found — did the heredoc marker change?" >&2
    exit 1
fi
printf 'embedded blocks: %s\n\n' "$count"

fail=0
for f in "$work"/chunk*.py; do
    printf '  %-14s ' "$(basename "$f")"
    if out="$("$PY" -m py_compile "$f" 2>&1)"; then
        printf '\033[32mok\033[0m\n'
    else
        printf '\033[31mFAIL\033[0m\n%s\n' "$out"
        fail=1
    fi
done

printf '\n'
if [ "$fail" = "0" ]; then
    printf '\033[32m✓\033[0m all blocks compile on %s\n' "$("$PY" -V 2>&1)"
else
    printf '\033[31m✗\033[0m some blocks need newer python than the system one\n'
fi
exit "$fail"
