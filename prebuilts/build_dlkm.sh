#!/usr/bin/env bash

set -Eeuo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

normalize_module_list() {
    local input_file="$1"
    local wlan_profile="${2:-}"

    awk -v wlan_profile="${wlan_profile}" '
        {
            sub(/^.*\//, "", $0)
        }
        !/\.ko$/ || $0 == "hdm.ko" { next }
        $0 == "qca6490.ko" || $0 == "kiwi_v2.ko" ||
            $0 == "qca_cld3_qca6490.ko" || $0 == "qca_cld3_kiwi_v2.ko" {
            if (wlan_profile != "" && !wlan_added++)
                print "qca_cld3_" wlan_profile ".ko"
            next
        }
        !seen[$0]++ { print }
    ' "${input_file}"
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

kernel_release_from_module() {
    local module="$1"
    local release

    release="$(modinfo -F vermagic -- "${module}" | awk 'NR == 1 { print $1 }')"
    [[ -n "${release}" && "${release}" != */* ]] ||
        die "could not determine kernel release from ${module}"
    printf '%s\n' "${release}"
}

main() {
    (( $# == 1 )) || die "usage: build_dlkm.sh <vendor_dlkm|system_dlkm>"

    local partition="$1"
    local repo_root="${REPO_ROOT:?REPO_ROOT is required}"
    local dist_dir="${DIST_DIR:?DIST_DIR is required}"
    local output_image="${OUTPUT_IMAGE:?OUTPUT_IMAGE is required}"
    local wlan_profile="${WLAN_PROFILE:-}"
    local list_file="${dist_dir}/${partition}.modules.load"
    local file_contexts="${repo_root}/prebuilts/${partition}_file_contexts"
    local clang_bin="${repo_root}/kernel_platform/prebuilts/clang/host/linux-x86/clang-${TOOLCHAIN_VERSION:-r614150}/bin"
    local strip_tool="${clang_bin}/llvm-strip"
    local objcopy_tool="${clang_bin}/llvm-objcopy"
    local system_map="${dist_dir}/System.map"
    local work_dir
    local root_dir
    local versioned_modules_dir
    local final_modules_dir
    local normalized_list
    local inventory_list
    local raw_inventory
    local excluded_modules
    local reference_module
    local release
    local module_name
    local source_module
    local metadata
    local epoch="${SOURCE_DATE_EPOCH:-$(date +%s)}"
    local uuid

    case "${partition}" in
        vendor_dlkm)
            [[ "${wlan_profile}" == qca6490 || "${wlan_profile}" == kiwi_v2 ]] ||
                die "vendor_dlkm requires WLAN_PROFILE=qca6490 or WLAN_PROFILE=kiwi_v2"
            uuid="6b128d5a-0f66-4bb6-b5d1-90c9ad38c54a"
            ;;
        system_dlkm)
            [[ -z "${wlan_profile}" ]] || die "system_dlkm does not accept WLAN_PROFILE"
            uuid="f2ec91c9-d5a7-47bf-a6eb-c19f24ee6fcb"
            ;;
        *)
            die "unsupported DLKM partition: ${partition}"
            ;;
    esac

    require_command depmod
    require_command fsck.erofs
    require_command mkfs.erofs
    require_command modinfo
    [[ -d "${dist_dir}" ]] || die "kernel dist directory not found: ${dist_dir}"
    [[ -s "${list_file}" ]] || die "module load list not found: ${list_file}"
    [[ -s "${system_map}" ]] || die "System.map not found: ${system_map}"
    [[ -f "${file_contexts}" ]] || die "file contexts not found: ${file_contexts}"
    [[ -x "${strip_tool}" ]] || die "llvm-strip not found: ${strip_tool}"
    [[ -x "${objcopy_tool}" ]] || die "llvm-objcopy not found: ${objcopy_tool}"

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-${partition}.XXXXXX")"
    trap "rm -rf -- $(printf '%q' "${work_dir}")" EXIT
    root_dir="${work_dir}/root"
    normalized_list="${work_dir}/modules.load"
    inventory_list="${work_dir}/modules.inventory"
    raw_inventory="${work_dir}/modules.inventory.raw"
    excluded_modules="${work_dir}/modules.exclude"
    mkdir -p "${root_dir}/etc" "${root_dir}/lib/modules"
    normalize_module_list "${list_file}" "${wlan_profile}" >"${normalized_list}"
    [[ -s "${normalized_list}" ]] || die "normalized ${partition} module list is empty"

    if [[ "${partition}" == vendor_dlkm ]]; then
        find "${dist_dir}" -maxdepth 1 -type f -name '*.ko' -printf '%f\n' \
            | sort -u >"${raw_inventory}"
        normalize_module_list "${raw_inventory}" "${wlan_profile}" >"${inventory_list}.all"
        normalize_module_list "${dist_dir}/modules.load" >"${excluded_modules}"
        normalize_module_list "${dist_dir}/system_dlkm.modules.load" \
            >>"${excluded_modules}"
        awk 'NR == FNR { excluded[$0] = 1; next } !excluded[$0]' \
            "${excluded_modules}" "${inventory_list}.all" >"${inventory_list}"
    else
        cp -- "${normalized_list}" "${inventory_list}"
    fi
    [[ -s "${inventory_list}" ]] || die "${partition} module inventory is empty"

    reference_module="$(resolve_module "${dist_dir}" "$(head -n 1 "${inventory_list}")")"
    release="$(kernel_release_from_module "${reference_module}")"
    versioned_modules_dir="${root_dir}/lib/modules/${release}"
    mkdir -p "${versioned_modules_dir}"

    while IFS= read -r module_name; do
        source_module="$(resolve_module "${dist_dir}" "${module_name}")"
        cp -- "${source_module}" "${versioned_modules_dir}/${module_name}"
    done <"${inventory_list}"

    while IFS= read -r -d '' source_module; do
        "${objcopy_tool}" --remove-section=.BTF --remove-section=.BTF.ext \
            "${source_module}"
        "${strip_tool}" --strip-debug "${source_module}"
    done < <(find "${versioned_modules_dir}" -type f -name '*.ko' -print0)

    depmod -b "${root_dir}" -F "${system_map}" "${release}"
    cp -- "${normalized_list}" "${versioned_modules_dir}/modules.load"

    for metadata in modules.blocklist modules.options; do
        if [[ -s "${dist_dir}/${partition}.${metadata}" ]]; then
            cp -- "${dist_dir}/${partition}.${metadata}" \
                "${versioned_modules_dir}/${metadata}"
        fi
    done

    if [[ "${partition}" == vendor_dlkm ]]; then
        final_modules_dir="${root_dir}/lib/modules"
        cp -a "${versioned_modules_dir}/." "${final_modules_dir}/"
        rm -rf -- "${versioned_modules_dir}"
    fi

    printf '%s\n' \
        "ro.product.${partition}.name=GoRhanHee SM8550 universal" \
        "ro.product.${partition}.device=universal" \
        "ro.product.${partition}.build.date.utc=${epoch}" \
        >"${root_dir}/etc/build.prop"

    mkdir -p "$(dirname "${output_image}")"
    rm -f -- "${output_image}"
    mkfs.erofs \
        -zlz4hc,level=12 \
        -E^xattr-name-filter \
        -T"${epoch}" \
        --all-time \
        --all-root \
        -U"${uuid}" \
        -L "${partition}" \
        --file-contexts="${file_contexts}" \
        "${output_image}" "${root_dir}"
    fsck.erofs -p "${output_image}"

    echo "[packaging] Created ${output_image}"
}

main "$@"
