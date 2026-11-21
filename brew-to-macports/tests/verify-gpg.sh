#!/usr/bin/env bash
#
# verify_gpg must accept a file only when its detached signature is valid AND
# was made by the pinned key. evermeet.cx now redirects every download to a
# third-party host, so the signature is the only thing that ties the binary to
# its author. Throwaway keys are generated here; nothing touches ~/.gnupg.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../bin/upgrade-vendor-packages.sh"

command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1 \
    || { echo "SKIP: gpg/gpgv not installed"; exit 0; }

work="$(mktemp -d)"
trap 'gpgconf --homedir "$work/g" --kill all >/dev/null 2>&1; rm -rf "$work"' EXIT
export GNUPGHOME="$work/g"
mkdir -m 700 "$GNUPGHOME"

# The function under test, lifted out of the script so the script's main body
# does not run.
awk '/^verify_gpg\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SCRIPT" > "$work/fn.sh"
grep -q '^verify_gpg()' "$work/fn.sh" || { echo "FAIL: verify_gpg not found in $SCRIPT"; exit 1; }
# shellcheck source=/dev/null
. "$work/fn.sh"

newkey() {
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$1" ed25519 sign never >/dev/null 2>&1
    gpg --batch --with-colons --list-keys "$1" | awk -F: '$1=="fpr"{print $10; exit}'
}
A="$(newkey 'pinned <a@test>')"
B="$(newkey 'other <b@test>')"
gpg --batch --armor --export "$A" > "$work/a.asc"
gpg --batch --armor --export "$A" "$B" > "$work/ab.asc"

printf 'binary\n' > "$work/f"
gpg --batch --pinentry-mode loopback --passphrase '' -u "$A" -o "$work/f.sigA" --detach-sign "$work/f"
gpg --batch --pinentry-mode loopback --passphrase '' -u "$B" -o "$work/f.sigB" --detach-sign "$work/f"
printf 'tampered\n' > "$work/t"

# The real keyring must not help: verification has to use only the key file.
fail=0
check() {
    local want="$1" desc="$2"; shift 2
    verify_gpg "$@"; local rc=$?
    if [ "$want" = ok ] && [ $rc -eq 0 ]; then echo "ok   $desc"
    elif [ "$want" = no ] && [ $rc -ne 0 ]; then echo "ok   $desc (rc=$rc)"
    else echo "FAIL $desc (rc=$rc)"; fail=1; fi
}

check ok "valid signature by the pinned key"            "$work/f" "$work/f.sigA" "$work/a.asc"  "$A"
check no "file changed after signing"                   "$work/t" "$work/f.sigA" "$work/a.asc"  "$A"
check no "signed by a key that is not in the key file"  "$work/f" "$work/f.sigB" "$work/a.asc"  "$A"
check no "signed by a key in the file but not pinned"   "$work/f" "$work/f.sigB" "$work/ab.asc" "$A"
check no "key file holds a different key than pinned"  "$work/f" "$work/f.sigA" "$work/a.asc"  "$B"
check no "signature file missing"                       "$work/f" "$work/nope"   "$work/a.asc"  "$A"
check no "key file missing"                             "$work/f" "$work/f.sigA" "$work/nope"   "$A"

exit $fail
