#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${PACKAGE_DIR:?PACKAGE_DIR is required}"

echo "[vendor_boot] Staging vendor ramdisk modules"
export REPO_ROOT="${SOURCE_DIR}"
export OUTPUT_DIR="${PACKAGE_DIR}/vendor_ramdisk"
"${SOURCE_DIR}/scripts/lib/stage_vendor_ramdisk.sh"
