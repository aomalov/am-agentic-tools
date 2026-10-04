#!/usr/bin/env bash
#
# Message catalogue loader — bash side.
#
# Why not gettext: `msgfmt`/`msgmerge` are not on a stock macOS, and on the very
# machines this tool exists for, installing them through Homebrew means a build
# from source. The whole point is to need nothing.
#
# Why not an associative array: macOS ships bash 3.2, which has no `declare -A`.
# Keys become plain variables with an `M_` prefix instead, which works
# everywhere and stays readable in a debugger.
#
# The catalogue format is deliberately simple enough that the embedded python
# reports parse the *same* files (see lib/i18n.py) — one source of truth per
# language, no duplicated strings.
#
#   key.with.dots = text with %s placeholders
#
# Loading order is English first, then the selected language on top. A key that
# a translation has not covered therefore falls back to English instead of
# printing an empty string, which is what makes adding a language safe: a
# partial catalogue is a usable catalogue.

# Resolve the language once: explicit override, else the usual locale variables,
# else English.
i18n_detect_lang() {
    if [ -n "${BREW2MP_LANG:-}" ]; then
        printf '%s' "$BREW2MP_LANG"
        return
    fi
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        ru*|RU*|*_RU*) printf 'ru' ;;
        *)             printf 'en' ;;
    esac
}

# Turn one catalogue file into M_* variables. Later files override earlier ones.
i18n_load_file() {
    local file="$1" line key val
    [ -f "$file" ] || return 0
    # IFS= and -r keep leading spaces and backslashes intact; the final `[ -n ]`
    # catches a last line with no trailing newline.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        case "$line" in
            *=*) ;;
            *)   continue ;;
        esac
        key="${line%%=*}"
        val="${line#*=}"
        # trim surrounding spaces around the key and one space after '='
        key="${key%"${key##*[![:space:]]}"}"
        key="${key#"${key%%[![:space:]]*}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        # keys are addressed as shell variables, so only these characters
        case "$key" in
            *[!a-zA-Z0-9_.]*|'') continue ;;
        esac
        eval "M_${key//./_}=\$val"
    done < "$file"
}

# Call once from the main script with the directory holding the catalogues.
i18n_init() {
    I18N_DIR="${1:?i18n_init needs the locale directory}"
    I18N_LANG="$(i18n_detect_lang)"
    i18n_load_file "$I18N_DIR/en.msg"
    [ "$I18N_LANG" != "en" ] && i18n_load_file "$I18N_DIR/$I18N_LANG.msg"
    export I18N_DIR I18N_LANG
}

# msg KEY — the text, no newline. An unknown key prints the key itself, which
# makes a typo visible in the output instead of silently blanking a line.
msg() {
    local v="M_${1//./_}"
    if [ -n "${!v+x}" ]; then printf '%s' "${!v}"; else printf '!%s!' "$1"; fi
}

# msgf KEY ARGS... — the text as a printf format. Use for anything with %s.
msgf() {
    local v="M_${1//./_}" fmt
    if [ -n "${!v+x}" ]; then fmt="${!v}"; else fmt="!$1!"; fi
    shift
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}

# msgl KEY ARGS... — same, with a trailing newline. The common case.
msgl() {
    msgf "$@"
    printf '\n'
}
