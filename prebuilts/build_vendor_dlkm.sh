#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="${SCRIPT_DIR:?SCRIPT_DIR is required}"
LKM_TOOLS_DIR="${REPO_ROOT}/prebuilts/LKM_Tools"
AIT_DIR="${REPO_ROOT}/prebuilts/vendor_dlkm_unpack"
KBUILD_PATH="${DIST_DIR:-${OUT_DIR:?OUT_DIR is required}/dist}"
PKG_VENDOR_DLKM="${LKM_TOOLS_DIR}/03.prepare_vendor_dlkm.sh"
VENDOR_DLKM_MODULES_LIST="${LKM_TOOLS_DIR}/vendor_dlkm/modules_list.txt"
VENDOR_BOOT_MODULES_LIST="${LKM_TOOLS_DIR}/vendor_boot/modules_list.txt"
VENDOR_DLKM_MODULES_LOAD_FILE="${LKM_TOOLS_DIR}/vendor_dlkm/modules.load"
OUTPUT_DIR="${AIT_DIR}/EXTRACTED_IMAGES/extracted_vendor_dlkm"
MODULES_OUTPUT_DIR="${OUTPUT_DIR}/lib/modules"
SYSTEM_MAP="${KBUILD_PATH}/System.map"
STRIP_TOOL="${REPO_ROOT}/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e/bin/llvm-strip"
OBJCOPY_TOOL="${REPO_ROOT}/kernel_platform/prebuilts/clang/host/linux-x86/clang-r450784e/bin/llvm-objcopy"
REPACK_CONFIG="${AIT_DIR}/CONFIGS/vendor_dlkm_repack.conf"
REPACKED_IMAGE="${AIT_DIR}/REPACKED_IMAGES/vendor_dlkm_repacked.img"
ROOTLESS_EXTRACT_MARKER="${AIT_DIR}/.rootless-erofs-extract"
REPACK_METADATA="${OUTPUT_DIR}/.repack_info/metadata.txt"
VENDOR_DLKM_FILE_CONTEXTS="${REPO_ROOT}/prebuilts/vendor_dlkm_file_contexts"
STOCK_IMAGE="${AIT_DIR}/INPUT_IMAGES/vendor_dlkm.img"
VENDOR_DLKM_CAPACITY_HELPER="${REPO_ROOT}/prebuilts/vendor_dlkm_capacity.sh"

[[ -f "${VENDOR_DLKM_CAPACITY_HELPER}" ]] || {
    echo "vendor_dlkm capacity helper not found: ${VENDOR_DLKM_CAPACITY_HELPER}" >&2
    exit 1
}
# shellcheck source=/dev/null
source "${VENDOR_DLKM_CAPACITY_HELPER}"

run_privileged() {
    if (( EUID == 0 )); then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        env AIT_ALLOW_ROOTLESS_FUSE=1 "$@"
    fi
}

[[ -x "${PKG_VENDOR_DLKM}" ]] || chmod +x "${PKG_VENDOR_DLKM}"
[[ -x "${OBJCOPY_TOOL}" ]] || { echo "llvm-objcopy not found: ${OBJCOPY_TOOL}" >&2; exit 1; }
[[ -f "${VENDOR_DLKM_MODULES_LIST}" ]] || { echo "vendor_dlkm modules list not found: ${VENDOR_DLKM_MODULES_LIST}" >&2; exit 1; }
[[ -f "${VENDOR_DLKM_MODULES_LOAD_FILE}" ]] || { echo "vendor_dlkm modules.load not found: ${VENDOR_DLKM_MODULES_LOAD_FILE}" >&2; exit 1; }

STOCK_MODULES_DIR="$(mktemp -d)"
trap 'rm -rf "${STOCK_MODULES_DIR}"' EXIT
cp -a "${MODULES_OUTPUT_DIR}/." "${STOCK_MODULES_DIR}/"

"${PKG_VENDOR_DLKM}" \
    "${VENDOR_DLKM_MODULES_LIST}" \
    "${KBUILD_PATH}" \
    "${VENDOR_DLKM_MODULES_LOAD_FILE}" \
    "${SYSTEM_MAP}" \
    "${STRIP_TOOL}" \
    "${MODULES_OUTPUT_DIR}" \
    "${VENDOR_BOOT_MODULES_LIST}" \
    "" \
    ""

while IFS= read -r module; do
    "${OBJCOPY_TOOL}" \
        --remove-section=.BTF \
        --remove-section=.BTF.ext \
        "${module}"
done < <(find "${MODULES_OUTPUT_DIR}" -maxdepth 1 -type f -name "*.ko" -print)

UNRESOLVED=0
if [[ -s "${MODULES_OUTPUT_DIR}/missing_modules.txt" ]]; then
    while IFS= read -r module; do
        [[ -n "${module}" ]] || continue
        if [[ -f "${STOCK_MODULES_DIR}/${module}" ]]; then
            cp "${STOCK_MODULES_DIR}/${module}" "${MODULES_OUTPUT_DIR}/${module}"
        else
            UNRESOLVED=1
        fi
    done < "${MODULES_OUTPUT_DIR}/missing_modules.txt"
fi
if (( UNRESOLVED == 0 )); then
    rm -f "${MODULES_OUTPUT_DIR}/missing_modules.txt"
else
    echo "vendor_dlkm modules remain unresolved" >&2
    exit 1
fi
while IFS= read -r stock_file; do
    target="${MODULES_OUTPUT_DIR}/$(basename "${stock_file}")"
    [[ -e "${target}" ]] || cp "${stock_file}" "${target}"
