#!/usr/bin/env bash
#
# Catalogue consistency. English is the base, so this checks every other
# language against it:
#
#   1. keys the translation defines that English does not  — dead weight, or a
#      typo that will never be looked up
#   2. keys English has that the translation lacks         — fine at runtime
#      (they fall back), reported as a count so a stale catalogue is visible
#   3. placeholder count mismatch                          — the real hazard: a
#      translation with fewer %s silently drops a value, with more it raises
#      inside the formatting call
#   4. keys used in the code but absent from English       — would print !key!
#   5. keys in English that the code never uses            — dead strings
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
LOC="$ROOT/locale"
SCRIPT="$ROOT/bin/upgrade-vendor-packages.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ -f "$LOC/en.msg" ] || { red "no $LOC/en.msg"; exit 1; }

fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# key<TAB>number-of-%s-placeholders
keymap() {
    /usr/bin/python3 - "$1" <<'PY'
import sys
for line in open(sys.argv[1], encoding='utf-8'):
    if not line.strip() or line.lstrip().startswith('#') or '=' not in line:
        continue
    k, _, v = line.partition('=')
    k = k.strip()
    if k:
        # %% is a literal percent, not a placeholder
        print('%s\t%d' % (k, v.replace('%%', '').count('%s')))
PY
}

keymap "$LOC/en.msg" | sort > "$tmp/en"
cut -f1 "$tmp/en" > "$tmp/en.keys"
printf 'en.msg: %s keys\n\n' "$(grep -c '' < "$tmp/en.keys")"

for f in "$LOC"/*.msg; do
    lang="$(basename "$f" .msg)"
    [ "$lang" = "en" ] && continue
    keymap "$f" | sort > "$tmp/$lang"
    cut -f1 "$tmp/$lang" > "$tmp/$lang.keys"

    printf '%s.msg: %s keys\n' "$lang" "$(grep -c '' < "$tmp/$lang.keys")"

    extra="$(comm -13 "$tmp/en.keys" "$tmp/$lang.keys")"
    if [ -n "$extra" ]; then
        red "  keys not present in en.msg (dead or misspelled):"
        printf '    %s\n' $extra
        fail=1
    fi

    missing_n="$(comm -23 "$tmp/en.keys" "$tmp/$lang.keys" | grep -c . || true)"
    if [ "$missing_n" != "0" ]; then
        yellow "  $missing_n keys untranslated — they fall back to English"
    fi

    # placeholder arity must match, or formatting breaks at runtime
    bad="$(join -t"$(printf '\t')" "$tmp/en" "$tmp/$lang" \
           | awk -F"\t" '$2 != $3 {print "    " $1 "  en:" $2 "  '"$lang"':" $3}')"
    if [ -n "$bad" ]; then
        red "  %s placeholder count differs:"
        printf '%s\n' "$bad"
        fail=1
    fi
    printf '\n'
done

# --- keys referenced by the code -------------------------------------------
if [ -f "$SCRIPT" ]; then
    {
        grep -oE "(msg|msgf|msgl) [a-z][a-z0-9_.]*" "$SCRIPT" | awk '{print $2}'
        # The leading [^A-Za-z0-9_] keeps this from matching the "t(" inside
        # .get('...') and similar — that produced a dozen phantom keys.
        grep -oE "[^A-Za-z0-9_]t\('[a-z][a-z0-9_.]*'" "$SCRIPT" | sed "s/.*t('//;s/'//"
    } | sort -u > "$tmp/used"
    printf 'keys referenced in the script: %s\n' "$(grep -c '' < "$tmp/used")"

    undefined="$(comm -23 "$tmp/used" "$tmp/en.keys")"
    if [ -n "$undefined" ]; then
        red "  used but missing from en.msg — these would print as !key!:"
        printf '    %s\n' $undefined
        fail=1
    fi

    unused="$(comm -13 "$tmp/used" "$tmp/en.keys")"
    if [ -n "$unused" ]; then
        yellow "  defined but never used:"
        printf '    %s\n' $unused
    fi
fi

printf '\n'
if [ "$fail" = "0" ]; then
    green "✓ catalogues are consistent"
else
    red "✗ catalogues need fixing"
fi
exit "$fail"
