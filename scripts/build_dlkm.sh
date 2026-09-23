#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${PACKAGE_DIR:?PACKAGE_DIR is required}"

if [[ -s "${PACKAGING_WORK_DIR}/erofs-bin" ]]; then
    export PATH="$(<"${PACKAGING_WORK_DIR}/erofs-bin"):${PATH}"
fi
export REPO_ROOT="${SOURCE_DIR}"

echo "[vendor_dlkm] Building universal image"
export OUTPUT_IMAGE="${PACKAGE_DIR}/vendor_dlkm.img"
"${SOURCE_DIR}/scripts/lib/build_dlkm_image.sh" vendor_dlkm

echo "[system_dlkm] Building image"
export OUTPUT_IMAGE="${PACKAGE_DIR}/system_dlkm.img"
"${SOURCE_DIR}/scripts/lib/build_dlkm_image.sh" system_dlkm
