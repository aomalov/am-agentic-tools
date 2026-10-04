#!/usr/bin/env bash
#
# upgrade-vendor-packages.sh
#
# Ставит и обновляет инструменты из официальных бинарных релизов вендоров,
# в обход Homebrew.
#
# Зачем: Homebrew свернул сборку бутылок под Intel macOS. Формулы gh, go,
# node, pandoc, yt-dlp, terraform, ffmpeg, deno остались только с arm64-бутылками,
# поэтому на Intel они компилируются из исходников — десятки минут и
# полностью загруженный процессор. У всех у них есть готовый darwin/amd64
# бинарник от самого вендора.
#
# Политика версий: обновляемся при смене MAJOR или MINOR. Патч-релизы
# пропускаем (исключение — yt-dlp, у него патч это починка экстракторов).
#
# Отдельно скрипт присматривает за приложениями из Homebrew, которые выпускают
# патчи почти ежедневно: они держатся закреплёнными через brew pin и
# обновляются только на смене MAJOR — см. MAJOR_ONLY_CASKS.
#
# Ничего не требует sudo.
#
set -uo pipefail

VENDOR_ROOT="${VENDOR_ROOT:-$HOME/.local/vendor}"
BIN_DIR="${VENDOR_BIN_DIR:-$HOME/.local/bin}"
KEEP_VERSIONS="${KEEP_VERSIONS:-2}"

# Системный питон Apple. Ровно он, а не найденный в PATH: на свежей машине
# другого может не быть, а вставки в этом скрипте намеренно держатся в рамках
# 3.9, чтобы работать и на старых macOS.
PY="${PY:-/usr/bin/python3}"

# Каталог сообщений. Корень определяем от самого файла, чтобы скрипт работал и
# по симлинку из ~/.local/bin, и из рабочей копии репозитория.
SELF="${BASH_SOURCE[0]:-$0}"
while [ -L "$SELF" ]; do
    _t="$(readlink "$SELF")"
    case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac
done
ROOT_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
LIB_DIR="$ROOT_DIR/lib"
LOCALE_DIR="${BREW2MP_LOCALE_DIR:-$ROOT_DIR/locale}"
# shellcheck source=../lib/i18n.sh
if [ -f "$LIB_DIR/i18n.sh" ]; then
    . "$LIB_DIR/i18n.sh"
    i18n_init "$LOCALE_DIR"
else
    # Без каталога инструмент всё равно должен работать: ключи будут видны как
    # !key!, но ни одна ветка не упадёт.
    msg()  { printf '!%s!' "$1"; }
    msgf() { local f="$1"; shift; printf '!%s!' "$f"; }
    msgl() { msgf "$@"; printf '\n'; }
    I18N_LANG=en; I18N_DIR=""
fi
export I18N_LIB="$LIB_DIR"

# Инструменты, которые скрипт умеет ставить из официальных бинарников вендора.
# Переопределяется в конфиге (см. ниже).
ALL_TOOLS="${ALL_TOOLS:-gh go node pandoc yt-dlp terraform ffmpeg deno resvg gws gcloud}"

# Приложения, которые остаются в Homebrew, но обновляются только на смене
# MAJOR. Держатся закреплёнными (brew pin), чтобы brew upgrade не тянул
# ежедневные патчи: у крупных GUI-приложений каждый патч — это перекачка
# установщика целиком, нередко в несколько сотен мегабайт.
MAJOR_ONLY_CASKS="${MAJOR_ONLY_CASKS:-}"

# Конфиг. Первый найденный выигрывает; переменные окружения выше его, поэтому
# конфиг задаёт значения через ?= — то есть только если ещё не задано.
# Машинно-специфичное (чей это мак, какие приложения держать на мажорах) живёт
# здесь, а не в коде, иначе инструмент перестаёт быть универсальным.
CONFIG_FILE=""
for _cfg in \
    "${BREW2MP_CONFIG:-}" \
    "$HOME/.config/brew-to-macports/tools.conf" \
    "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/config/tools.conf"
do
    [ -n "$_cfg" ] && [ -f "$_cfg" ] && { CONFIG_FILE="$_cfg"; break; }
done
# shellcheck source=/dev/null
[ -n "$CONFIG_FILE" ] && . "$CONFIG_FILE"

STATE_FILE="$VENDOR_ROOT/state.tsv"
PROBE_CACHE="$VENDOR_ROOT/.macports-probe"

# ---------------------------------------------------------------- вывод ----

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m';    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m';  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
    C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

info() { printf '%s\n' "$*"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
head1(){ printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# --------------------------------------------------------------- аргументы -

DRY_RUN=0
INCLUDE_PATCH=0
ONLY=""
ROLLBACK=""

usage() {
    local n="upgrade_vendor_packages"
    msgl usage.title
    printf '\n'
    printf '  %-40s %s\n' "$n"                   "$(msg usage.all)"
    printf '  %-40s %s\n' "$n --check"           "$(msg usage.check)"
    printf '  %-40s %s\n' "$n --only gh,go"      "$(msg usage.only)"
    printf '  %-40s %s\n' "$n --include-patch"   "$(msg usage.patch)"
    printf '  %-40s %s\n' "$n --rollback node"   "$(msg usage.rollback)"
    printf '  %-40s %s\n' "$n --list"            "$(msg usage.list)"
    printf '  %-40s %s\n' "$n --preflight"       "$(msg usage.preflight)"
    printf '  %-40s %s\n' "$n --macports"        "$(msg usage.macports)"
    printf '  %-40s %s\n' "$n --bootstrap"       "$(msg usage.bootstrap)"
    printf '\n'
    printf '%-14s%s\n' "$(msg usage.tools)"  "$ALL_TOOLS"
    printf '%-14s%s   %s\n' "$(msg usage.prefix)" "$VENDOR_ROOT" "$(msgf usage.symlinks "$BIN_DIR")"
    printf '\n'
    msgl usage.body1; msgl usage.body2; msgl usage.body3
    printf '\n'
    msgl usage.body4; msgl usage.body5
    printf '\n'
    printf '%s %s\n' "$(msg usage.casks)" "${MAJOR_ONLY_CASKS:-—}"
    printf '  %s\n' "$(msg usage.casks1)"
    printf '  %s\n' "$(msg usage.casks2)"
    printf '  %s\n' "$(msg usage.casks3)"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--check|--dry-run) DRY_RUN=1 ;;
        --include-patch)      INCLUDE_PATCH=1 ;;
        --bootstrap)          ONLY="__bootstrap__" ;;
        --only)               ONLY="$(printf '%s' "${2:-}" | tr ',' ' ')"; shift ;;
        --only=*)             ONLY="$(printf '%s' "${1#*=}" | tr ',' ' ')" ;;
        --rollback)           ROLLBACK="${2:-}"; shift ;;
        --rollback=*)         ROLLBACK="${1#*=}" ;;
        --list)               ONLY="__list__" ;;
        --preflight)          ONLY="__preflight__" ;;
        --macports)           ONLY="__macports__" ;;
        -h|--help)            usage; exit 0 ;;
        *) err "$(msgf err.unknown_arg "$1")"; usage; exit 2 ;;
    esac
    shift
done

# ------------------------------------------------------------ архитектура --

UNAME_M="$(uname -m)"
DARWIN_MAJOR="$(uname -r | cut -d. -f1)"

case "$UNAME_M" in
    x86_64) A_GO=amd64; A_GH=amd64; A_NODE=x64;   A_PANDOC=x86_64; A_TF=amd64; A_DENO=x86_64;  A_RESVG=x86_64;  A_GWS=x86_64;  A_GCLOUD=x86_64 ;;
    arm64)  A_GO=arm64; A_GH=arm64; A_NODE=arm64; A_PANDOC=arm64;  A_TF=arm64; A_DENO=aarch64; A_RESVG=aarch64; A_GWS=aarch64; A_GCLOUD=arm    ;;
    *)      err "$(msgf err.unknown_arch "$UNAME_M")"; exit 1 ;;
esac

# ------------------------------------------------------------- утилиты -----

need() { command -v "$1" >/dev/null 2>&1 || { err "$(msgf err.no_tool "$1")"; exit 1; }; }
need curl; need unzip; need tar
[ -x "$PY" ] || { err "$(msgf err.no_py "$PY")"; exit 1; }

fetch() { curl -fsSL --max-time 60 "$@"; }

gh_json() {
    local tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [ -n "$tok" ]; then
        fetch -H "Authorization: Bearer $tok" -H 'Accept: application/vnd.github+json' "$1"
    else
        fetch -H 'Accept: application/vnd.github+json' "$1"
    fi
}

# Сравнение версий. Печатает: newer-major | newer-minor | newer-patch | same | older
ver_relation() {
    "$PY" - "$1" "$2" <<'PYEOF'
import re, sys

def parts(v):
    v = v.strip().lstrip('vV')
    nums = [int(x) for x in re.findall(r'\d+', v)[:3]]
    while len(nums) < 3:
        nums.append(0)
    return nums

cur, new = parts(sys.argv[1]), parts(sys.argv[2])
if new < cur:
    print("older")
elif new == cur:
    print("same")
elif new[0] != cur[0]:
    print("newer-major")
elif new[1] != cur[1]:
    print("newer-minor")
else:
    print("newer-patch")
PYEOF
}

state_get() {
    [ -f "$STATE_FILE" ] || return 0
    awk -F'\t' -v t="$1" '$1==t {print $2}' "$STATE_FILE" | tail -1
}