done < <(find "${STOCK_MODULES_DIR}" -maxdepth 1 -type f ! -name '*.ko')

while IFS= read -r generated_file; do
    [[ -e "${STOCK_MODULES_DIR}/$(basename "${generated_file}")" ]] ||
        rm -f "${generated_file}"
done < <(find "${MODULES_OUTPUT_DIR}" -maxdepth 1 -type f ! -name '*.ko')

cp "${VENDOR_DLKM_MODULES_LOAD_FILE}" "${MODULES_OUTPUT_DIR}/modules.load"
while IFS= read -r module_path; do
    module="$(basename "${module_path}")"
    if awk -F: -v module="${module}" '
        {
            name = $1
            sub(/^.*\//, "", name)
            if (name == module)
                found = 1
        }
        END { exit found ? 0 : 1 }
    ' "${MODULES_OUTPUT_DIR}/modules.dep"; then
        continue
    fi

    stock_dep="$(awk -F: -v module="${module}" '
        {
            name = $1
            sub(/^.*\//, "", name)
            if (name == module) {
                print
                exit
            }
        }
    ' "${STOCK_MODULES_DIR}/modules.dep")"
    [[ -n "${stock_dep}" ]] || {
        echo "stock dependency metadata not found for ${module}" >&2
        exit 1
    }
    printf '%s\n' "${stock_dep//\/vendor\/lib\/modules\//}" \
        >> "${MODULES_OUTPUT_DIR}/modules.dep"
done < <(find "${MODULES_OUTPUT_DIR}" -maxdepth 1 -type f -name '*.ko' -print)

[[ -f "${STOCK_IMAGE}" ]] || {
    echo "stock vendor_dlkm image not found: ${STOCK_IMAGE}" >&2
    exit 1
}

cat > "${REPACK_CONFIG}" <<EOF
ACTION=repack
SOURCE_DIR=${OUTPUT_DIR}
OUTPUT_IMAGE=${REPACKED_IMAGE}
FILESYSTEM=erofs
CREATE_SPARSE_IMAGE=false
COMPRESSION_MODE=lz4hc
COMPRESSION_LEVEL=12
EOF

command -v fsck.erofs >/dev/null 2>&1 || {
    echo "fsck.erofs not found" >&2
    exit 1
}
command -v dump.erofs >/dev/null 2>&1 || {
    echo "dump.erofs not found" >&2
    exit 1
}
[[ -f "${VENDOR_DLKM_FILE_CONTEXTS}" ]] || {
    echo "vendor_dlkm file contexts not found: ${VENDOR_DLKM_FILE_CONTEXTS}" >&2
    exit 1
}
STOCK_UUID="$(
    dump.erofs -s "${STOCK_IMAGE}" |
        awk '/Filesystem UUID:/ { print $NF; exit }'
)"
[[ -n "${STOCK_UUID}" ]] || {
    echo "stock vendor_dlkm UUID could not be read" >&2
    exit 1
}

if [[ -f "${ROOTLESS_EXTRACT_MARKER}" ]]; then
    command -v mkfs.erofs >/dev/null 2>&1 || {
        echo "mkfs.erofs not found" >&2
        exit 1
    }
    STOCK_TIMESTAMP="$(stat -c %Y "${OUTPUT_DIR}/etc/build.prop")"
    mkdir -p "$(dirname "${REPACKED_IMAGE}")"
    rm -f "${REPACKED_IMAGE}"
    mkfs.erofs \
        -zlz4hc,level=12 \
        -E^xattr-name-filter \
        -T"${STOCK_TIMESTAMP}" \
        --all-time \
        --all-root \
        -U"${STOCK_UUID}" \
        --file-contexts="${VENDOR_DLKM_FILE_CONTEXTS}" \
        "${REPACKED_IMAGE}" \
        "${OUTPUT_DIR}"
else
    vendor_dlkm_metadata_set_uuid "${REPACK_METADATA}" "${STOCK_UUID}"
    (
        cd "${AIT_DIR}"
        run_privileged ./android_image_tools.sh \
            --conf="${REPACK_CONFIG}" --quiet
    )
fi

[[ -s "${REPACKED_IMAGE}" ]] || {
    echo "rebuilt vendor_dlkm image is missing or empty: ${REPACKED_IMAGE}" >&2
    exit 1
}
vendor_dlkm_capacity_pad_to_stock "${STOCK_IMAGE}" "${REPACKED_IMAGE}"
SELINUX_XATTR_DIR="$(mktemp -d)"
trap 'rm -rf "${STOCK_MODULES_DIR}" "${SELINUX_XATTR_DIR}"' EXIT
fsck.erofs -p --xattrs --extract="${SELINUX_XATTR_DIR}" "${REPACKED_IMAGE}"
REPACKED_UUID="$(
    dump.erofs -s "${REPACKED_IMAGE}" |
        awk '/Filesystem UUID:/ { print $NF; exit }'
    )"
[[ -n "${REPACKED_UUID}" ]] || {
    echo "rebuilt vendor_dlkm UUID could not be read" >&2
    exit 1
}
[[ "${REPACKED_UUID}" == "${STOCK_UUID}" ]] || {
    echo "rebuilt vendor_dlkm UUID differs from stock: ${REPACKED_UUID} != ${STOCK_UUID}" >&2
    exit 1
}
vendor_dlkm_selinux_xattrs_validate "${SELINUX_XATTR_DIR}"
vendor_dlkm_capacity_validate "${STOCK_IMAGE}" "${REPACKED_IMAGE}"

cp "${REPACKED_IMAGE}" "${REPO_ROOT}/vendor_dlkm.img"
