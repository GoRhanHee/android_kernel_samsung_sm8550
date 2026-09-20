#!/usr/bin/env bash

set -Eeuo pipefail

: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${GKI_OUT_DIR:?GKI_OUT_DIR is required}"
: "${GKI_DIST_DIR:?GKI_DIST_DIR is required}"

echo "[common] Building GKI kernel"
(
    cd "${KERNEL_PLATFORM}"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export BUILD_CONFIG_FRAGMENTS=""
    export OUT_DIR="${GKI_OUT_DIR}"
    export DIST_DIR="${GKI_DIST_DIR}"
    export GKI_BUILD_CONFIG=""
    export GKI_PREBUILTS_DIR=""
    export KBUILD_EXT_MODULES=""
    export KBUILD_EXTRA_SYMBOLS=""
    export MODNAME=""
    export BUILD_BOOT_IMG=""
    export BUILD_VENDOR_BOOT_IMG=""
    export SKIP_VENDOR_BOOT="1"
    ./build/build.sh
)

[[ -s "${GKI_DIST_DIR}/Image" ]] || {
    echo "error: common kernel Image was not produced: ${GKI_DIST_DIR}/Image" >&2
    exit 1
}
echo "[common] Artifacts: ${GKI_DIST_DIR}"
