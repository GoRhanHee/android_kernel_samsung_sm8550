#!/usr/bin/env bash

set -Eeuo pipefail

: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${GKI_OUT_DIR:?GKI_OUT_DIR is required}"
: "${GKI_DIST_DIR:?GKI_DIST_DIR is required}"

COMMON_OUT_DIR="$(readlink -m -- "${GKI_OUT_DIR}")"
COMMON_DIST_DIR="$(readlink -m -- "${GKI_DIST_DIR}")"
[[ "${COMMON_DIST_DIR}" == "${COMMON_OUT_DIR}/"* ]] || {
    echo "error: GKI_DIST_DIR must be beneath GKI_OUT_DIR" >&2
    exit 1
}

echo "[common] Building GKI kernel"
(
    cd "${KERNEL_PLATFORM}"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export BUILD_CONFIG_FRAGMENTS=""
    export OUT_DIR="${COMMON_OUT_DIR}"
    export DIST_DIR="${COMMON_DIST_DIR}"
    # These variables enable mixed-build artifact copying in build/build.sh.
    # A standalone common build already writes directly to DIST_DIR, so letting
    # them leak into this process makes the build copy dist onto itself.
    unset GKI_OUT_DIR GKI_DIST_DIR GKI_PREBUILTS_DIR
    export GKI_BUILD_CONFIG=""
    export KBUILD_EXT_MODULES=""
    export KBUILD_EXTRA_SYMBOLS=""
    export MODNAME=""
    export BUILD_BOOT_IMG=""
    export BUILD_VENDOR_BOOT_IMG=""
    export SKIP_VENDOR_BOOT="1"
    ./build/build.sh
)

[[ -s "${COMMON_DIST_DIR}/Image" ]] || {
    echo "error: common kernel Image was not produced: ${COMMON_DIST_DIR}/Image" >&2
    exit 1
}
echo "[common] Artifacts: ${COMMON_DIST_DIR}"
