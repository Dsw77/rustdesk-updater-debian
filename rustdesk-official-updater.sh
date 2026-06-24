#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

UPDATE_DESKTOP="${UPDATE_DESKTOP:-1}"
UPDATE_SERVER="${UPDATE_SERVER:-1}"

LOCKFILE="/run/rustdesk-official-updater.lock"

log() {
    printf '[%s] %s\n' "$(date -Is)" "$*" >&2
}

fail() {
    log "ERROR: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

need_cmd bash
need_cmd curl
need_cmd jq
need_cmd sha256sum
need_cmd dpkg
need_cmd dpkg-query
need_cmd apt-get
need_cmd flock

if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root"
fi

exec 9>"${LOCKFILE}"
flock -n 9 || {
    log "Another updater instance is already running; exiting."
    exit 0
}

WORKDIR="$(mktemp -d /tmp/rustdesk-update-XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

github_api() {
    local url="$1"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl -fsSL --retry 3 \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "$url"
    else
        curl -fsSL --retry 3 \
            -H "Accept: application/vnd.github+json" \
            "$url"
    fi
}

latest_release_json() {
    local repo="$1"
    github_api "https://api.github.com/repos/${repo}/releases/latest"
}

download_and_verify() {
    local name="$1"
    local url="$2"
    local digest="$3"

    local file="${WORKDIR}/${name}"

    log "Downloading ${name}"
    curl -fL --retry 3 -o "${file}" "${url}"

    if [[ -n "${digest}" && "${digest}" != "null" ]]; then
        if [[ "${digest}" == sha256:* ]]; then
            local expected="${digest#sha256:}"
            local actual
            actual="$(sha256sum "${file}" | awk '{print $1}')"

            if [[ "${actual}" != "${expected}" ]]; then
                fail "SHA256 mismatch for ${name}"
            fi

            log "SHA256 verified for ${name}"
        else
            log "Asset digest exists but is not sha256; skipping digest verification: ${digest}"
        fi
    else
        log "No GitHub asset digest found for ${name}; continuing without digest verification."
    fi

    printf '%s\n' "${file}"
}

asset_lines_from_json() {
    local json="$1"
    local regex="$2"

    jq -r --arg re "${regex}" '
        .assets[]
        | select(.name | test($re; "i"))
        | [.name, .browser_download_url, (.digest // "")]
        | @tsv
    ' <<<"${json}"
}

first_asset_line_from_json() {
    local json="$1"
    local regex="$2"

    asset_lines_from_json "${json}" "${regex}" | head -n1
}

restart_service_if_present() {
    local svc="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi

    if systemctl cat "${svc}" >/dev/null 2>&1; then
        log "Restarting ${svc}"
        systemctl try-restart "${svc}" || true
    fi
}

desktop_asset_regex() {
    local arch
    arch="$(dpkg --print-architecture)"

    case "${arch}" in
        amd64)
            echo '^rustdesk-.*(x86_64|amd64)\.deb$'
            ;;
        arm64)
            echo '^rustdesk-.*(aarch64|arm64)\.deb$'
            ;;
        armhf)
            echo '^rustdesk-.*(armv7|armhf).*\.deb$'
            ;;
        *)
            fail "Unsupported Debian architecture for RustDesk desktop: ${arch}"
            ;;
    esac
}

server_deb_arch() {
    local arch
    arch="$(dpkg --print-architecture)"

    case "${arch}" in
        amd64)
            echo "amd64"
            ;;
        arm64)
            echo "arm64"
            ;;
        armhf)
            echo "armhf"
            ;;
        *)
            fail "Unsupported Debian architecture for RustDesk Server .deb packages: ${arch}"
            ;;
    esac
}

