#!/usr/bin/env bash

set -Eeuo pipefail

readonly BUILD_DLKM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dlkm_capacity.sh
source "${BUILD_DLKM_DIR}/dlkm_capacity.sh"

DLKM_TEMPORARY_DIRS=()

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

run_privileged() {
    if (( EUID == 0 )); then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        env AIT_ALLOW_ROOTLESS_FUSE=1 "$@"
    fi
}

remove_nuked_module() {
    local modules_dir="$1"
    local metadata
    local escaped_module='hdm\.ko'

    rm -f -- "${modules_dir}/hdm.ko"
    for metadata in modules.load modules.load.recovery modules.dep modules.softdep modules_list.txt; do
        [[ -f "${modules_dir}/${metadata}" ]] || continue
        sed -i \
            -e "/^${escaped_module}$/d" \
            -e "/^${escaped_module}:/d" \
            "${modules_dir}/${metadata}"
    done
}

cleanup_dlkm_temporary_dirs() {
    local directory

    for directory in "${DLKM_TEMPORARY_DIRS[@]}"; do
        [[ -n "${directory}" && "${directory}" == /tmp/* ]] || continue
        run_privileged rm -rf -- "${directory}"
    done
}

discover_system_module_root() {
    local modules_parent="$1"
    local -a roots=()

    [[ -d "${modules_parent}" ]] || die "system_dlkm modules directory not found: ${modules_parent}"
    mapfile -d '' roots < <(
        find "${modules_parent}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z
    )
    (( ${#roots[@]} == 1 )) ||
        die "system_dlkm requires exactly one versioned /lib/modules root; found ${#roots[@]}"
    printf '%s\n' "${roots[0]}"
}

module_field() {
    local field="$1"
    local module="$2"

    modinfo -F "${field}" -- "${module}" 2>/dev/null | head -n 1
}

assert_stock_module_compatible() {
    local stock_module="$1"
    local custom_reference="$2"
    local module_name
    local field
    local stock_value
    local custom_value

    module_name="$(basename "${stock_module}")"
    for field in vermagic signer sig_key sig_hashalgo; do
        stock_value="$(module_field "${field}" "${stock_module}")" ||
            die "stock fallback module ${module_name} has unreadable ${field} metadata"
        custom_value="$(module_field "${field}" "${custom_reference}")" ||
            die "custom module policy has unreadable ${field} metadata: ${custom_reference}"
        if [[ "${field}" == vermagic && ( -z "${stock_value}" || -z "${custom_value}" ) ]]; then
            die "incompatible stock fallback module ${module_name}: vermagic metadata is empty"
        fi
        [[ "${stock_value}" == "${custom_value}" ]] ||
            die "incompatible stock fallback module ${module_name}: ${field} '${stock_value}' != custom '${custom_value}'"
    done
}

restore_stock_metadata() {
    local stock_root="$1"
    local output_root="$2"
    local stock_file
    local relative
    local target

    while IFS= read -r -d '' stock_file; do
        relative="${stock_file#${stock_root}/}"
        target="${output_root}/${relative}"
        if [[ ! -e "${target}" && ! -L "${target}" ]]; then
            mkdir -p "$(dirname "${target}")"
            cp -a -- "${stock_file}" "${target}"
        fi
    done < <(
        find "${stock_root}" \( -type f ! -name '*.ko' -o -type l \) -print0
    )

    while IFS= read -r -d '' target; do
        relative="${target#${output_root}/}"
        if [[ ! -e "${stock_root}/${relative}" && ! -L "${stock_root}/${relative}" ]]; then
            rm -f -- "${target}"
        fi
    done < <(find "${output_root}" -type f ! -name '*.ko' -print0)
}

normalize_stock_dependency() {
    local partition="$1"
    local release="$2"
    local dependency_line="$3"
    local runtime_partition="${partition%_dlkm}"
    local module_suffix=""
    local prefix
    local module_path
    local dependencies
    local dependency
    local normalized

    [[ -z "${release}" ]] || module_suffix="/${release}"
    for prefix in \
        "/${runtime_partition}/lib/modules${module_suffix}/" \
        "/${partition}/lib/modules${module_suffix}/" \
        "/lib/modules${module_suffix}/"; do
        dependency_line="${dependency_line//${prefix}/}"
    done
    if [[ "${partition}" == vendor_dlkm ]]; then
        printf '%s\n' "${dependency_line}"
        return
    fi

    module_path="${dependency_line%%:*}"
    dependencies="${dependency_line#*:}"
    normalized="$(basename "${module_path}"):"
    for dependency in ${dependencies}; do
        normalized+=" $(basename "${dependency}")"
    done
    printf '%s\n' "${normalized}"
}

dependency_line_for_module() {
    local modules_dep="$1"
    local module_name="$2"

    awk -F: -v module="${module_name}" '
        {
            name = $1
            sub(/^.*\//, "", name)
            if (name == module) {
                print
                exit
            }
        }
    ' "${modules_dep}"
}

normalize_system_modules_load() {
    local stock_load="$1"
    local output_root="$2"
    local generated_load="${output_root}/modules.load"
    local normalized_load
    local load_file
    local entry
    local module

    normalized_load="$(mktemp "${generated_load}.normalized.XXXXXX")"
    for load_file in "${stock_load}" "${generated_load}"; do
        while IFS= read -r entry; do
            [[ -n "${entry}" ]] || continue
            module="$(basename "${entry}")"
            [[ -f "${output_root}/${module}" ]] || continue
            grep -Fqx -- "${module}" "${normalized_load}" 2>/dev/null ||
                printf '%s\n' "${module}" >>"${normalized_load}"
        done <"${load_file}"
    done
    chmod --reference="${generated_load}" "${normalized_load}"
    mv -- "${normalized_load}" "${generated_load}"
}

main() {
    (( $# == 1 )) || die "usage: build_dlkm.sh <vendor_dlkm|system_dlkm>"

    local partition="$1"
    local repo_root="${SCRIPT_DIR:?SCRIPT_DIR is required}"
    local dist_dir="${DIST_DIR:?DIST_DIR is required}"
    local out_dir="${OUT_DIR:?OUT_DIR is required}"
    local lkm_tools_dir="${repo_root}/prebuilts/LKM_Tools"
    local image_tools_dir="${repo_root}/prebuilts/${partition}_unpack"
    local kbuild_path="${dist_dir:-${out_dir}/dist}"
    local cooker="${lkm_tools_dir}/03.prepare_vendor_dlkm.sh"
    local partition_metadata="${lkm_tools_dir}/${partition}"
    local modules_list="${partition_metadata}/modules_list.txt"
    local modules_load="${partition_metadata}/modules.load"
    local modules_blocklist="${partition_metadata}/modules.blocklist"
    local prune_list=""
    local output_dir="${image_tools_dir}/EXTRACTED_IMAGES/extracted_${partition}"
    local modules_output_dir
    local modules_parent="${output_dir}/lib/modules"
    local module_root_relative
    local release=""
    local system_map="${kbuild_path}/System.map"
    local clang_bin="${repo_root}/kernel_platform/prebuilts/clang/host/linux-x86/clang-${TOOLCHAIN_VERSION:-r614150}/bin"
    local strip_tool="${clang_bin}/llvm-strip"
    local objcopy_tool="${clang_bin}/llvm-objcopy"
    local repack_config="${image_tools_dir}/CONFIGS/${partition}_repack.conf"
    local repacked_image="${image_tools_dir}/REPACKED_IMAGES/${partition}_repacked.img"
    local rootless_marker="${image_tools_dir}/.rootless-erofs-extract"
    local repack_metadata="${output_dir}/.repack_info/metadata.txt"
    local file_contexts="${repo_root}/prebuilts/${partition}_file_contexts"
    local stock_image="${image_tools_dir}/INPUT_IMAGES/${partition}.img"
    local final_output="${repo_root}/${partition}.img"
    local stock_modules_dir
    local labels_dir
    local custom_reference
    local stock_uuid
    local stock_label
    local stock_timestamp
    local blocklist_arg=""
    local unresolved=0
    local module
    local stock_module
    local stock_dep
    local normalized_dep
    local -a mkfs_args=()

    _dlkm_validate_partition "${partition}" || exit $?
    rm -f -- "${final_output}"
    [[ -d "${output_dir}" ]] || die "extracted ${partition} root not found: ${output_dir}"
    [[ -f "${stock_image}" ]] || die "stock ${partition} image not found: ${stock_image}"
    [[ -f "${modules_list}" ]] || die "${partition} modules list not found: ${modules_list}"
    [[ -f "${modules_load}" ]] || die "${partition} modules.load not found: ${modules_load}"
    [[ -f "${file_contexts}" ]] || die "${partition} file contexts not found: ${file_contexts}"
    [[ -x "${objcopy_tool}" ]] || die "llvm-objcopy not found: ${objcopy_tool}"
    command -v modinfo >/dev/null 2>&1 || die "modinfo not found"
    command -v fsck.erofs >/dev/null 2>&1 || die "fsck.erofs not found"
    command -v dump.erofs >/dev/null 2>&1 || die "dump.erofs not found"
    [[ -x "${cooker}" ]] || chmod +x "${cooker}"

    case "${partition}" in
        vendor_dlkm)
            modules_output_dir="${modules_parent}"
            prune_list="${lkm_tools_dir}/vendor_boot/modules_list.txt"
            ;;
        system_dlkm)
            modules_output_dir="$(discover_system_module_root "${modules_parent}")"
            release="$(basename "${modules_output_dir}")"
            [[ ! -s "${modules_blocklist}" ]] || blocklist_arg="${modules_blocklist}"
            ;;
    esac
    module_root_relative="${modules_output_dir#${output_dir}}"
    custom_reference="$(find "${kbuild_path}" -type f -name '*.ko' -print -quit)"
    [[ -n "${custom_reference}" ]] || die "no custom module found beneath ${kbuild_path}"

    stock_modules_dir="$(mktemp -d)"
    DLKM_TEMPORARY_DIRS+=("${stock_modules_dir}")
    trap cleanup_dlkm_temporary_dirs EXIT
    cp -a "${modules_output_dir}/." "${stock_modules_dir}/"

    remove_nuked_module "${stock_modules_dir}"
    remove_nuked_module "${partition_metadata}"
    if [[ "${partition}" == vendor_dlkm ]]; then
        remove_nuked_module "${lkm_tools_dir}/vendor_boot"
    fi

    "${cooker}" \
        "${modules_list}" \
        "${kbuild_path}" \
        "${modules_load}" \
        "${system_map}" \
        "${strip_tool}" \
        "${modules_output_dir}" \
        "${prune_list}" \
        "" \
        "${blocklist_arg}"

    while IFS= read -r -d '' module; do
        "${objcopy_tool}" --remove-section=.BTF --remove-section=.BTF.ext "${module}"
    done < <(find "${modules_output_dir}" -maxdepth 1 -type f -name '*.ko' -print0)

    if [[ -s "${modules_output_dir}/missing_modules.txt" ]]; then
        while IFS= read -r module; do
            [[ -n "${module}" ]] || continue
            [[ "${module}" == "$(basename "${module}")" && "${module}" == *.ko ]] ||
                die "invalid missing module name from cooker: ${module}"
            stock_module="$(find "${stock_modules_dir}" -type f -name "${module}" -print -quit)"
            if [[ -z "${stock_module}" ]]; then
                printf 'stock fallback module not found: %s\n' "${module}" >&2
                unresolved=1
                continue
            fi
            [[ "${partition}" != system_dlkm ]] || assert_stock_module_compatible "${stock_module}" "${custom_reference}"
            cp -- "${stock_module}" "${modules_output_dir}/${module}"
        done <"${modules_output_dir}/missing_modules.txt"
    fi
    (( unresolved == 0 )) || die "${partition} modules remain unresolved"
    rm -f -- "${modules_output_dir}/missing_modules.txt"

    restore_stock_metadata "${stock_modules_dir}" "${modules_output_dir}"
    if [[ "${partition}" == vendor_dlkm ]]; then
        cp -- "${modules_load}" "${modules_output_dir}/modules.load"
    else
        [[ -f "${modules_output_dir}/modules.load" ]] ||
            die "cooker did not produce ${partition} modules.load"
        normalize_system_modules_load "${modules_load}" "${modules_output_dir}"
    fi
    remove_nuked_module "${modules_output_dir}"
    [[ -f "${modules_output_dir}/modules.dep" ]] ||
        die "cooker did not produce ${partition} modules.dep"
    while IFS= read -r -d '' module; do
        module="$(basename "${module}")"
        if [[ -n "$(dependency_line_for_module "${modules_output_dir}/modules.dep" "${module}")" ]]; then
            continue
        fi
        stock_dep="$(dependency_line_for_module "${stock_modules_dir}/modules.dep" "${module}")"
        [[ -n "${stock_dep}" ]] || die "stock dependency metadata not found for ${module}"
        normalized_dep="$(normalize_stock_dependency \
            "${partition}" "${release}" "${stock_dep}")"
        printf '%s\n' "${normalized_dep}" >>"${modules_output_dir}/modules.dep"
    done < <(find "${modules_output_dir}" -maxdepth 1 -type f -name '*.ko' -print0)

    mkdir -p "$(dirname "${repack_config}")" "$(dirname "${repacked_image}")"
    printf '%s\n' \
        'ACTION=repack' \
        "SOURCE_DIR=${output_dir}" \
        "OUTPUT_IMAGE=${repacked_image}" \
        'FILESYSTEM=erofs' \
        'CREATE_SPARSE_IMAGE=false' \
        'COMPRESSION_MODE=lz4hc' \
        'COMPRESSION_LEVEL=12' \
        >"${repack_config}"

    stock_uuid="$(dlkm_image_uuid "${stock_image}")"
    [[ -n "${stock_uuid}" ]] || die "stock ${partition} UUID could not be read"
    stock_label="$(dlkm_image_label "${stock_image}")"
    rm -f -- "${repacked_image}"
    if [[ -f "${rootless_marker}" ]]; then
        command -v mkfs.erofs >/dev/null 2>&1 || die "mkfs.erofs not found"
        stock_timestamp="$(stat -c %Y "${output_dir}/etc/build.prop")"
        mkfs_args=(
            -zlz4hc,level=12
            -E^xattr-name-filter
            -T"${stock_timestamp}"
            --all-time
            --all-root
            -U"${stock_uuid}"
            --file-contexts="${file_contexts}"
        )
        [[ -z "${stock_label}" ]] || mkfs_args+=(-L "${stock_label}")
        mkfs.erofs "${mkfs_args[@]}" "${repacked_image}" "${output_dir}"
    else
        [[ -f "${repack_metadata}" ]] ||
            die "${partition} repack metadata not found: ${repack_metadata}"
        dlkm_metadata_set_identity \
            "${partition}" "${repack_metadata}" "${stock_uuid}" "${stock_label}"
        (
            cd "${image_tools_dir}"
            run_privileged ./android_image_tools.sh --conf="${repack_config}" --quiet
        )
    fi

    [[ -s "${repacked_image}" ]] ||
        die "rebuilt ${partition} image is missing or empty: ${repacked_image}"
    dlkm_capacity_pad_to_stock "${partition}" "${stock_image}" "${repacked_image}"
    labels_dir="$(mktemp -d)"
    DLKM_TEMPORARY_DIRS+=("${labels_dir}")
    run_privileged fsck.erofs -p --xattrs --extract="${labels_dir}" "${repacked_image}"
    run_privileged bash "${BUILD_DLKM_DIR}/dlkm_capacity.sh" \
        --validate-selinux-xattrs "${partition}" "${labels_dir}" "${module_root_relative}"
    dlkm_image_validate "${partition}" "${stock_image}" "${repacked_image}"
    cp -- "${repacked_image}" "${final_output}"
}

main "$@"
