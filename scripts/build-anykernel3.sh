#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${PACKAGE_DIR:?PACKAGE_DIR is required}"
: "${ANYKERNEL_PACKAGE:?ANYKERNEL_PACKAGE is required}"

mkdir -p "${PACKAGE_DIR}"
[[ -s "${DIST_DIR}/Image" ]] || {
    echo "error: kernel Image is missing: ${DIST_DIR}/Image" >&2
    exit 1
}
cp -- "${DIST_DIR}/Image" "${PACKAGE_DIR}/Image"

echo "[AnyKernel3] Creating ${ANYKERNEL_PACKAGE}"
"${SOURCE_DIR}/scripts/lib/make_anykernel_package.sh" \
    "${ANYKERNEL_PACKAGE}" "${PACKAGE_DIR}"