update_rustdesk_desktop() {
    log "Checking RustDesk desktop release"

    local json tag version installed regex line name url digest file

    json="$(latest_release_json "rustdesk/rustdesk")"

    tag="$(jq -r '.tag_name' <<<"${json}")"
    version="${tag#v}"

    installed="$(dpkg-query -W -f='${Version}' rustdesk 2>/dev/null || true)"

    if [[ -n "${installed}" ]] && dpkg --compare-versions "${installed}" ge "${version}"; then
        log "RustDesk desktop already up to date: installed=${installed}, latest=${version}"
        return 0
    fi

    regex="$(desktop_asset_regex)"
    line="$(first_asset_line_from_json "${json}" "${regex}")"

    if [[ -z "${line}" ]]; then
        fail "Could not find RustDesk desktop .deb asset matching regex: ${regex}"
    fi

    IFS=$'\t' read -r name url digest <<<"${line}"

    log "RustDesk desktop update available: installed=${installed:-none}, latest=${version}, asset=${name}"

    file="$(download_and_verify "${name}" "${url}" "${digest}")"

    apt-get update -qq
    apt-get install -y "${file}"

    log "RustDesk desktop installed/updated to ${version}"
}

update_rustdesk_server() {
    log "Checking RustDesk Server .deb release"

    local json tag version deb_arch regex

    json="$(latest_release_json "rustdesk/rustdesk-server")"

    tag="$(jq -r '.tag_name' <<<"${json}")"
    version="${tag#v}"
    deb_arch="$(server_deb_arch)"

    local packages=(
        rustdesk-server-hbbs
        rustdesk-server-hbbr
        rustdesk-server-utils
    )

    local all_current=1
    local pkg installed

    for pkg in "${packages[@]}"; do
        installed="$(dpkg-query -W -f='${Version}' "${pkg}" 2>/dev/null || true)"

        if [[ -z "${installed}" ]]; then
            all_current=0
            log "${pkg} is not installed; latest=${version}"
        elif dpkg --compare-versions "${installed}" ge "${version}"; then
            log "${pkg} already up to date: installed=${installed}, latest=${version}"
        else
            all_current=0
            log "${pkg} needs update: installed=${installed}, latest=${version}"
        fi
    done

    if [[ "${all_current}" == "1" ]]; then
        log "RustDesk Server .deb packages already up to date: ${version}"
        return 0
    fi

    regex="^rustdesk-server-(hbbs|hbbr|utils)_[^_]+_${deb_arch}\.deb$"

    declare -A asset_name
    declare -A asset_url
    declare -A asset_digest

    local name url digest pkgname

    while IFS=$'\t' read -r name url digest; do
        pkgname="${name%%_*}"

        asset_name["${pkgname}"]="${name}"
        asset_url["${pkgname}"]="${url}"
        asset_digest["${pkgname}"]="${digest}"
    done < <(asset_lines_from_json "${json}" "${regex}")

    local files=()

    for pkg in "${packages[@]}"; do
        if [[ -z "${asset_url[$pkg]:-}" ]]; then
            fail "Could not find official .deb asset for ${pkg}, arch=${deb_arch}, regex=${regex}"
        fi

        log "Selected ${asset_name[$pkg]}"
        files+=( "$(download_and_verify "${asset_name[$pkg]}" "${asset_url[$pkg]}" "${asset_digest[$pkg]}")" )
    done

    log "Installing/updating RustDesk Server .deb packages to ${version}"

    apt-get update -qq
    apt-get install -y "${files[@]}"

    log "RustDesk Server .deb packages installed/updated to ${version}"

    restart_service_if_present "rustdesk-server-hbbs.service"
    restart_service_if_present "rustdesk-server-hbbr.service"
    restart_service_if_present "rustdesk-hbbs.service"
    restart_service_if_present "rustdesk-hbbr.service"
    restart_service_if_present "hbbs.service"
    restart_service_if_present "hbbr.service"
}

if [[ "${UPDATE_DESKTOP}" == "1" ]]; then
    update_rustdesk_desktop
fi

if [[ "${UPDATE_SERVER}" == "1" ]]; then
    update_rustdesk_server
fi

log "Done"
