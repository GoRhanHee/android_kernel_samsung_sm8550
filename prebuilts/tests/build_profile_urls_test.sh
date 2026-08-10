#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/build.sh"

die() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_profile_urls() {
    local device="$1"
    local release="$2"
    local model="$3"

    grep -Fq "STOCK_VENDOR_BOOT_URL=\"https://github.com/GoRhanHee/Firmware_Samsung/releases/download/${release}/vendor_boot.img\"" "${BUILD_SCRIPT}" ||
        die "${device}: current vendor_boot profile URL is stale or missing"
    grep -Fq "STOCK_VENDOR_DLKM_URL=\"https://github.com/GoRhanHee/Firmware_Samsung/releases/download/${release}/vendor_dlkm.img\"" "${BUILD_SCRIPT}" ||
        die "${device}: current vendor_dlkm profile URL is stale or missing"
    grep -Fq "STOCK_SYSTEM_DLKM_URL=\"https://github.com/GoRhanHee/Firmware_Samsung/releases/download/${release}/system_dlkm.img\"" "${BUILD_SCRIPT}" ||
        die "${device}: system_dlkm profile URL is missing"
    grep -Fq "MODEL=\"${model}\"" "${BUILD_SCRIPT}" ||
        die "${device}: model profile assertion is missing"
}

assert_profile_urls dm1q S911NKSS8FZG1_KOO_OKR dm1q
assert_profile_urls dm2q S916NKSS8FZG1_KOO_OKR dm2q
assert_profile_urls dm3q S918NKSS8FZG1_KOO_OKR dm3q
assert_profile_urls q5q F946NKSS6GZG3_KOO_OKR q5q
assert_profile_urls b5q F731NKSS6GZG4_KOO_OKR b5q

printf '%s\n' 'PASS: current build.sh vendor and system_dlkm profile URLs'
