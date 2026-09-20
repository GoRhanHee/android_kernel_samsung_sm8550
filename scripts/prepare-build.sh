#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${OUT_DIR:?OUT_DIR is required}"
: "${PACKAGING_WORK_DIR:?PACKAGING_WORK_DIR is required}"
: "${DOWNLOAD_DIR:?DOWNLOAD_DIR is required}"
: "${TMPDIR:?TMPDIR is required}"

die() {
    echo "error: $*" >&2
    exit 1
}

for command_name in depmod git zip; do
    command -v "${command_name}" >/dev/null 2>&1 ||
        die "required command not found: ${command_name}"
done

[[ "${PACKAGING_WORK_DIR}" == "${OUT_DIR}/"* ]] ||
    die "PACKAGING_WORK_DIR must be scoped beneath OUT_DIR"
[[ "${TMPDIR}" == "${PACKAGING_WORK_DIR}/"* ]] ||
    die "TMPDIR must be scoped beneath PACKAGING_WORK_DIR"

for path in "${PACKAGING_WORK_DIR}" "${DOWNLOAD_DIR}"; do
    [[ ! -e "${path}" ]] || die "build workspace already exists: ${path}"
done
mkdir -p "${ANDROID_PRODUCT_OUT}" "${ANDROID_KERNEL_OUT}" "${DOWNLOAD_DIR}" "${TMPDIR}"

erofs_install_dir="${SOURCE_DIR}/.cache/erofs-utils"
erofs_check="${SOURCE_DIR}/scripts/lib/erofs_image.sh"
if "${erofs_check}" --check >/dev/null 2>&1; then
    echo "[packaging] Existing EROFS tools passed image checks"
elif PATH="${erofs_install_dir}/bin:${PATH}" "${erofs_check}" --check >/dev/null 2>&1; then
    export PATH="${erofs_install_dir}/bin:${PATH}"
    echo "[packaging] Using cached EROFS tools: ${erofs_install_dir}/bin"
else
    echo "[packaging] Installing pinned EROFS tools"
    "${SOURCE_DIR}/scripts/lib/install_erofs_utils.sh" "${erofs_install_dir}"
    export PATH="${erofs_install_dir}/bin:${PATH}"
    "${erofs_check}" --check
fi

# A child cannot update its parent's PATH, so persist the selected tool path for
# the later packaging phases and let each phase prepend it when present.
if [[ -x "${erofs_install_dir}/bin/mkfs.erofs" ]]; then
    printf '%s\n' "${erofs_install_dir}/bin" >"${PACKAGING_WORK_DIR}/erofs-bin"
fi

echo "[paths] OUT_DIR=${OUT_DIR}"
echo "[paths] TMPDIR=${TMPDIR}"
