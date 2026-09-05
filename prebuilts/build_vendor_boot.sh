#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="${SCRIPT_DIR:?SCRIPT_DIR is required}"
LKM_TOOLS_DIR="${REPO_ROOT}/prebuilts/LKM_Tools"
BOOT_EDITOR_DIR="${REPO_ROOT}/prebuilts/vendor_boot_unpack"
KBUILD_PATH="${DIST_DIR:-${OUT_DIR:?OUT_DIR is required}/dist}"
PKG_VENDOR_BOOT="${LKM_TOOLS_DIR}/02.prepare_vendor_boot_modules.sh"
MODULES_LIST="${LKM_TOOLS_DIR}/vendor_boot/modules_list.txt"
OEM_LOAD_FILE="${LKM_TOOLS_DIR}/vendor_boot/modules.load"
OUTPUT_DIR="${BOOT_EDITOR_DIR}/build/unzip_boot/root.1/lib/modules"
SYSTEM_MAP="${KBUILD_PATH}/System.map"
CLANG_TOOLCHAIN_DIR="${REPO_ROOT}/kernel_platform/prebuilts/clang/host/linux-x86/clang-${TOOLCHAIN_VERSION:-r614150}"
STRIP_TOOL="${CLANG_TOOLCHAIN_DIR}/bin/llvm-strip"
FSTAB_FILE="${BOOT_EDITOR_DIR}/build/unzip_boot/root.1/first_stage_ramdisk/fstab.qcom"
FSTAB_PATCHER="${REPO_ROOT}/prebuilts/patch_vendor_dlkm_fstab.sh"

NUKE_MODULE="hdm.ko"

remove_nuked_module() {
    local modules_dir="$1"
    local metadata
    local escaped_module="${NUKE_MODULE//./\\.}"

    rm -f -- "${modules_dir}/${NUKE_MODULE}"
    for metadata in modules.load modules.load.recovery modules.dep modules.softdep modules_list.txt; do
        [[ -f "${modules_dir}/${metadata}" ]] || continue
        sed -i \
            -e "/^${escaped_module}$/d" \
            -e "/^${escaped_module}:/d" \
            "${modules_dir}/${metadata}"
    done
}

[[ -x "${PKG_VENDOR_BOOT}" ]] || chmod +x "${PKG_VENDOR_BOOT}"
[[ -f "${MODULES_LIST}" ]] || { echo "vendor_boot modules list not found: ${MODULES_LIST}" >&2; exit 1; }
[[ -f "${OEM_LOAD_FILE}" ]] || { echo "vendor_boot modules.load not found: ${OEM_LOAD_FILE}" >&2; exit 1; }
[[ -x "${FSTAB_PATCHER}" ]] || { echo "fstab patcher not found: ${FSTAB_PATCHER}" >&2; exit 1; }

STOCK_MODULES_DIR="$(mktemp -d)"
trap 'rm -rf "${STOCK_MODULES_DIR}"' EXIT
cp -a "${OUTPUT_DIR}/." "${STOCK_MODULES_DIR}/"
remove_nuked_module "${STOCK_MODULES_DIR}"
remove_nuked_module "${LKM_TOOLS_DIR}/vendor_boot"

"${PKG_VENDOR_BOOT}" \
    "${MODULES_LIST}" \
    "${KBUILD_PATH}" \
    "${OEM_LOAD_FILE}" \
    "${SYSTEM_MAP}" \
    "${STRIP_TOOL}" \
    "${OUTPUT_DIR}"

UNRESOLVED=0
if [[ -s "${OUTPUT_DIR}/missing_modules.txt" ]]; then
    while IFS= read -r module; do
        [[ -n "${module}" ]] || continue
        if [[ -f "${STOCK_MODULES_DIR}/${module}" ]]; then
            cp "${STOCK_MODULES_DIR}/${module}" "${OUTPUT_DIR}/${module}"
        else
            UNRESOLVED=1
        fi
    done < "${OUTPUT_DIR}/missing_modules.txt"
fi
if (( UNRESOLVED == 0 )); then
    rm -f "${OUTPUT_DIR}/missing_modules.txt"
fi
while IFS= read -r stock_file; do
    target="${OUTPUT_DIR}/$(basename "${stock_file}")"
    [[ -e "${target}" ]] || cp "${stock_file}" "${target}"
done < <(find "${STOCK_MODULES_DIR}" -maxdepth 1 -type f ! -name '*.ko')

remove_nuked_module "${OUTPUT_DIR}"

[[ -f "${FSTAB_FILE}" ]] || { echo "fstab not found: ${FSTAB_FILE}" >&2; exit 1; }
"${FSTAB_PATCHER}" "${FSTAB_FILE}"

(
    cd "${BOOT_EDITOR_DIR}"
    LC_ALL=C.UTF-8 ./gradlew -Dfile.encoding=UTF-8 pack
    cp vendor_boot.img "${REPO_ROOT}/vendor_boot.img"
)