state_set() {
    local tool="$1" ver="$2" tmp
    mkdir -p "$VENDOR_ROOT"
    touch "$STATE_FILE"
    tmp="$(mktemp)"
    awk -F'\t' -v t="$tool" '$1!=t' "$STATE_FILE" > "$tmp"
    printf '%s\t%s\t%s\n' "$tool" "$ver" "$(date +%Y-%m-%dT%H:%M:%S)" >> "$tmp"
    sort -o "$tmp" "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Разворачивает единственную вложенную папку архива прямо в назначение.
flatten_into() {
    local src="$1" dest="$2" inner count
    inner="$(find "$src" -mindepth 1 -maxdepth 1)"
    count="$(printf '%s' "$inner" | grep -c '^' || true)"
    if [ "$count" = "1" ] && [ -d "$inner" ]; then
        src="$inner"
    fi
    mkdir -p "$dest"
    ( cd "$src" && tar cf - . ) | ( cd "$dest" && tar xf - )
}

link_binaries() {
    local tool="$1" ver="$2" d f name
    d="$VENDOR_ROOT/$tool/$ver/bin"
    [ -d "$d" ] || { err "$(msgf err.no_bindir "$tool" "$d")"; return 1; }
    mkdir -p "$BIN_DIR"
    : > "$VENDOR_ROOT/$tool/$ver/.linked"
    for f in "$d"/*; do
        [ -e "$f" ] || continue
        [ -x "$f" ] || continue
        [ -d "$f" ] && continue
        name="$(basename "$f")"
        ln -sfn "$f" "$BIN_DIR/$name"
        printf '%s\n' "$name" >> "$VENDOR_ROOT/$tool/$ver/.linked"
    done
}

prune_old() {
    local tool="$1" keep="$2" d
    # BSD head не понимает head -n -N, поэтому хвост отрезаем через awk
    for d in $(ls -1 "$VENDOR_ROOT/$tool" 2>/dev/null | sort -V \
                 | awk -v k="$keep" '{a[NR]=$0} END{for(i=1;i<=NR-k;i++) print a[i]}'); do
        rm -rf "${VENDOR_ROOT:?}/$tool/$d"
        dim "    $(msgf vendor.pruned "$tool" "$d")"
    done
}

# ------------------------------------------------- версии у вендоров -------

latest_gh() {
    gh_json https://api.github.com/repos/cli/cli/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
latest_go() {
    fetch 'https://go.dev/dl/?mode=json' \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)[0]["version"][2:])'
}
latest_node() {
    fetch https://nodejs.org/dist/index.json \
        | "$PY" -c 'import json,sys; print(next(v for v in json.load(sys.stdin) if v["lts"])["version"].lstrip("v"))'
}
latest_pandoc() {
    gh_json https://api.github.com/repos/jgm/pandoc/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
latest_yt_dlp() {
    gh_json https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
latest_terraform() {
    fetch https://api.releases.hashicorp.com/v1/releases/terraform/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}
# deno собирается из исходников через lld, а у lld Intel-бутылки уже нет —
# сборка из brew утянула бы за собой весь LLVM. Берём готовый бинарник.
latest_deno() {
    gh_json https://api.github.com/repos/denoland/deno/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
# librsvg под Intel собирается только из исходников и тянет за собой rust —
# один такой случай занял 39 минут. resvg рендерит тот же SVG, но
# приезжает готовым бинарником на 1 МБ. Совместимость с rsvg-convert даёт шим,
# который кладётся рядом (см. install_resvg).
latest_resvg() {
    gh_json https://api.github.com/repos/linebender/resvg/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
# Google Workspace CLI. В MacPorts порт называется googleworkspace-cli и
# собирается через rust+cargo, а Intel-архива под darwin_25 там нет вообще —
# только darwin_16..24 и darwin_25.arm64. Upstream при этом сам выкладывает
# x86_64-apple-darwin и опережает порт (0.22.5 против 0.16.0).
# Бинарник внутри архива называется gws, отсюда и имя инструмента.
latest_gws() {
    gh_json https://api.github.com/repos/googleworkspace/cli/releases/latest \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}
# Google Cloud SDK. 2026-10-04 снят с brew: cask gcloud-cli объявлял
# depends_on formula python@3.14, и эта одна строчка держала все девять
# оставшихся формул, у шести из которых Intel-бутылки нет. При этом сам cask был
# фиктивным — Caskroom застыл на 534.0.0, а SDK давно обновлялся сам до 587, и
# качал cask ровно тот же tarball с dl.google.com, что берём мы.
#
# В MacPorts порт есть (google-cloud-sdk, архив darwin_any.x86_64), но он глушит
# "disable_updater": true и прибивает CLOUDSDK_PYTHON к python314, а ещё архив
# существует только без вариантов — +cloud_run_proxy там не собран. Компоненты
# важнее, поэтому вендор.
#
# Вшитого питона у Google под macOS не бывает: и darwin-x86_64, и darwin-arm
# отдают пустышки по ~114 байт (внутри файл с буквальным BUILD_NUMBER в имени),
# настоящий только linux-x86_64. gcloud поэтому живёт на виртуалке
# ~/.config/gcloud/virtenv, собранной от python.org framework — к brew она
# отношения не имеет.
latest_gcloud() {
    fetch https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}
latest_ffmpeg() {
    fetch https://evermeet.cx/ffmpeg/info/ffmpeg/release \
        | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}

latest_version() {
    case "$1" in
        gh)        latest_gh ;;
        go)        latest_go ;;
        node)      latest_node ;;
        pandoc)    latest_pandoc ;;
        yt-dlp)    latest_yt_dlp ;;
        terraform) latest_terraform ;;
        ffmpeg)    latest_ffmpeg ;;
        deno)      latest_deno ;;
        resvg)     latest_resvg ;;
        gws)       latest_gws ;;
        gcloud)    latest_gcloud ;;
    esac
}

# yt-dlp нумеруется датами, и «патч» у него — это починка сломавшихся
# экстракторов YouTube. Для него правило «только минор» не применяем.
version_policy() {
    case "$1" in
        yt-dlp) echo always ;;
        # gws ещё на 0.x: мажор и минор заморожены, вся жизнь идёт в патче.
        gws)    echo always ;;
        *)      echo minor ;;
    esac
}

# ------------------------------------------------------- установка ---------

install_gh() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.zip" "https://github.com/cli/cli/releases/download/v${v}/gh_${v}_macOS_${A_GH}.zip" || return 1
    unzip -qq "$tmp/a.zip" -d "$tmp/x" || return 1
    flatten_into "$tmp/x" "$dest"
    rm -rf "$tmp"
}

install_go() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.tgz" "https://go.dev/dl/go${v}.darwin-${A_GO}.tar.gz" || return 1
    mkdir -p "$tmp/x" && tar xzf "$tmp/a.tgz" -C "$tmp/x" || return 1
    flatten_into "$tmp/x" "$dest"
    rm -rf "$tmp"
}

install_node() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.tgz" "https://nodejs.org/dist/v${v}/node-v${v}-darwin-${A_NODE}.tar.gz" || return 1
    mkdir -p "$tmp/x" && tar xzf "$tmp/a.tgz" -C "$tmp/x" || return 1
    flatten_into "$tmp/x" "$dest"
    rm -rf "$tmp"
}

install_pandoc() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.zip" "https://github.com/jgm/pandoc/releases/download/${v}/pandoc-${v}-${A_PANDOC}-macOS.zip" || return 1
    unzip -qq "$tmp/a.zip" -d "$tmp/x" || return 1
    flatten_into "$tmp/x" "$dest"
    rm -rf "$tmp"
}

install_yt_dlp() {
    local v="$1" dest="$2"
    mkdir -p "$dest/bin"
    fetch -o "$dest/bin/yt-dlp" "https://github.com/yt-dlp/yt-dlp/releases/download/${v}/yt-dlp_macos" || return 1
    chmod +x "$dest/bin/yt-dlp"
}

install_terraform() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.zip" "https://releases.hashicorp.com/terraform/${v}/terraform_${v}_darwin_${A_TF}.zip" || return 1
    mkdir -p "$dest/bin"
    unzip -qq -o "$tmp/a.zip" -d "$dest/bin" || return 1
    chmod +x "$dest/bin/terraform"
    rm -rf "$tmp"
}

# evermeet.cx собирает статический ffmpeg только под Intel.
install_ffmpeg() {
    local v="$1" dest="$2" tmp b bv
    if [ "$UNAME_M" != "x86_64" ]; then
        err "$(msgf err.ffmpeg_arch "$UNAME_M")"
        return 1
    fi
    tmp="$(mktemp -d)"
    mkdir -p "$dest/bin"
    for b in ffmpeg ffprobe; do
        bv="$(fetch "https://evermeet.cx/ffmpeg/info/$b/release" \
              | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["version"])')" || return 1
        fetch -o "$tmp/$b.zip" "https://evermeet.cx/ffmpeg/${b}-${bv}.zip" || return 1
        unzip -qq -o "$tmp/$b.zip" -d "$dest/bin" || return 1
        chmod +x "$dest/bin/$b"
    done
    rm -rf "$tmp"
}

install_deno() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.zip" \
        "https://github.com/denoland/deno/releases/download/v${v}/deno-${A_DENO}-apple-darwin.zip" || return 1
    mkdir -p "$dest/bin"
    unzip -qq -o "$tmp/a.zip" -d "$dest/bin" || return 1
    chmod +x "$dest/bin/deno"
    rm -rf "$tmp"
}

# Слой совместимости: pandoc и прочие зовут rsvg-convert, а у нас resvg.
# Кладётся в тот же bin, что и resvg, поэтому link_binaries утащит обе штуки
# в ~/.local/bin, а откат по версиям работает как у всех остальных.
write_rsvg_shim() {
    local path="$1"
    cat > "$path" <<'SHIM'
#!/bin/sh
#
# rsvg-convert → resvg
#
# librsvg под Intel macOS остался без бутылки Homebrew и собирается из
# исходников через rust, поэтому rsvg-convert заменён на resvg. Этот скрипт
# переводит аргументы rsvg-convert в то, что понимает resvg.
#
# pandoc зовёт ровно так (проверено на pandoc 3.11):
#   rsvg-convert -f png -a --dpi-x 96 --dpi-y 96   < in.svg > out.png
#
# Ограничение: resvg умеет только PNG. Запрос pdf/ps/svg — это осознанная
# ошибка, а не тихая подмена формата.

resvg_bin="$(dirname "$0")/resvg"
dpi=96
fmt=png
out=""
width=""
height=""
input=""
background=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--format)          fmt="$2"; shift 2 ;;
        --format=*)           fmt="${1#*=}"; shift ;;
        --dpi-x|--dpi-y)      dpi="$2"; shift 2 ;;
        --dpi-x=*|--dpi-y=*)  dpi="${1#*=}"; shift ;;
        -d|--dpi)             dpi="$2"; shift 2 ;;
        -w|--width)           width="$2"; shift 2 ;;
        --width=*)            width="${1#*=}"; shift ;;
        -h|--height)          height="$2"; shift 2 ;;
        --height=*)           height="${1#*=}"; shift ;;
        -o|--output)          out="$2"; shift 2 ;;
        --output=*)           out="${1#*=}"; shift ;;
        -b|--background-color) background="$2"; shift 2 ;;
        --background-color=*)  background="${1#*=}"; shift ;;
        -a|--keep-aspect-ratio) shift ;;
        -v|--version)         exec "$resvg_bin" --version ;;
        --help)               exec "$resvg_bin" --help ;;
        --)                   shift ;;
        -*)                   shift ;;
        *)                    input="$1"; shift ;;
    esac
done

case "$fmt" in
    png|PNG) ;;
    *)
        printf '%s\n' "@@SHIM_FORMAT@@" >&2
        exit 1 ;;
esac

set -- --dpi "$dpi"
[ -n "$width" ]      && set -- "$@" --width "$width"
[ -n "$height" ]     && set -- "$@" --height "$height"
[ -n "$background" ] && set -- "$@" --background "$background"

# При чтении со stdin resvg не знает, откуда разрешать относительные ссылки,
# и предупреждает об этом на каждый вызов. Pandoc всегда отдаёт SVG через
# stdin, поэтому указываем текущий каталог явно.
[ -z "$input" ] && set -- "$@" --resources-dir "$PWD"

if [ -n "$out" ]; then
    exec "$resvg_bin" "$@" "${input:--}" "$out"
else
    exec "$resvg_bin" "$@" "${input:--}" -c
fi
SHIM
    # Текст подставляем уже переведённым: шим это самостоятельный скрипт, в нём
    # нет ни каталога, ни функций msg. Язык в нём фиксируется на момент
    # установки — ровно то, что нужно, потому что его stderr читает pandoc, а не
    # тот, кто сейчас запускает апгрейд.
    _shim_msg="$(msgf shim.format '%s')"
    "$PY" - "$path" "$_shim_msg" <<'PYEOF_SHIM'
import sys
path, text = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as fh:
    body = fh.read()
# Строка в шиме стоит внутри двойных кавычек, поэтому %s из каталога
# превращается просто в $fmt: свои кавычки добавлять не надо, они уже есть в
# тексте сообщения.
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(body.replace('@@SHIM_FORMAT@@', text.replace('%s', '$fmt')))
PYEOF_SHIM
    chmod +x "$path"
}

install_resvg() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.zip" \
        "https://github.com/linebender/resvg/releases/download/v${v}/resvg-macos-${A_RESVG}.zip" || return 1
    mkdir -p "$dest/bin"
    unzip -qq -o "$tmp/a.zip" -d "$dest/bin" || return 1
    chmod +x "$dest/bin/resvg"
    write_rsvg_shim "$dest/bin/rsvg-convert" || return 1
    rm -rf "$tmp"
}

install_gws() {
    local v="$1" dest="$2" tmp
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.tgz" \
        "https://github.com/googleworkspace/cli/releases/download/v${v}/google-workspace-cli-${A_GWS}-apple-darwin.tar.gz" || return 1
    mkdir -p "$tmp/x" "$dest/bin"
    tar xzf "$tmp/a.tgz" -C "$tmp/x" || return 1
    # В архиве лежат gws и три текстовых файла, без вложенной папки.
    cp "$tmp/x/gws" "$dest/bin/gws" || return 1
    chmod +x "$dest/bin/gws"
    rm -rf "$tmp"
}

# Апгрейд делаем НЕ переустановкой tarball'а, а родным gcloud components
# update: свежий tarball это 54 МБ голого SDK, а на диске у нас 689 МБ с
# доустановленными компонентами (bq, gsutil, cloud-run-proxy, gcloud-crc32c), и
# распаковка поверх их бы потеряла. Поэтому прошлый каталог переносим под новое
# имя версии и даём SDK обновить себя сам. Следствие: версий у gcloud всегда
# одна, --rollback для него работать не будет (откат есть у самого SDK:
# gcloud components update --version=NNN).
install_gcloud() {
    local v="$1" dest="$2" tmp prev
    # -type d отсекает симлинк current, иначе приняли бы его за прошлую версию
    prev="$(find "$VENDOR_ROOT/gcloud" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    if [ -n "$prev" ] && [ -x "$prev/bin/gcloud" ]; then
        dim "    $(msg vendor.gcloud_inplace)"
        mv "$prev" "$dest" || return 1
        if ! CLOUDSDK_CORE_DISABLE_PROMPTS=1 "$dest/bin/gcloud" components update --quiet; then
            err "$(msgf err.gcloud_upd "$dest")"
            return 1
        fi
        ln -sfn "$dest" "$VENDOR_ROOT/gcloud/current"
        return 0
    fi
    tmp="$(mktemp -d)"
    fetch -o "$tmp/a.tgz" \
        "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${v}-darwin-${A_GCLOUD}.tar.gz" || return 1
    mkdir -p "$tmp/x"
    tar xzf "$tmp/a.tgz" -C "$tmp/x" || return 1
    mkdir -p "$dest"
    ( cd "$tmp/x/google-cloud-sdk" && tar cf - . ) | ( cd "$dest" && tar xf - ) || return 1
    rm -rf "$tmp"
    # Стабильный путь для CLOUDSDK_HOME: плагин gcloud в oh-my-zsh наш каталог в
    # своих search_locations не знает, но переменную уважает, а версию в неё
    # вписывать нельзя — устареет на первом же обновлении.
    ln -sfn "$dest" "$VENDOR_ROOT/gcloud/current"
}

install_tool() {
    case "$1" in
        gh)        install_gh        "$2" "$3" ;;
        go)        install_go        "$2" "$3" ;;
        node)      install_node      "$2" "$3" ;;
        pandoc)    install_pandoc    "$2" "$3" ;;
        yt-dlp)    install_yt_dlp    "$2" "$3" ;;
        terraform) install_terraform "$2" "$3" ;;
        ffmpeg)    install_ffmpeg    "$2" "$3" ;;
        deno)      install_deno      "$2" "$3" ;;
        resvg)     install_resvg     "$2" "$3" ;;
        gws)       install_gws       "$2" "$3" ;;
        gcloud)    install_gcloud    "$2" "$3" ;;
    esac
}

# ------------------------------------------------------------- откат -------

do_rollback() {
    local tool="$1" cur prev
    cur="$(state_get "$tool")"
    prev="$(ls -1 "$VENDOR_ROOT/$tool" 2>/dev/null | sort -V | grep -v "^${cur}$" | tail -1)"
    if [ -z "$prev" ]; then
        err "$(msgf err.no_previous "$tool" "${cur:-$(msg err.nothing)}")"
        return 1
    fi
    link_binaries "$tool" "$prev" || return 1
    state_set "$tool" "$prev"
    ok "$(msgf vendor.rolled_back "$tool" "$cur" "$prev")"
}

# --------------------------------------------------- обновление MacPorts --
#
# Как только часть инвентаря переехала в MacPorts, обновлять надо и его —
# из той же одной команды, иначе переезд создаёт второй забытый менеджер.
#
# Железное правило: только `port -b`, то есть binary-only. Без него любой
# порт, у которого не оказалось архива под Intel, молча уедет в сборку из
# исходников — ровно так librsvg утащил за собой rust и положил машину.
# С -b такой порт просто останется необновлённым, о чём и будет сказано.

# Префикс MacPorts не обязан быть /opt/local — при сборке из исходников его
# задают через --prefix. Ищем port в PATH, потом по типовым местам, а префикс
# выводим из найденного бинарника.
PORT_BIN="$(command -v port 2>/dev/null)"
if [ -z "$PORT_BIN" ]; then
    for _c in /opt/local/bin/port /usr/local/bin/port /opt/mports/bin/port; do
        [ -x "$_c" ] && { PORT_BIN="$_c"; break; }
    done
fi
MP_PREFIX=""
[ -n "$PORT_BIN" ] && MP_PREFIX="$(dirname "$(dirname "$PORT_BIN")")"

# Выполнить от root. Возвращает 97, если получить root нечем.
mp_sudo() {
    if [ "$(id -u)" = "0" ]; then "$@"; return $?; fi
    if sudo -n true 2>/dev/null; then sudo "$@"; return $?; fi
    if [ -t 0 ]; then sudo "$@"; return $?; fi
    return 97
}

# Разбирает `port outdated` и проверяет, есть ли под каждый порт архив ровно
# той версии/ревизии/вариантов, которые хочет дерево. Имя архива у MacPorts
# включает варианты, и buildbot нередко собирает не с дефолтными — так у нас
# 404-ил gnupg2 (+pinentry в дереве против +pinentry_mac в архиве).
mp_report_outdated() {
    MP_OUT_LIST="${1:-}" \
    DARWIN_MAJOR="$DARWIN_MAJOR" UNAME_M="$UNAME_M" PORT_BIN="$PORT_BIN" "$PY" - <<'PYEOF'
import concurrent.futures as cf
import os, re, subprocess, sys

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

tag  = f"darwin_{os.environ['DARWIN_MAJOR']}"
arch = os.environ['UNAME_M']
tty  = sys.stdout.isatty()
def c(code, s):
    return f'\033[{code}m{s}\033[0m' if tty else s

def sh(*a, timeout=120):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ''

PORT = os.environ.get('PORT_BIN') or 'port'
out = sh(PORT, 'outdated')
ports = []
for line in out.splitlines():
    line = line.strip()
    if not line or line.lower().startswith(('the following', 'no installed')):
        continue
    ports.append(line.split()[0])

if not ports:
    print('  ' + c('2', t('mpr.up_to_date')))
    sys.exit(0)

def expected_name(p):
    info = sh(PORT, 'info', '--version', '--revision', p)
    v = re.search(r'version:\s*(\S+)', info)
    if not v:
        return None
    r = re.search(r'revision:\s*(\S+)', info)
    rev = r.group(1) if r else '0'
    defaults = sorted(re.findall(r'^\s*\[\+\](\S+?):', sh(PORT, 'variants', p), re.M))
    return f"{p}-{v.group(1)}_{rev}" + ''.join('+' + d for d in defaults)

def has_archive(p):
    exp = expected_name(p)
    if exp is None:
        return p, None
    try:
        page = subprocess.run(['curl', '-fsS', '--max-time', '25',
                               f'https://packages.macports.org/{p}/'],
                              capture_output=True, text=True, timeout=35).stdout
    except Exception:
        return p, None
    pat = re.escape(exp) + r'\.(?:' + re.escape(tag) + r'|darwin_any|any_any)\.(?:' + re.escape(arch) + r'|noarch)\.tbz2'
    return p, bool(re.search(pat, page))

with cf.ThreadPoolExecutor(max_workers=6) as ex:
    res = dict(ex.map(has_archive, ports))

ok   = [p for p in ports if res.get(p)]
miss = [p for p in ports if res.get(p) is False]
unk  = [p for p in ports if res.get(p) is None]

print('  ' + t('mpr.outdated', len(ports)))
if ok:
    print('    ' + c('32', t('mpr.archive_yes') + ' ') + ', '.join(ok))
if miss:
    print('    ' + c('33', t('mpr.archive_no') + ' ') + ', '.join(miss))
    print('    ' + c('2', t('mpr.skipped_by_b')))
if unk:
    print('    ' + c('2', t('mpr.uncheckable') + ' ') + ', '.join(unk))

# Список тех, у кого архив совпал — их и будем обновлять поштучно.
dst = os.environ.get('MP_OUT_LIST')
if dst:
    with open(dst, 'w') as fh:
        fh.write("\n".join(ok))
sys.exit(1 if ok else 0)
PYEOF
}

macports_upgrade() {
    [ -n "$PORT_BIN" ] || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        dim "  $(msg mp.checkmode)"
        mp_report_outdated
        return 0
    fi

    # --- 1. дерево портов -------------------------------------------------
    # Без selfupdate локальное дерево отстаёт от сборочной фермы, имя архива
    # не совпадает, и port уходит компилировать. Ровно так собрался tesseract
    # 5.4.1, когда на сервере уже лежал бинарник 5.5.3.
    dim "  $(msg mp.selfupdate)"
    mp_sync_out="$(mp_sudo "$PORT_BIN" selfupdate 2>&1)"
    mp_rc=$?
    if [ "$mp_rc" -eq 97 ]; then
        warn "$(msg mp.no_root)"
        dim  "  $(msg mp.run_manually)"
        return 0
    elif [ "$mp_rc" -ne 0 ]; then
        warn "$(msg mp.selfupdate_bad)"
    else
        printf '%s\n' "$mp_sync_out" \
            | grep -iE "ports tree has been updated|MacPorts base version|Installing new" \
            | sed 's/^/    /'
    fi

    # --- 2. что можно обновить -------------------------------------------
    mp_list="$(mktemp)"
    mp_report_outdated "$mp_list"
    mp_has=$?
    if [ "$mp_has" -ne 1 ]; then
        rm -f "$mp_list"
        macports_prune_inactive
        return 0
    fi

    # --- 3. обновляем поштучно -------------------------------------------
    # Пачкой (`upgrade outdated`) первый же порт без архива обрывает всё
    # остальное. Поштучно — неудача одного не мешает прочим.
    dim "  $(msg mp.upgrading)"
    mp_done=0
    mp_fail=""
    while IFS= read -r mp_p; do
        [ -n "$mp_p" ] || continue
        if mp_sudo "$PORT_BIN" -N -b upgrade "$mp_p" >/dev/null 2>&1; then
            ok "    $mp_p"
            mp_done=$((mp_done + 1))
        else
            err "$(msgf mp.upgrade_failed "$mp_p")"
            mp_fail="$mp_fail $mp_p"
        fi
    done < "$mp_list"
    rm -f "$mp_list"

    if [ "$mp_done" -gt 0 ]; then
        SUMMARY="$SUMMARY\n  MacPorts  $(msgf mp.sum_upgraded "$mp_done")"
    fi
    if [ -n "$mp_fail" ]; then
        SUMMARY="$SUMMARY\n  MacPorts  $(msgf mp.sum_failed "$mp_fail")"
        FAILED=1
    fi

    macports_prune_inactive
}

# После апгрейда старые версии остаются неактивными и занимают место.
macports_prune_inactive() {
    local n
    n="$("$PORT_BIN" -q installed inactive 2>/dev/null | grep -c . || true)"
    [ "${n:-0}" -gt 0 ] || return 0
    dim "  $(msgf mp.pruning "$n")"
    if mp_sudo "$PORT_BIN" -N uninstall inactive >/dev/null 2>&1; then
        ok "    $(msg mp.pruned)"
        SUMMARY="$SUMMARY\n  MacPorts  $(msgf mp.pruning "$n")"
    else
        warn "$(msg mp.prune_failed)"
    fi
}

# ------------------------------------------------- слежение за MacPorts ---
#
# Когда MacPorts поднимает билдер под новую платформу, дерево собирается снизу
# вверх: сначала zlib/ncurses/openssl3, потом icu/curl/pcre2. Нужные пакеты —
# листья этого дерева, их архивы появляются последними.
#
# Здесь мы за ними следим. Проверяется сам целевой порт, а не всё его
# замыкание: buildbot MacPorts берётся за порт только когда его зависимости
# уже собраны, поэтому появление архива у листа означает, что и низ готов.
# Глубокая проверка с процентами готовности — отдельный флаг --macports.

# Следим ровно за тем, что стоит в brew ПО ЗАПРОСУ и чему нет вендорского
# бинарника (список = brew leaves --installed-on-request минус переехавшие).
# Зависимости не watch'им намеренно: они приедут сами вместе с портом-листом,
# отдельные строки про них были бы шумом. Срочность не хардкодим — она берётся
# из состояния бутылки в brew на каждом запуске: пока бутылка льётся, спешить
# некуда; как только она пропала, brew начнёт собирать из исходников.
#
# Формат строки: "<порт в MacPorts>:<формула в brew, которую он заменяет>".
# Список пересобирается сам на каждом прогоне (macports_rebuild_watch), так что
# в норме здесь пусто. Вписывать вручную стоит только то, чего ещё нет локально,
# но за чем хочется следить заранее.
MACPORTS_WATCH=""
WATCH_LIST_FILE="$VENDOR_ROOT/.macports-watch.list"

WATCH_STATE="$VENDOR_ROOT/.macports-watch.tsv"

# Общий код проверки. $1 = deep|fast
macports_check() {
    WATCH_LIST="$(printf '%s\n%s' "$MACPORTS_WATCH" "$(cat "$WATCH_LIST_FILE" 2>/dev/null)")" \
    WATCH_STATE="$WATCH_STATE" \
    DARWIN_MAJOR="$DARWIN_MAJOR" UNAME_M="$UNAME_M" MODE="${1:-fast}" \
    PORT_BIN="$PORT_BIN" MP_PREFIX="$MP_PREFIX" \
    "$PY" - <<'PYEOF'
import concurrent.futures as cf
import json, os, re, subprocess, sys, time

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

arch  = os.environ['UNAME_M']
tag   = f"darwin_{os.environ['DARWIN_MAJOR']}.{arch}"
# Архив, пригодный на этой машине. Кроме обычного darwin_<N>.<arch> бывают
# noarch-порты: данные (any_any.noarch), заголовки (darwin_any.noarch) и
# ОС-независимые библиотеки (any_any.<arch>). Без них poppler-data,
# curl-ca-bundle, xorg-xorgproto и libgcc ложно считались несобранными.
ARCH_RE = (r'\.(?:darwin_' + re.escape(os.environ['DARWIN_MAJOR']) +
           r'|darwin_any|any_any)\.(?:' + re.escape(arch) + r'|noarch)\.tbz2')
state = os.environ['WATCH_STATE']
deep  = os.environ.get('MODE') == 'deep'
tty   = sys.stdout.isatty()

def c(code, s):
    return f'\033[{code}m{s}\033[0m' if tty else s

def curl(url, t=25):
    try:
        return subprocess.run(['curl', '-fsS', '--max-time', str(t), url],
                              capture_output=True, text=True, timeout=t + 10).stdout
    except Exception:
        return ''

if not os.environ['WATCH_LIST'].strip():
    # Состояние обязательно обнулить: иначе кэшированный показ на следующем
    # запуске напечатает запись от прошлых времён как актуальную.
    try:
        os.makedirs(os.path.dirname(state), exist_ok=True)
        open(state, 'w').close()
    except Exception:
        pass
    # Пустой список — нормальное состояние, но молчать про него нельзя:
    # надо видеть, что именно ещё держит Homebrew и почему это не уезжает.
    print('  ' + c('32', t('mpc.nothing_left')))
    try:
        formulae = subprocess.run(['brew', 'list', '--formula'],
                                  capture_output=True, text=True, timeout=60).stdout.split()
        casks = subprocess.run(['brew', 'list', '--cask'],
                               capture_output=True, text=True, timeout=60).stdout.split()
        locked = {}
        if casks:
            info = json.loads(subprocess.run(['brew', 'info', '--cask', '--json=v2', *casks],
                                             capture_output=True, text=True, timeout=180).stdout or '{}')
            for ck in info.get('casks') or []:
                for f in (ck.get('depends_on') or {}).get('formula') or []:
                    locked.setdefault(f, []).append(ck['token'])
        print('  ' + c('2', t('mpc.remaining', len(formulae), len(casks))))
        for f, by in sorted(locked.items()):
            print('  ' + c('2', t('mpc.held_by_cask', f, ', '.join(by))))
            print('  ' + c('2', t('mpc.held_note')))
    except Exception:
        pass
    sys.exit(0)

watch = []
for line in os.environ['WATCH_LIST'].splitlines():
    line = line.strip()
    if line:
        port, repl = (line.split(':') + [''])[:2]
        watch.append((port, repl))

# Состояние бутылок в brew — из его же локального кэша, того самого, по
# которому brew решает «лить или собирать». Формула без bottle_checksum уже
# собирается из исходников, значит переезд для неё срочный.
# Выбор payload'а кэша brew. Их может лежать несколько: после апгрейда macOS
# рядом с packages.tahoe остаётся packages.sonoma и т.п. Алфавитный sorted()[0]
# тогда отдал бы payload ЧУЖОЙ ОС, и бутылки считались бы по ней.
# Берём самый свежий по mtime и запоминаем bottle_tag, чтобы было видно, под
# какую платформу посчитано.
def brew_payload():
    import glob
    cache = subprocess.run(['brew', '--cache'], capture_output=True,
                           text=True).stdout.strip()
    pay = glob.glob(os.path.join(cache, 'api/internal/packages.*.jws.json.payload'))
    if not pay:
        return None, None
    pay.sort(key=lambda f: os.path.getmtime(f), reverse=True)
    d = json.loads(open(pay[0]).read().splitlines()[1])
    return d, (d.get('metadata') or {}).get('bottle_tag')

BREW = {}
BREW_TAG = None
try:
    _d, BREW_TAG = brew_payload()
    if _d:
        BREW = _d['formulae']
except Exception:
    BREW = {}

# BREW — это каталог ВСЕХ известных формул, а не установленных. Проверять по
# нему «стоит ли пакет» нельзя: так в команды переезда попадал бы
# `brew uninstall tesseract` для пакета, которого в brew давно нет.
BREW_INSTALLED = set()
try:
    BREW_INSTALLED = set(subprocess.run(['brew', 'list', '--formula'],
                                        capture_output=True, text=True,
                                        timeout=120).stdout.split())
except Exception:
    pass

def brew_state(formula):
    """'source' — brew уже собирает из исходников; 'bottle' — ещё льёт;
       '' — формулы в brew нет вовсе."""
    if formula not in BREW_INSTALLED:
        return ''
    e = BREW.get(formula)
    if e is None:
        return ''
    return 'bottle' if 'bottle_checksum' in e else 'source'


PORT = os.environ.get('PORT_BIN') or ''

def sh(*a):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ''

# Имя, которое запросит port: <порт>-<версия>_<ревизия><+дефолтные варианты>.
# Именно оно должно найтись на сервере — «какой-нибудь архив под платформу»
# ничего не гарантирует: у tesseract лежал 5.5.3 под Intel, а локальное дерево
# стояло на 5.4.1, и port ушёл компилировать.
def tree_name(port):
    if not PORT:
        return None
    info = sh(PORT, 'info', '--version', '--revision', port)
    v = re.search(r'version:\s*(\S+)', info)
    if not v:
        return None
    r = re.search(r'revision:\s*(\S+)', info)
    rev = r.group(1) if r else '0'
    defs = sorted(re.findall(r'^\s*\[\+\](\S+?):', sh(PORT, 'variants', port), re.M))
    return f"{port}-{v.group(1)}_{rev}" + ''.join('+' + d for d in defs)

def archive(port):
    """(состояние, имя, дата) либо None.
       ready — архив ровно под версию из локального дерева портов;
       stale — архив есть, но под другую версию: нужен port selfupdate;
       maybe — MacPorts не установлен, сверять не с чем."""
    out = curl(f'https://packages.macports.org/{port}/')
    if not out:
        return None
    rows = re.findall(
        r'href="([^"]+' + ARCH_RE + r')"[^>]*>[^<]*</a></td>'
        r'<td align="right">([\d-]+ [\d:]+)', out)
    if not rows:
        return None
    rows.sort(key=lambda r: r[1])
    exp = tree_name(port)
    if exp is None:
        return ('maybe',) + rows[-1]
    exact = [r for r in rows if r[0].startswith(exp + '.')]
    if exact:
        return ('ready',) + exact[-1]
    return ('stale',) + rows[-1]

with cf.ThreadPoolExecutor(max_workers=8) as ex:
    got = dict(zip([w[0] for w in watch],
                   ex.map(archive, [w[0] for w in watch])))

# Предыдущее состояние — чтобы показать именно изменения.
prev = {}
try:
    with open(state) as fh:
        for line in fh:
            p = line.rstrip('\n').split('\t')
            if len(p) >= 2:
                prev[p[0]] = p[1]
except FileNotFoundError:
    pass

def state_of(port):
    a = got[port]
    return a[0] if a else 'waiting'

ready  = [w for w in watch if state_of(w[0]) in ('ready', 'maybe')]
stale  = [w for w in watch if state_of(w[0]) == 'stale']
fresh  = [w for w in ready if prev.get(w[0]) not in ('ready', 'maybe')]
urgent = [w for w in watch if brew_state(w[1]) == 'source']

print('  ' + t('mpc.target', c('1', tag), len(watch)))
for port, repl in watch:
    a = got[port]
    st = brew_state(repl)
    if st == 'source':
        why = c('31', t('mpc.why_building'))
    elif st == 'bottle':
        why = c('2', t('mpc.why_bottle'))
    else:
        why = c('2', t('mpc.why_absent'))

    if a and a[0] == 'ready':
        new = c('1;32', ' ' + t('mpc.new')) if (port, repl) in fresh else ''
        print(f"    {c('32', '✓')} {port:13s} → {repl:12s} {t('mpc.has_archive', a[2])}{new}")
    elif a and a[0] == 'maybe':
        new = c('1;32', ' ' + t('mpc.new')) if (port, repl) in fresh else ''
        print(f"    {c('32', '✓')} {port:13s} → {repl:12s} {t('mpc.has_archive', a[2])}{new}")
        print(f"      {c('2', t('mpc.no_mp_compare'))}")
    elif a and a[0] == 'stale':
        print(f"    {c('33', '≈')} {port:13s} → {repl:12s} {c('33', t('mpc.stale_archive'))}")
        print(f"      {c('33', t('mpc.need_selfupd'))}")
        print(f"      {c('2', t('mpc.on_server', a[1]))}")
    else:
        print(f"    {c('2', '·')} {port:13s} → {repl:12s} {t('mpc.no_archive')}   {why}")

if deep:
    print()
    print(c('1', '  ' + t('mpc.deep_head')))
    dep_cache, rdy_cache = {}, {}

    def libdeps(port):
        if port in dep_cache:
            return dep_cache[port]
        r = []
        try:
            for g in json.loads(curl(f'https://ports.macports.org/api/v1/ports/{port}/')).get('dependencies') or []:
                if g.get('type') == 'lib':
                    r = list(g.get('ports') or [])
        except Exception:
            pass
        dep_cache[port] = r
        return r

    def is_ready(port):
        if port not in rdy_cache:
            rdy_cache[port] = archive(port) is not None
        return rdy_cache[port]

    for port, repl in watch:
        seen, frontier = set(), {port}
        for _ in range(3):
            nxt = set()
            with cf.ThreadPoolExecutor(max_workers=8) as ex:
                for d in ex.map(libdeps, frontier):
                    nxt |= set(d)
            seen |= frontier
            frontier = nxt - seen
            if not frontier:
                break
        closure = sorted(seen | frontier)
        with cf.ThreadPoolExecutor(max_workers=10) as ex:
            res = dict(zip(closure, ex.map(is_ready, closure)))
        ok = [p for p in closure if res[p]]
        miss = [p for p in closure if not res[p]]
        pct = 100 * len(ok) // max(len(closure), 1)
        col = '32' if not miss else ('33' if pct >= 70 else '2')
        print(f"    {c(col, f'{pct:3d}%')} {port:14s} {t('mpc.deep_ports', len(ok), len(closure))}")
        if miss and len(miss) <= 12:
            print(c('2', '           ' + t('mpc.deep_waiting', ', '.join(miss))))
        elif miss:
            print(c('2', '           ' + t('mpc.deep_waiting_n', len(miss), ', '.join(miss[:10]) + '…')))

os.makedirs(os.path.dirname(state), exist_ok=True)
with open(state, 'w') as fh:
    for port, _ in watch:
        fh.write(f"{port}\t{state_of(port)}\t{time.strftime('%Y-%m-%d')}\n")

if ready:
    print()
    title = t('mpc.ready_title', len(ready))
    print(c('1;32', '  ╔' + '═' * 66 + '╗'))
    print(c('1;32', '  ║  ' + title.ljust(64) + '║'))
    print(c('1;32', '  ╚' + '═' * 66 + '╝'))
    print()

    have_port = bool(os.environ.get('PORT_BIN'))
    if not have_port:
        print('  ' + t('mpc.mp_missing'))
        print('    ' + t('mpc.mp_step1', os.environ['DARWIN_MAJOR']))
        print('    ' + t('mpc.mp_step2'))
        print()

    # Сколько портов приедет следом. Через `port rdeps`, а не `port -y install`:
    # сухой прогон установки пишет в реестр и без root падает с
    # «attempt to write a readonly database». rdeps только читает.
    _installed = None
    def incoming(port):
        nonlocal_installed = None
        if not PORT:
            return None
        global _MP_INSTALLED
        try:
            _MP_INSTALLED
        except NameError:
            _MP_INSTALLED = {l.split()[0] for l in
                             (x.strip() for x in sh(PORT, '-q', 'installed').splitlines())
                             if l}
        # --no-build обязателен: при установке из архива (-b) build-зависимости
        # не нужны вовсе, а без флага rdeps их считает и завышает цифру втрое.
        tree = sh(PORT, 'rdeps', '--no-build', port)
        if not tree:
            return None
        names = set()
        for line in tree.splitlines():
            line = line.strip()
            if not line or line.startswith('The following'):
                continue
            names.add(line.split()[0])
        todo = names - _MP_INSTALLED
        return len(todo) if todo else 0

    for port, repl in ready:
        tag_new = c('1;32', '   ' + t('mpc.new')) if (port, repl) in fresh else ''
        print(f"  {c('1', port)}{tag_new}")
        n = incoming(port)
        if n is not None:
            print(f"    {c('2', t('mpc.pulls_in', n))}")
        print(f"    {c('32', 'sudo port -b install ' + port)}")
        if repl and brew_state(repl):
            print(f"    {c('32', 'brew uninstall ' + repl)}")
            print(f"    {c('32', 'brew autoremove')}")
        print()

    print('  ' + c('1', t('mpc.say_migrate', ', '.join(p for p, _ in ready))))
    print('  ' + t('mpc.say_migrate2'))
    print('  ' + t('mpc.say_migrate3'))
    print()
    print('  ' + c('2', t('mpc.b_required')))
    print('  ' + c('2', t('mpc.point_of_it',
                            os.environ.get('MP_PREFIX') or '/opt/local')))
    print('  ' + c('2', t('mpc.point_of_it2')))
else:
    print('  ' + c('2', t('mpc.none_ready')))


# Отдельной строкой, независимо от новинок: за что горит прямо сейчас.
if stale:
    print()
    print('  ' + c('33', t('mpc.tree_behind', ', '.join(w[0] for w in stale))))
    print('  ' + c('33', t('mpc.tree_behind2')))

if urgent:
    waiting = [w for w in urgent if state_of(w[0]) != 'ready']
    if waiting:
        names = ', '.join(w[1] for w in waiting)
        print('  ' + c('31', t('mpc.urgent', names)))
PYEOF
}

# Список наблюдения не хардкодится, а пересобирается на каждом прогоне из
# фактического состояния brew. Правило:
#
#   берём brew leaves --installed-on-request  (то, что поставлено осознанно и
#   от чего ничего не зависит — только такое имеет смысл переносить целиком,
#   зависимости приедут сами вместе с портом-листом)
#   минус формулы, которые требуют установленные cask'и — их переезд
#   невозможен: cask завязан именно на брюшную формулу (так у нас
#   python@3.14 держит gcloud-cli)
#
# Имя порта в MacPorts ищется по локальному дереву портов, а не по таблице
# соответствий: brew и MacPorts называют пакеты по-разному (libpq против
# postgresql18, glib против glib2, jpeg-turbo против libjpeg-turbo), и
# угадывать вслепую — тот же тяп-ляп, что уже стоил нам пересборки tesseract.
macports_rebuild_watch() {
    [ -n "$PORT_BIN" ] || return 0
    command -v brew >/dev/null 2>&1 || return 0

    PORT_BIN="$PORT_BIN" WATCH_FILE="$WATCH_LIST_FILE" "$PY" - <<'PYEOF'
import json, os, re, subprocess, sys

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

PORT = os.environ['PORT_BIN']
DEST = os.environ['WATCH_FILE']

def sh(*a, t=90):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=t).stdout
    except Exception:
        return ''

leaves = sh('brew', 'leaves', '--installed-on-request').split()
if not leaves:
    open(DEST, 'w').close()
    sys.exit(0)

# Формулы, которые держат cask'и: переезжать им некуда.
locked = set()
casks = sh('brew', 'list', '--cask').split()
if casks:
    try:
        data = json.loads(sh('brew', 'info', '--cask', '--json=v2', *casks, t=180) or '{}')
        for c in data.get('casks') or []:
            locked |= set((c.get('depends_on') or {}).get('formula') or [])
    except Exception:
        pass

def port_exists(name):
    return bool(re.search(r'version:\s*\S+', sh(PORT, 'info', '--version', name, t=30)))

# Кандидаты на имя порта. Сначала как есть, потом типовые расхождения; всё
# проверяется по дереву, так что ошибиться нельзя — только не найти.
def candidates(brew_name):
    base = brew_name.split('@')[0]
    out = [brew_name, base]
    if '@' in brew_name:
        ver = brew_name.split('@')[1].replace('.', '')
        out += [base + ver, base + ver.rstrip('0')]
    out += [base + '2', base + '3', 'lib' + base, base.replace('lib', '', 1)]
    seen, uniq = set(), []
    for c in out:
        if c and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq

lines, locked_out, no_port = [], [], []
for f in sorted(leaves):
    if f in locked:
        locked_out.append(f)
        continue
    for cand in candidates(f):
        if port_exists(cand):
            lines.append(f"{cand}:{f}")
            break
    else:
        no_port.append(f)

with open(DEST, 'w') as fh:
    fh.write("\n".join(lines))
    if lines:
        fh.write("\n")

if lines:
    print('  ' + t('mpw.rebuilt', len(lines)) + ' '
          + ', '.join(l.split(':')[0] for l in lines))
if locked_out:
    print('  ' + t('mpw.locked_out', ', '.join(locked_out)))
if no_port:
    print('  ' + t('mpw.no_port_name', ', '.join(no_port)))
    print('  ' + "  " + t('mpw.naming_note'))
    print('  ' + "   " + t('mpw.naming_note2'))
PYEOF
}

macports_watch() {
    local today cached pending

    today="$(date +%Y-%m-%d)"

    # Кэш на день — только когда ждать уже нечего. Пока хоть один порт в
    # состоянии waiting, проверяем сеть на каждом запуске: архивы выкладывают
    # ночью, а дневной кэш отложил бы новость до следующих суток. Три запроса
    # стоят секунду, экономить тут нечего.
    pending=0
    if [ -s "$WATCH_STATE" ]; then
        grep -q "$(printf '\t')waiting$(printf '\t')" "$WATCH_STATE" 2>/dev/null && pending=1
    fi

    # Если сгенерированный список пуст, кэш не показываем вовсе — иначе на
    # экран попадёт состояние, которого уже нет.
    if [ ! -s "$WATCH_LIST_FILE" ] && [ -z "$MACPORTS_WATCH" ]; then
        macports_check fast
        mkdir -p "$VENDOR_ROOT"
        printf '%s checked\n' "$today" > "$PROBE_CACHE"
        return 0
    fi

    if [ "$pending" -eq 0 ] && [ -f "$PROBE_CACHE" ] && [ -s "$WATCH_STATE" ]; then
        cached="$(head -1 "$PROBE_CACHE" 2>/dev/null)"
        if [ "${cached%% *}" = "$today" ]; then
            macports_show_cached
            return 0
        fi
    fi

    macports_check fast
    mkdir -p "$VENDOR_ROOT"
    printf '%s checked\n' "$today" > "$PROBE_CACHE"
}

# Печать из сохранённого состояния, без обращений к сети.
macports_show_cached() {
    local port status rest n_ready=0
    while IFS=$'\t' read -r port status rest; do
        [ -n "$port" ] || continue
        if [ "$status" = "ready" ]; then
            printf '    %s✓%s %-14s %s\n' "$C_GREEN" "$C_RESET" "$port" "$(msg mp.archive_yes)"
            n_ready=$((n_ready + 1))
        else
            printf '    %s· %-14s %s%s\n' "$C_DIM" "$port" "$(msg mp.archive_wait)" "$C_RESET"
        fi
    done < "$WATCH_STATE"
    dim "  $(msg mp.cached_today)"
}

# ------------------------------------------ предполётная проверка brew ----
#
# Говорит, что из ожидающих обновлений разольётся готовой бутылкой, а что
# поедет собираться из исходников — и потянет ли за собой тяжёлый тулчейн.
#
# Данные берутся из локального кэша brew — packages.<tag>.jws.json.payload.
# Это тот же файл, по которому brew сам решает, лить бутылку или собирать,
# поэтому ответ точен именно для этой машины и качать ничего не надо.
#
# Повод: librsvg 2.63.0 остался без Intel-бутылки, brew утащил за
# ним rust, а бутстрап rust запускает cargo с -j по числу ядер и на
# HOMEBREW_MAKE_JOBS не смотрит — машина легла на 39 минут.

brew_preflight() {
    command -v brew >/dev/null 2>&1 || return 0

    "$PY" - <<'PYEOF'
import glob, json, os, re, subprocess, sys

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout

cache = sh('brew', '--cache').strip()
found = glob.glob(os.path.join(cache, 'api/internal/packages.*.jws.json.payload'))
if not found:
    print('  ' + t('pf.no_cache'))
    sys.exit(0)
# Самый свежий, а не алфавитно первый: после апгрейда macOS рядом лежит payload
# прошлой ОС, и бутылки посчитались бы не для этой платформы.
found.sort(key=lambda f: os.path.getmtime(f), reverse=True)
try:
    _d = json.loads(open(found[0]).read().splitlines()[1])
    F = _d['formulae']
    BREW_TAG = (_d.get('metadata') or {}).get('bottle_tag')
except Exception as exc:
    print('  ' + t('pf.cache_unread', exc))
    sys.exit(0)

tty = sys.stdout.isatty()
def c(code, s):
    return f'\033[{code}m{s}\033[0m' if tty else s

installed = set(sh('brew', 'list', '--formula').split())
pinned    = set(sh('brew', 'list', '--pinned').split())

rows = []
for line in sh('brew', 'outdated', '--formula', '--verbose').splitlines():
    m = re.match(r'^(\S+)\s+\(([^)]*)\)\s+[<!]+\s+(\S+)', line.strip())
    if not m:
        continue
    name, cur, new = m.groups()
    rows.append((name, cur, new, '[pinned' in line))

live = [r for r in rows if not r[3]]
held = [r for r in rows if r[3]]

if not rows:
    print('  ' + c('2', t('pf.nothing')))
    sys.exit(0)

def has_bottle(n):
    return 'bottle_checksum' in (F.get(n) or {})

def deps(name, include_build):
    out = []
    for d in (F.get(name) or {}).get('stable_dependencies') or []:
        if isinstance(d, str):
            out.append(d)
        elif isinstance(d, dict):
            for k, v in d.items():
                if v == ':test':
                    continue
                if v == ':build' and not include_build:
                    continue
                out.append(k)
    return out

# Что придётся собрать из исходников, если обновлять эту формулу. Формулу без
# бутылки нужно собирать, а значит доставить и её build-зависимости — та самая
# цепочка, которой librsvg притащил rust.
def source_builds(root):
    seen, stack, src = set(), [root], []
    while stack:
        n = stack.pop()
        if n in seen or n not in F:
            continue
        seen.add(n)
        bottled = has_bottle(n)
        if not bottled:
            src.append(n)
        for d in deps(n, include_build=not bottled):
            if d in installed and d != root:
                continue
            stack.append(d)
    return src

HEAVY = {'rust', 'go', 'ghc', 'cabal-install', 'swift', 'gcc', 'lld', 'llvm', 'node'}
def heavy(n):
    return n in HEAVY or n.split('@')[0] in HEAVY

worst = 0
lines = []
for name, cur, new, _ in live:
    src = sorted(source_builds(name))
    hv = [n for n in src if heavy(n)]
    if hv:
        worst = max(worst, 2)
        mark, col = '‼', '31'
        tail = c('31', t('pf.from_source', ', '.join(src))) + c('1;31', '  ' + t('pf.heavy', ', '.join(hv)))
    elif src:
        worst = max(worst, 1)
        mark, col = '!', '33'
        tail = c('33', t('pf.from_source', ', '.join(src)))
    else:
        mark, col = '✓', '32'
        tail = c('2', t('pf.will_pour'))
    lines.append(f"  {c(col, mark)} {name:22s} {cur} → {new}   {tail}")

print('  ' + t('pf.pending', len(live)))
for l in lines:
    print(l)

if held:
    print('  ' + c('2', t('pf.held', ', '.join(n for n, _, _, _ in held))))

if worst == 2:
    print()
    print(c('1;31', '  ' + t('pf.dont_upgrade')))
    print(c('31', '  ' + t('pf.heavy_note1')))
    print(c('31', '  ' + t('pf.heavy_note2')))
    print(c('31', '  ' + t('pf.heavy_note3') + ' ') + c('1;31', t('pf.heavy_cmd')))
elif worst == 1:
    print()
    print(c('33', '  ' + t('pf.minutes')))
PYEOF
}

# ------------------------------------------- brew: кто ещё держит формулы ---
#
# 2026-10-04: разобрались, что все девять оставшихся формул — одно дерево с
# корнем python@3.14, а его держит ровно одна строчка в метаданных cask
# gcloud-cli (depends_on.formula). В рантайме gcloud этим питоном НЕ
# пользуется: /usr/local/bin/python3 и pip3 — симлинки на python.org framework,
# brew там не владеет ничем, а /usr/local/lib/python3.14 вообще не существует.
#
# Отсюда две вещи, за которыми надо следить:
#
#  1. python@3.14 вернётся сам при `brew upgrade --cask gcloud-cli` — cask
#     объявляет зависимость, и brew её переустановит. Вместе с ним приедут
#     openssl@3, xz, lz4, mpdecimal, readline, и у шести из девяти формул
#     Intel-бутылки НЕТ, то есть это сборка из исходников.
#  2. openssl@3 обязан быть закреплён, пока он установлен. Бутылки у него нет
#     (проверено по тому же payload), и любой brew upgrade погонит его собирать.
#     Пин снимается только непосредственно перед uninstall — uninstall на
#     закреплённую формулу отказывается: "is pinned. You must unpin it".

brew_orphan_watch() {
    command -v brew >/dev/null 2>&1 || return 0

    "$PY" - <<'PYEOF'
import glob, json, os, subprocess, sys

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout

tty = sys.stdout.isatty()
def c(code, s):
    return f'\033[{code}m{s}\033[0m' if tty else s

installed = sorted(sh('brew', 'list', '--formula').split())
if not installed:
    print('  ' + c('32', t('ow.none_left')))
    sys.exit(0)

pinned = set(sh('brew', 'list', '--pinned').split())

cache = sh('brew', '--cache').strip()
found = glob.glob(os.path.join(cache, 'api/internal/packages.*.jws.json.payload'))
found.sort(key=lambda f: os.path.getmtime(f), reverse=True)
F = {}
if found:
    try:
        F = json.loads(open(found[0]).read().splitlines()[1])['formulae']
    except Exception:
        F = {}

def has_bottle(n):
    return 'bottle_checksum' in (F.get(n) or {})

# Зависимости формул и — отдельно — формульные зависимости cask'ов. Второе
# невидимо для формульного графа, и именно на этом python@3.14 однажды чуть не
# был снесён из-под gcloud-cli.
info = sh('brew', 'info', '--json=v2', '--installed')
try:
    data = json.loads(info)
except Exception as exc:
    print('  ' + t('ow.info_unread', exc))
    sys.exit(0)

fdeps = {}
for f in data.get('formulae', []):
    fdeps[f['name']] = (f.get('dependencies') or []) + (f.get('build_dependencies') or [])

cdeps = {}
for k in data.get('casks', []):
    fl = (k.get('depends_on') or {}).get('formula') or []
    if fl:
        cdeps[k['token']] = fl

def holders(n):
    out = [t('ow.holder_formula', f) for f, ds in fdeps.items() if n in ds and f != n]
    out += [t('ow.holder_cask', ck) for ck, fl in cdeps.items() if n in fl]
    return out

roots   = [n for n in installed if not holders(n)]
by_cask = [n for n in installed if holders(n) and all(h.startswith('cask ') for h in holders(n))]

print('  ' + t('ow.installed', len(installed)))

if roots:
    print('  ' + c('1;33', t('ow.no_holders')))
    for n in roots:
        print(f"    {c('33', n)}")
    print(f"    {c('32', 'brew uninstall ' + ' '.join(roots))}")
    print(f"    {c('32', 'brew autoremove')}")

# Корень дерева, который держит только cask. Это и есть python@3.14: сносится
# лишь через --ignore-dependencies и вернётся при обновлении самого cask'а.
for n in by_cask:
    who = [h[5:] for h in holders(n) if h.startswith('cask ')]
    pulls = sorted(d for d in fdeps.get(n, []) if d in installed)
    nb = [x for x in [n] + pulls if not has_bottle(x)]
    print()
    print('  ' + c('1;33', t('ow.cask_only', n, ', '.join(who))))
    print('    ' + c('2', t('ow.cask_only_note')))
    if pulls:
        print('    ' + c('2', t('ow.pulls', ', '.join(pulls))))
    if nb:
        print('    ' + c('31', t('ow.no_bottle')))
        print('      ' + c('31', ', '.join(nb)))
    need_unpin = [x for x in [n] + pulls if x in pinned]
    print('    ' + c('1', t('ow.order_matters')))
    for u in need_unpin:
        print(f"      {c('32', 'brew unpin ' + u)}")
    print(f"      {c('32', 'brew uninstall --ignore-dependencies ' + n)}")
    print(f"      {c('32', 'brew autoremove')}")
    print('    ' + c('2', t('ow.will_return', who[0])))

# Главный страж: установленная формула без бутылки и без пина — это заложенная
# сборка из исходников на ближайший brew upgrade.
risky = [n for n in installed if not has_bottle(n) and n not in pinned]
if risky:
    print()
    print('  ' + c('1;31', t('ow.risky')))
    for n in risky:
        print(f"    {c('31', n)}")
    print(f"    {c('32', 'brew pin ' + ' '.join(risky))}")
elif not roots and not by_cask:
    print('  ' + c('32', t('ow.all_safe')))
PYEOF
}

# --------------------------------------------- --bootstrap: новый переезд ---
#
# Режим первого знакомства с машиной. Ничего не меняет — только инвентаризует
# Homebrew и раскладывает каждую установленную формулу по трём маршрутам в том
# порядке, в котором их и надо пробовать:
#
#   1. вендорский бинарник  — если инструмент есть в ALL_TOOLS этого скрипта;
#   2. MacPorts             — если есть одноимённый порт И архив ровно под эту
#                             платформу (точное имя, а не «хоть какой-то»);
#   3. остаётся в brew      — всё прочее, с пометкой, есть ли бутылка.
#
# Приоритет именно такой: вендорский бинарник не требует ни компилятора, ни
# рута, MacPorts с -b не компилирует, а brew на платформе без бутылок означает
# сборку из исходников.
#
# Запускается сам, когда state.tsv пуст — это и значит «вендоров тут ещё не
# было, переезд новый». Интерактивную часть ведёт скилл brew-to-macports:
# скрипт считает факты, решения принимает человек.

bootstrap_report() {
    local n_state=0
    [ -f "$STATE_FILE" ] && n_state="$(grep -c . "$STATE_FILE" 2>/dev/null || echo 0)"

    head1 "$(msg boot.head)"
    printf '  %-10s %s · darwin %s\n' "$(msg boot.platform)" "$UNAME_M" "$DARWIN_MAJOR"
    if [ -n "$PORT_BIN" ]; then
        printf '  %-10s %s %s\n' "$(msg boot.macports)" "$PORT_BIN" "$(msgf boot.mp_prefix "$MP_PREFIX")"
    else
        printf '  %-10s %s%s%s %s\n' "$(msg boot.macports)" "$C_YELLOW" "$(msg boot.mp_missing)" "$C_RESET" "$(msg boot.mp_skipped)"
        printf '             %s\n' "\$(msg boot.mp_pkg)"
    fi
    printf '  %s %s\n' "$(msg boot.state)" "$n_state"
    if [ -n "$CONFIG_FILE" ]; then
        printf '  %-10s %s\n' "$(msg boot.config)" "$CONFIG_FILE"
    else
        printf '  %-10s %s%s%s %s\n' "$(msg boot.config)" "$C_DIM" "$(msg boot.no_config)" "$C_RESET" "$(msg boot.defaults)"
    fi
    printf '\n'

    command -v brew >/dev/null 2>&1 || {
        ok "  $(msg boot.no_brew)"
        return 0
    }

    ALL_TOOLS="$ALL_TOOLS" DARWIN_MAJOR="$DARWIN_MAJOR" UNAME_M="$UNAME_M" \
    PORT_BIN="$PORT_BIN" "$PY" - <<'PYEOF'
import concurrent.futures as cf
import json, os, re, subprocess, sys

sys.path.insert(0, os.environ.get('I18N_LIB', ''))
from i18n import t          # каталог сообщений, см. lib/i18n.py

tty = sys.stdout.isatty()
def c(code, s):
    return f'\033[{code}m{s}\033[0m' if tty else s

def sh(*a, t=180):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=t).stdout
    except Exception:
        return ''

PORT = os.environ.get('PORT_BIN') or ''
arch = os.environ['UNAME_M']
ARCH_RE = (r'\.(?:darwin_' + re.escape(os.environ['DARWIN_MAJOR']) +
           r'|darwin_any|any_any)\.(?:' + re.escape(arch) + r'|noarch)\.tbz2')

installed = sorted(sh('brew', 'list', '--formula').split())
casks     = sorted(sh('brew', 'list', '--cask').split())
if not installed and not casks:
    print('  ' + c('32', t('bs.brew_empty')))
    sys.exit(0)

# Бутылки — из того же кэша, по которому brew решает «лить или собирать».
F, TAG = {}, None
try:
    import glob
    cache = sh('brew', '--cache').strip()
    pay = glob.glob(os.path.join(cache, 'api/internal/packages.*.jws.json.payload'))
    pay.sort(key=lambda f: os.path.getmtime(f), reverse=True)
    if pay:
        d = json.loads(open(pay[0]).read().splitlines()[1])
        F, TAG = d['formulae'], (d.get('metadata') or {}).get('bottle_tag')
except Exception:
    pass

print('  ' + t('bs.inventory', len(installed), len(casks))
      + (t('bs.bottle_tag', TAG) if TAG else ''))
if not F:
    print('  ' + c('33', t('bs.cache_unread')))
print()

VENDOR = set(os.environ['ALL_TOOLS'].split())

# Кто кого держит: формулы плюс формульные зависимости cask'ов. Второе невидимо
# для формульного графа и однажды почти стоило нам python@3.14 из-под gcloud-cli.
fdeps, cdeps = {}, {}
try:
    data = json.loads(sh('brew', 'info', '--json=v2', '--installed') or '{}')
    for f in data.get('formulae', []):
        fdeps[f['name']] = (f.get('dependencies') or []) + (f.get('build_dependencies') or [])
    for k in data.get('casks', []):
        fl = (k.get('depends_on') or {}).get('formula') or []
        if fl:
            cdeps[k['token']] = fl
except Exception:
    pass

def holders(n):
    return ([t('ow.holder_formula', f) for f, ds in fdeps.items() if n in ds and f != n]
            + [t('ow.holder_cask', ck) for ck, fl in cdeps.items() if n in fl])

# --- MacPorts: порт существует И архив ровно под эту платформу ---------------
# Имя архива собирается из версии, ревизии и ДЕФОЛТНЫХ вариантов. Проверять
# «есть хоть какой-то архив» нельзя: так tesseract однажды показался готовым,
# а на деле дерево хотело версию, которой на зеркале не было, и порт уехал
# компилироваться. Вариант, отличный от дефолтного, меняет имя и архива не
# найдёт — так было с gnupg2 (+pinentry против +pinentry_mac).
def mp_status(name):
    if not PORT:
        return ('no_macports', '')
    if not sh(PORT, 'info', '--name', '--line', name, t=60).strip():
        return ('no_port', '')
    v = sh(PORT, 'info', '--version', '--line', name, t=60).strip()
    r = sh(PORT, 'info', '--revision', '--line', name, t=60).strip() or '0'
    if not v:
        return ('no_port', '')
    defs = sorted(re.findall(r'^\s*\[\+\](\S+?):', sh(PORT, 'variants', name, t=60), re.M))
    exp = f'{name}-{v}_{r}' + ''.join('+' + d for d in defs)
    page = sh('curl', '-fsS', '--max-time', '25',
              f'https://packages.macports.org/{name}/', t=40)
    rows = re.findall(re.escape(name) + r'-[^"<>]*?' + ARCH_RE, page)
    if any(x.startswith(exp + '.') for x in rows):
        return ('archive', exp)
    if rows:
        return ('archive_stale', exp)
    return ('no_archive', exp)

targets = [n for n in installed if n not in VENDOR]
mp = {}
if targets and PORT:
    print('  ' + c('2', t('bs.probing', len(targets))))
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        for n, res in zip(targets, ex.map(mp_status, targets)):
            mp[n] = res
    print()

route_vendor, route_mp, route_stay = [], [], []
for n in installed:
    bottled = 'bottle_checksum' in (F.get(n) or {})
    if n in VENDOR:
        route_vendor.append((n, bottled))
        continue
    st, exp = mp.get(n, ('no_macports', ''))
    if st == 'archive':
        route_mp.append((n, bottled, exp))
    else:
        route_stay.append((n, bottled, st, exp))

def mark(bottled):
    return c('2', t('bs.bottled')) if bottled else c('31', t('bs.not_bottled'))

if not installed:
    print('  ' + c('32', t('bs.only_casks')))

if route_vendor:
    print('  ' + c('1;32', t('bs.route1', len(route_vendor))))
    print('     ' + c('2', t('bs.route1_note')))
    for n, b in route_vendor:
        print(f'     {c("32", n):<28} {mark(b)}')
    print(f'     {c("32", "upgrade_vendor_packages --only " + ",".join(n for n, _ in route_vendor))}')
    print(f'     {c("32", "brew uninstall " + " ".join(n for n, _ in route_vendor))}   ' + t('bs.after_check'))
    print()

if route_mp:
    print('  ' + c('1;32', t('bs.route2', len(route_mp))))
    print('     ' + c('2', t('bs.route2_note')))
    for n, b, exp in route_mp:
        print(f'     {c("32", n):<28} {mark(b)}')
        print(f'       {c("2", exp)}')
    print(f'     {c("32", "sudo " + (PORT or "port") + " -b install " + " ".join(n for n, _, _ in route_mp))}')
    print()

if route_stay:
    why = {'no_port':       t('bs.why_no_port'),
           'no_archive':    t('bs.why_no_archive'),
           'archive_stale': t('bs.why_stale'),
           'no_macports':   t('bs.why_no_mp')}
    print('  ' + c('1;33', t('bs.route3', len(route_stay))))
    for n, b, st, exp in route_stay:
        h = holders(n)
        tail = c('2', '← ' + ', '.join(h)) if h else c('33', t('bs.nobody_holds'))
        print(f'     {n:<28} {mark(b)}')
        print(f'       {c("2", why.get(st, st))}  {tail}')
    risky = [n for n, b, _, _ in route_stay if not b]
    if risky:
        print()
        print('     ' + c('1;31', t('bs.risky1')))
        print('     ' + c('31', t('bs.risky2')))
        print(f'     {c("32", "brew pin " + " ".join(risky))}')
    print()

if cdeps:
    print('  ' + c('1;33', t('bs.cask_pulls')))
    for ck, fl in sorted(cdeps.items()):
        print(f'     cask {c("33", ck)} → {", ".join(fl)}')
    print()

if installed:
    print('  ' + c('1', t('bs.order1')))
    print('  ' + c('1', t('bs.order2')))
PYEOF
}

# ----------------------------------------- brew casks: только мажоры -------
#
# Homebrew не умеет «обновляй только мажоры». Что он умеет — это pin: у
# закреплённого cask'а brew upgrade не трогает вообще (cask/upgrade.rb
# выкидывает pinned из списка даже когда cask назван явно). Отсюда схема:
# держим cask постоянно закреплённым, а здесь раз в запуск сравниваем версии
# и снимаем закрепление ровно на время мажорного апгрейда.
#
# Зачем: крупные GUI-приложения выкатывают патч чуть ли не каждый день, и
# каждый такой патч — это перекачка установщика целиком, нередко в несколько
# сотен мегабайт, и переустановка приложения.

BREW_PREFIX=""
cask_available() {
    command -v brew >/dev/null 2>&1 || return 1
    [ -n "$BREW_PREFIX" ] || BREW_PREFIX="$(brew --prefix)"
    [ -n "$BREW_PREFIX" ]
}

# Печатает "<версия в каталоге>\t<имя .app>" для cask'а.
cask_info() {
    brew info --cask --json=v2 "$1" 2>/dev/null | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)["casks"][0]
except Exception:
    sys.exit(1)
app = ""
for a in d.get("artifacts") or []:
    if isinstance(a, dict) and a.get("app"):
        first = a["app"][0]
        if isinstance(first, str):
            app = first
            break
print("%s\t%s" % (d.get("version") or "", app))
'
}

# Версия, которая реально установлена. Такие приложения умеют обновлять себя
# сами, поэтому бандл в /Applications бывает новее записи в Caskroom — верим
# бандлу, Caskroom оставляем как запасной вариант.
cask_installed_version() {
    local token="$1" app="$2" v plist b
    v="$(brew list --cask --versions "$token" 2>/dev/null | awk '{print $2}')"
    if [ -n "$app" ]; then
        for plist in "/Applications/$app/Contents/Info.plist" \
                     "$HOME/Applications/$app/Contents/Info.plist"; do
            [ -f "$plist" ] || continue
            b="$(/usr/bin/defaults read "$plist" CFBundleShortVersionString 2>/dev/null)"
            [ -n "$b" ] && { v="$b"; break; }
        done
    fi
    printf '%s' "$v"
}

# Закрепление cask'а — это симлинк в $(brew --prefix)/var/homebrew/pinned_casks.
cask_pinned() {
    [ -n "$BREW_PREFIX" ] && [ -L "$BREW_PREFIX/var/homebrew/pinned_casks/$1" ]
}

do_casks() {
    local list="$1" token line latest app cur rel action

    cask_available || return 0
    [ -n "$(printf '%s' "$list" | tr -d ' ')" ] || return 0

    head1 "$(msg cask.head)"

    for token in $list; do
        printf '%s%-12s%s ' "$C_CYAN" "$token" "$C_RESET"

        line="$(cask_info "$token")"
        if [ -z "$line" ]; then
            printf '\n'; err "$(msgf cask.no_data "$token")"
            SUMMARY="$SUMMARY\n  $token  $(msg sum.request_error)"
            FAILED=1
            continue
        fi
        latest="${line%%	*}"
        app="${line#*	}"

        cur="$(cask_installed_version "$token" "$app")"
        if [ -z "$cur" ]; then
            printf '%s\n' "$(msg cask.not_installed)"
            dim "    $(msgf cask.install_hint "$token")"
            continue
        fi

        rel="$(ver_relation "$cur" "$latest")"
        case "$rel" in
            same)  msgl cask.latest "$cur"; action="skip" ;;
            older) msgl cask.ours_newer "$latest" "$cur"; action="skip" ;;
            newer-major)
                printf '%s%s%s\n' "$C_YELLOW" "$(msgf cask.major "$cur" "$latest")" "$C_RESET"
                action="upgrade" ;;
            newer-minor|newer-patch)
                if [ "$INCLUDE_PATCH" -eq 1 ]; then
                    msgl cask.taken_patch "$cur" "$latest" "${rel#newer-}"
                    action="upgrade"
                else
                    printf '%s%s%s\n' "$C_DIM" "$(msgf cask.not_major "$cur" "$latest")" "$C_RESET"
                    action="skip"
                    SUMMARY="$SUMMARY\n  $token  $cur → $latest  $(msg cask.sum_skipped)"
                fi ;;
            *) msgl cask.odd_version "$cur" "$latest"; action="skip" ;;
        esac

        if [ "$action" = "upgrade" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                SUMMARY="$SUMMARY\n  $token  $cur → $latest  $(msg cask.would_upgrade)"
            else
                dim "    $(msg cask.unpinning)"
                brew unpin --cask "$token" >/dev/null 2>&1
                if brew upgrade --cask "$token"; then
                    ok "    $(msgf cask.upgraded "$token" "$latest")"
                    SUMMARY="$SUMMARY\n  $token  $cur → $latest  $(msg cask.sum_upgraded)"
                else
                    err "$(msgf cask.upgrade_failed "$token")"
                    SUMMARY="$SUMMARY\n  $token  $(msg cask.sum_error)"
                    FAILED=1
                fi
            fi
        fi

        # Закрепление восстанавливаем всегда — и после апгрейда, и если его не
        # было: это единственное, что удерживает brew upgrade от ежедневной
        # перекачки патчей.
        if cask_pinned "$token"; then
            [ "$action" = "upgrade" ] && dim "    $(msg cask.pinned)"
        elif [ "$DRY_RUN" -eq 1 ]; then
            warn "$(msgf cask.not_pinned "$token" "$token")"
        else
            if brew pin --cask "$token" >/dev/null 2>&1; then
                dim "    $(msg cask.pinned_note)"
            else
                warn "$(msgf cask.pin_failed "$token" "$token")"
            fi
        fi
    done
}

# ------------------------------------------------------------- список -----

do_list() {
    head1 "$(msgf list.head "$VENDOR_ROOT")"
    if [ ! -s "$STATE_FILE" ]; then
        dim "  $(msg list.empty)"
        return 0
    fi
    # printf выравнивает по байтам, а не по символам, поэтому кириллическую
    # шапку выводим literal-строкой с уже проставленными пробелами.
    printf '  %s\n' "$(msg list.header)"
    while IFS=$'\t' read -r t v d; do
        [ -n "$t" ] || continue
        printf '  %-12s %-16s %-20s %s\n' "$t" "$v" "$d" "$VENDOR_ROOT/$t/$v"
    done < "$STATE_FILE"
}

# --------------------------------------------------------------- main -----

if [ -n "$ROLLBACK" ]; then
    do_rollback "$ROLLBACK"
    exit $?
fi

if [ "$ONLY" = "__list__" ]; then
    do_list
    exit 0
fi

if [ "$ONLY" = "__macports__" ]; then
    head1 "$(msg mp.head_ready)"
    macports_rebuild_watch
    macports_check deep
    mkdir -p "$VENDOR_ROOT"
    printf '%s checked\n' "$(date +%Y-%m-%d)" > "$PROBE_CACHE"
    exit 0
fi

if [ "$ONLY" = "__bootstrap__" ]; then
    bootstrap_report
    exit 0
fi

if [ "$ONLY" = "__preflight__" ]; then
    head1 "$(msg brew.head_preflight)"
    brew_preflight
    printf '\n'
    head1 "$(msg brew.head_holders)"
    brew_orphan_watch
    exit 0
fi

# Пустой state.tsv означает, что вендорских бинарников на этой машине ещё не
# было, то есть переезд новый. Гнать полный прогон вслепую не надо — сначала
# инвентаризация, решения принимает человек (скилл brew-to-macports).
if [ -z "$ONLY" ] && [ ! -s "$STATE_FILE" ]; then
    warn "$(msg fresh.warn)"
    info "  $(msgf fresh.hint1 "$(basename "$0")")"
    info "  $(msg fresh.hint2)"
    info "  $(msg fresh.hint3)"
    exit 0
fi

TOOLS="${ONLY:-$ALL_TOOLS}"

# --only может назвать как вендорский инструмент, так и cask — раскладываем
# по двум спискам. Без --only берём и то, и другое целиком.
CASKS=""
_tools=""
for _t in $TOOLS; do
    case " $MAJOR_ONLY_CASKS " in
        *" $_t "*) CASKS="$CASKS $_t" ;;
        *)         _tools="$_tools $_t" ;;
    esac
done
TOOLS="$_tools"
[ -n "$ONLY" ] || CASKS="$MAJOR_ONLY_CASKS"

mkdir -p "$VENDOR_ROOT" "$BIN_DIR"

head1 "$(msgf vendor.head "$UNAME_M" "$DARWIN_MAJOR")"
if [ "$DRY_RUN" -eq 1 ]; then
    dim "$(msg vendor.checkmode)"
fi
printf '\n'

SUMMARY=""
FAILED=0

for tool in $TOOLS; do
    case " $ALL_TOOLS " in
        *" $tool "*) ;;
        *) err "$(msgf err.no_tool_name "$tool")"; FAILED=1; continue ;;
    esac

    printf '%s%-12s%s ' "$C_CYAN" "$tool" "$C_RESET"

    new="$(latest_version "$tool" 2>/dev/null)"
    if [ -z "$new" ]; then
        printf '\n'; err "$(msgf err.no_version "$tool")"
        SUMMARY="$SUMMARY\n  $tool  $(msg sum.request_error)"
        FAILED=1
        continue
    fi

    cur="$(state_get "$tool")"
    policy="$(version_policy "$tool")"

    if [ -z "$cur" ]; then
        printf '%s\n' "$(msgf vendor.not_present "$new")"
        action="install"
    else
        rel="$(ver_relation "$cur" "$new")"
        case "$rel" in
            same)        msgl vendor.latest "$cur"; action="skip" ;;
            older)       msgl vendor.ours_newer "$new" "$cur"; action="skip" ;;
            newer-patch)
                if [ "$policy" = "always" ] || [ "$INCLUDE_PATCH" -eq 1 ]; then
                    msgl vendor.patch "$cur" "$new"; action="install"
                else
                    printf '%s%s%s\n' "$C_DIM" "$(msgf vendor.patch_skip "$cur" "$new")" "$C_RESET"
                    action="skip"
                    SUMMARY="$SUMMARY\n  $tool  $cur → $new  $(msg sum.skipped_patch)"
                fi ;;
            newer-minor) printf '%s%s%s\n' "$C_YELLOW" "$(msgf vendor.minor "$cur" "$new")" "$C_RESET"; action="install" ;;
            newer-major) printf '%s%s%s\n' "$C_YELLOW" "$(msgf vendor.major "$cur" "$new")" "$C_RESET"; action="install" ;;
            *)           msgl vendor.odd_version "$cur" "$new"; action="skip" ;;
        esac
    fi

    [ "$action" = "install" ] || continue

    if [ "$DRY_RUN" -eq 1 ]; then
        SUMMARY="$SUMMARY\n  $tool  ${cur:-—} → $new  $(msg sum.would_install)"
        continue
    fi

    dest="$VENDOR_ROOT/$tool/$new"
    if [ -d "$dest" ] && [ -d "$dest/bin" ]; then
        dim "    $(msgf vendor.unpacked "$new")"
    else
        rm -rf "$dest"
        dim "    $(msg vendor.downloading)"
        if ! install_tool "$tool" "$new" "$dest"; then
            err "$(msgf err.install "$tool")"
            rm -rf "$dest"
            SUMMARY="$SUMMARY\n  $tool  $(msg sum.install_error)"
            FAILED=1
            continue
        fi
    fi

    if ! link_binaries "$tool" "$new"; then
        err "$(msgf err.symlinks "$tool")"
        SUMMARY="$SUMMARY\n  $tool  $(msg sum.symlink_error)"
        FAILED=1
        continue
    fi

    state_set "$tool" "$new"
    prune_old "$tool" "$KEEP_VERSIONS"
    ok "    $(msgf vendor.ready "$tool" "$new")"
    SUMMARY="$SUMMARY\n  $tool  ${cur:-—} → $new  $(msg sum.installed)"
done

do_casks "$CASKS"

head1 "$(msg brew.head_preflight)"
brew_preflight

head1 "$(msg brew.head_holders)"
brew_orphan_watch

if [ -n "$SUMMARY" ]; then
    head1 "$(msg result.head)"
    printf '%b\n' "$SUMMARY"
else
    head1 "$(msg result.head)"
    dim "  $(msg result.nothing)"
fi

printf '\n'
if [ -n "$PORT_BIN" ]; then
    head1 "$(msg mp.head_upgrade)"
    macports_upgrade
fi

head1 "$(msg mp.head_watch)"
macports_rebuild_watch
macports_watch

exit $FAILED
