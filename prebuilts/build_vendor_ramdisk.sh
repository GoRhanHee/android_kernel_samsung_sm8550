#!/usr/bin/env bash

set -Eeuo pipefail

readonly BUILD_VENDOR_RAMDISK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly -a EARLY_ADSP_MODULES=(
    qcom_q6v5_pas.ko
    adsp_loader_dlkm.ko
    frpc-adsprpc.ko
)

die() {
    echo "error: $*" >&2
    exit 1
}

resolve_module() {
    local dist_dir="$1"
    local module_name="$2"
    local -a matches=()

    mapfile -d '' matches < <(
        find "${dist_dir}" -maxdepth 1 -type f -name "${module_name}" -print0
    )
    (( ${#matches[@]} == 1 )) ||
        die "expected one built ${module_name} beneath ${dist_dir}; found ${#matches[@]}"
    printf '%s\n' "${matches[0]}"
}

normalize_module_lists() {
    awk '
        {
            sub(/^.*\//, "", $0)
        }
        !/\.ko$/ || $0 == "hdm.ko" { next }
        $0 == "qca6490.ko" { $0 = "qca_cld3_qca6490.ko" }
        $0 == "kiwi_v2.ko" { $0 = "qca_cld3_kiwi_v2.ko" }
        !seen[$0]++ { print }
    ' "$@"
}

main() {
    local repo_root="${REPO_ROOT:?REPO_ROOT is required}"
    local dist_dir="${DIST_DIR:?DIST_DIR is required}"
    local output_dir="${OUTPUT_DIR:?OUTPUT_DIR is required}"
    local clang_bin="${repo_root}/kernel_platform/prebuilts/clang/host/linux-x86/clang-${TOOLCHAIN_VERSION:-r614150}/bin"
    local strip_tool="${clang_bin}/llvm-strip"
    local objcopy_tool="${clang_bin}/llvm-objcopy"
    local system_map="${dist_dir}/System.map"
    local early_list="${dist_dir}/modules.load"
    local vendor_list="${dist_dir}/vendor_dlkm.modules.load"
    local system_list="${dist_dir}/system_dlkm.modules.load"
    local work_dir
    local root_dir
    local versioned_modules_dir
    local normal_list
    local recovery_list
    local raw_inventory
    local release
    local module_name
    local source_module

    command -v depmod >/dev/null 2>&1 || die "required command not found: depmod"
    [[ -s "${system_map}" ]] || die "System.map not found: ${system_map}"
    for source_module in "${early_list}" "${vendor_list}" "${system_list}"; do
        [[ -s "${source_module}" ]] || die "module list not found: ${source_module}"
    done
    [[ -x "${strip_tool}" ]] || die "llvm-strip not found: ${strip_tool}"
    [[ -x "${objcopy_tool}" ]] || die "llvm-objcopy not found: ${objcopy_tool}"

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-vendor-ramdisk.XXXXXX")"
    trap "rm -rf -- $(printf '%q' "${work_dir}")" EXIT
    root_dir="${work_dir}/root"
    normal_list="${work_dir}/modules.load"
    recovery_list="${work_dir}/modules.load.recovery"
    raw_inventory="${work_dir}/modules.inventory.raw"
    normalize_module_lists "${early_list}" >"${normal_list}"
    # The Samsung sensor HAL starts before the vendor_dlkm load path has
    # consistently brought up the ADSP/FastRPC stack.  If that race is lost,
    # sensors-hal times out waiting for the sensors QMI service and keeps an
    # empty sensor list for the remainder of the boot.  Keep the remoteproc,
    # ADSP loader and FastRPC entry points in the vendor ramdisk load list;
    # depmod supplies their dependency order from the complete module set
    # staged below.
    for module_name in "${EARLY_ADSP_MODULES[@]}"; do
        resolve_module "${dist_dir}" "${module_name}" >/dev/null
        grep -Fqx "${module_name}" "${normal_list}" ||
            printf '%s\n' "${module_name}" >>"${normal_list}"
    done
    find "${dist_dir}" -maxdepth 1 -type f -name '*.ko' -printf '%f\n' \
        | sort -u >"${raw_inventory}"
    normalize_module_lists "${raw_inventory}" >"${recovery_list}"

    release="$("${BUILD_VENDOR_RAMDISK_DIR}/kernel_release.sh" "${dist_dir}/kernel.release")"
    versioned_modules_dir="${root_dir}/lib/modules/${release}"
    mkdir -p "${versioned_modules_dir}"

    while IFS= read -r module_name; do
        source_module="$(resolve_module "${dist_dir}" "${module_name}")"
        cp -- "${source_module}" "${versioned_modules_dir}/${module_name}"
    done <"${recovery_list}"

    while IFS= read -r -d '' source_module; do
        "${BUILD_VENDOR_RAMDISK_DIR}/prepare_module.sh" "${source_module}" "${clang_bin}"
    done < <(find "${versioned_modules_dir}" -type f -name '*.ko' -print0)

    depmod -b "${root_dir}" -F "${system_map}" "${release}"
    cp -- "${normal_list}" "${versioned_modules_dir}/modules.load"
    cp -- "${recovery_list}" "${versioned_modules_dir}/modules.load.recovery"
    awk 'NF && !seen[$0]++ { print }' \
        "${dist_dir}/modules.blocklist" \
        "${dist_dir}/system_dlkm.modules.blocklist" \
        >"${versioned_modules_dir}/modules.blocklist" 2>/dev/null || true
    [[ -s "${versioned_modules_dir}/modules.blocklist" ]] ||
        rm -f -- "${versioned_modules_dir}/modules.blocklist"

    rm -rf -- "${output_dir}"
    mkdir -p "${output_dir}/ramdisk/lib/modules"
    cp -a "${versioned_modules_dir}/." "${output_dir}/ramdisk/lib/modules/"
    echo "[packaging] Staged universal vendor ramdisk modules in ${output_dir}"
}

main "$@"
