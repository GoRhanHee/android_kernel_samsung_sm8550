#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${PACKAGE_DIR:?PACKAGE_DIR is required}"
: "${WLAN_PROFILES:?WLAN_PROFILES is required}"

if [[ -s "${PACKAGING_WORK_DIR}/erofs-bin" ]]; then
    export PATH="$(<"${PACKAGING_WORK_DIR}/erofs-bin"):${PATH}"
fi
export REPO_ROOT="${SOURCE_DIR}"

for wlan_profile in ${WLAN_PROFILES}; do
    echo "[vendor_dlkm] Building ${wlan_profile} image"
    export WLAN_PROFILE="${wlan_profile}"
    export OUTPUT_IMAGE="${PACKAGE_DIR}/vendor_dlkm_${wlan_profile}.img"
    "${SOURCE_DIR}/scripts/lib/build_dlkm_image.sh" vendor_dlkm
done

echo "[system_dlkm] Building image"
export WLAN_PROFILE=""
export OUTPUT_IMAGE="${PACKAGE_DIR}/system_dlkm.img"
"${SOURCE_DIR}/scripts/lib/build_dlkm_image.sh" system_dlkm
