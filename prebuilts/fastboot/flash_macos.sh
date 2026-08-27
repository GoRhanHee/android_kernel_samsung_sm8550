#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLATFORM_TOOLS_CACHE="${SCRIPT_DIR}/.platform-tools"
PLATFORM_TOOLS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
FASTBOOT=${FASTBOOT-}
DOWNLOAD_DIR=

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

confirm() {
    prompt=$1

    while :; do
        printf '%s [Y/N] then press Enter: ' "${prompt}"
        IFS= read -r answer || return 1
        case "${answer}" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) printf '%s\n' 'Please enter Y or N, then press Enter.' >&2 ;;
        esac
    done
}

resolve_fastboot() {
    requested=$1

    if [ -n "${requested}" ]; then
        if [ -x "${requested}" ]; then
            printf '%s\n' "${requested}"
            return 0
        fi
        if command_exists "${requested}"; then
            command -v "${requested}"
            return 0
        fi
    fi

    for candidate in \
        "${SCRIPT_DIR}/platform-tools/fastboot" \
        "${PLATFORM_TOOLS_CACHE}/platform-tools/fastboot"; do
        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    command_exists fastboot || return 1
    command -v fastboot
}

cleanup() {
    if [ -n "${DOWNLOAD_DIR}" ] && [ -d "${DOWNLOAD_DIR}" ]; then
        rm -rf -- "${DOWNLOAD_DIR}"
    fi
}
trap cleanup EXIT HUP INT TERM

download_archive() {
    archive=$1

    if command_exists curl; then
        curl -fL --retry 3 --connect-timeout 15 -o "${archive}" "${PLATFORM_TOOLS_URL}" ||
            die "could not download Android platform-tools with curl"
    elif command_exists wget; then
        wget -O "${archive}" "${PLATFORM_TOOLS_URL}" ||
            die "could not download Android platform-tools with wget"
    elif command_exists python3; then
        python3 -c 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' \
            "${PLATFORM_TOOLS_URL}" "${archive}" ||
            die "could not download Android platform-tools with Python"
    else
        die "curl, wget, or python3 is required to download Android platform-tools"
    fi
}

extract_archive() {
    archive=$1

    if command_exists unzip; then
        unzip -q -o "${archive}" -d "${PLATFORM_TOOLS_CACHE}" ||
            die "could not extract Android platform-tools with unzip"
    elif command_exists python3; then
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
            "${archive}" "${PLATFORM_TOOLS_CACHE}" ||
            die "could not extract Android platform-tools with Python"
    else
        die "unzip or python3 is required to extract Android platform-tools"
    fi
}

download_platform_tools() {
    DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gorhanhee-platform-tools.XXXXXX") ||
        die "could not create a temporary directory"
    archive="${DOWNLOAD_DIR}/platform-tools.zip"

    printf '%s\n' "fastboot was not found; downloading official Android platform-tools..."
    mkdir -p "${PLATFORM_TOOLS_CACHE}" ||
        die "could not create the platform-tools cache directory"
    download_archive "${archive}"
    extract_archive "${archive}"

    for executable in adb fastboot; do
        chmod +x "${PLATFORM_TOOLS_CACHE}/platform-tools/${executable}" ||
            die "could not make ${executable} executable"
    done
}

FASTBOOT=$(resolve_fastboot "${FASTBOOT}" || true)
if [ -z "${FASTBOOT}" ]; then
    confirm 'fastboot was not found; download official Android platform-tools?' ||
        die 'platform-tools download cancelled'
    download_platform_tools
    FASTBOOT=$(resolve_fastboot '' || true)
fi
[ -n "${FASTBOOT}" ] || die "fastboot is unavailable"

flash_image() {
    partition=$1
    image=$2
    image_path="${SCRIPT_DIR}/${image}"

    [ -s "${image_path}" ] || die "required image is missing or empty: ${image}"
    printf '%s\n' "Flashing ${partition}..."
    "${FASTBOOT}" flash "${partition}" "${image_path}" ||
        die "fastboot failed while flashing ${partition}"
}

printf '%s\n' 'Assuming the device is already in fastbootd.'
printf '%s\n' 'Do not disconnect the device while images are being flashed.'
confirm 'Continue flashing boot, vendor_boot, vendor_dlkm, and system_dlkm?' ||
    die 'flashing cancelled'
flash_image boot boot.img
flash_image vendor_boot vendor_boot.img
flash_image vendor_dlkm vendor_dlkm.img
flash_image system_dlkm system_dlkm.img

if confirm 'Reboot Android now?'; then
    printf '%s\n' 'All images flashed successfully; rebooting Android...'
    "${FASTBOOT}" reboot || die "images were flashed, but the final reboot command failed"
else
    printf '%s\n' 'Images flashed successfully; device remains in fastbootd.'
fi
