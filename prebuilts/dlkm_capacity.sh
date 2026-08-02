#!/usr/bin/env bash

# Shared exact-capacity and identity checks for raw DLKM EROFS images.

DLKM_BLOCK_SIZE=4096

_dlkm_validate_partition() {
    case "${1:-}" in
        vendor_dlkm | system_dlkm) ;;
        *)
            printf 'unsupported DLKM partition: %s\n' "${1:-<empty>}" >&2
            return 2
            ;;
    esac
}

_dlkm_resolve_size() {
    local partition="$1"
    local image="$2"
    local label="$3"
    local size

    [[ -f "${image}" ]] || {
        printf '%s %s image must be a regular file: %s\n' \
            "${label}" "${partition}" "${image}" >&2
        return 1
    }
    size="$(stat -c %s -- "${image}")" || {
        printf 'failed to read %s %s size: %s\n' \
            "${label}" "${partition}" "${image}" >&2
        return 1
    }
    printf '%s\n' "${size}"
}

_dlkm_validate_bounds() {
    local partition="$1"
    local stock_size="$2"
    local rebuilt_size="$3"

    if (( stock_size <= 0 )); then
        printf 'stock %s size must be positive: %s\n' "${partition}" "${stock_size}" >&2
        return 1
    fi
    if (( rebuilt_size <= 0 )); then
        printf 'rebuilt %s size must be positive: %s\n' "${partition}" "${rebuilt_size}" >&2
        return 1
    fi
    if (( stock_size % DLKM_BLOCK_SIZE != 0 )); then
        printf 'stock %s size is not %s-byte aligned: %s\n' \
            "${partition}" "${DLKM_BLOCK_SIZE}" "${stock_size}" >&2
        return 1
    fi
    if (( rebuilt_size % DLKM_BLOCK_SIZE != 0 )); then
        printf 'rebuilt %s size is not %s-byte aligned: %s\n' \
            "${partition}" "${DLKM_BLOCK_SIZE}" "${rebuilt_size}" >&2
        return 1
    fi
    if (( rebuilt_size > stock_size )); then
        printf 'rebuilt %s image exceeds stock partition capacity: %s > %s bytes\n' \
            "${partition}" "${rebuilt_size}" "${stock_size}" >&2
        return 1
    fi
}

dlkm_capacity_pad_to_stock() {
    if (( $# != 3 )); then
        printf 'usage: dlkm_capacity_pad_to_stock <partition> <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi

    local partition="$1"
    local stock_image="$2"
    local rebuilt_image="$3"
    local stock_size
    local rebuilt_size
    local final_size
    local padding
    local diagnostic

    _dlkm_validate_partition "${partition}" || return
    [[ -f "${rebuilt_image}" && ! -L "${rebuilt_image}" ]] || {
        printf 'rebuilt %s image must be a regular, non-symlink file: %s\n' \
            "${partition}" "${rebuilt_image}" >&2
        return 1
    }
    command -v truncate >/dev/null 2>&1 || {
        printf 'truncate is required to pad %s images\n' "${partition}" >&2
        return 1
    }

    stock_size="$(_dlkm_resolve_size "${partition}" "${stock_image}" stock)" || return
    rebuilt_size="$(_dlkm_resolve_size "${partition}" "${rebuilt_image}" rebuilt)" || return
    diagnostic="${partition} capacity: used=${rebuilt_size} max=${stock_size} headroom=$((stock_size - rebuilt_size))"
    if ! _dlkm_validate_bounds "${partition}" "${stock_size}" "${rebuilt_size}"; then
        printf '%s\n' "${diagnostic}" >&2
        return 1
    fi

    padding=$((stock_size - rebuilt_size))
    if (( padding > 0 )); then
        truncate -s "${stock_size}" -- "${rebuilt_image}" || {
            printf 'failed to pad rebuilt %s image to %s bytes: %s\n' \
                "${partition}" "${stock_size}" "${rebuilt_image}" >&2
            return 1
        }
    fi
    final_size="$(_dlkm_resolve_size "${partition}" "${rebuilt_image}" rebuilt)" || return
    if (( final_size != stock_size )); then
        printf 'rebuilt %s image did not reach stock capacity: %s != %s bytes\n' \
            "${partition}" "${final_size}" "${stock_size}" >&2
        return 1
    fi
    printf '%s capacity padded: used_before=%s max=%s padding=%s used_after=%s\n' \
        "${partition}" "${rebuilt_size}" "${stock_size}" "${padding}" "${final_size}"
}

dlkm_capacity_validate() {
    if (( $# != 3 )); then
        printf 'usage: dlkm_capacity_validate <partition> <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi

    local partition="$1"
    local stock_size
    local rebuilt_size
    local diagnostic

    _dlkm_validate_partition "${partition}" || return
    stock_size="$(_dlkm_resolve_size "${partition}" "$2" stock)" || return
    rebuilt_size="$(_dlkm_resolve_size "${partition}" "$3" rebuilt)" || return
    diagnostic="${partition} capacity: used=${rebuilt_size} max=${stock_size} headroom=$((stock_size - rebuilt_size))"
    if ! _dlkm_validate_bounds "${partition}" "${stock_size}" "${rebuilt_size}"; then
        printf '%s\n' "${diagnostic}" >&2
        return 1
    fi
    if (( rebuilt_size != stock_size )); then
        printf '%s\n' "${diagnostic}" >&2
        printf 'rebuilt %s image must exactly match stock capacity: %s != %s bytes\n' \
            "${partition}" "${rebuilt_size}" "${stock_size}" >&2
        return 1
    fi
    printf '%s\n' "${diagnostic}"
}

dlkm_metadata_set_identity() {
    if (( $# < 3 || $# > 4 )); then
        printf 'usage: dlkm_metadata_set_identity <partition> <metadata-file> <uuid> [label]\n' >&2
        return 2
    fi

    local partition="$1"
    local metadata_file="$2"
    local filesystem_uuid="$3"
    local volume_label="${4:-}"
    local rewritten_metadata

    _dlkm_validate_partition "${partition}" || return
    [[ -f "${metadata_file}" && ! -L "${metadata_file}" ]] || {
        printf '%s metadata must be a regular, non-symlink file: %s\n' \
            "${partition}" "${metadata_file}" >&2
        return 1
    }
    [[ "${filesystem_uuid}" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
        printf 'invalid %s filesystem UUID: %s\n' "${partition}" "${filesystem_uuid}" >&2
        return 1
    }
    (( ${#volume_label} <= 15 )) || {
        printf '%s EROFS volume label exceeds 15 bytes: %s\n' \
            "${partition}" "${volume_label}" >&2
        return 1
    }

    rewritten_metadata="$(mktemp "${metadata_file}.identity.XXXXXX")" || return 1
    if ! awk '!/^ORIGINAL_UUID=/ && !/^ORIGINAL_VOLUME_NAME=/' \
        "${metadata_file}" >"${rewritten_metadata}" ||
        ! printf 'ORIGINAL_UUID=%s\nORIGINAL_VOLUME_NAME=%s\n' \
            "${filesystem_uuid}" "${volume_label}" >>"${rewritten_metadata}" ||
        ! chmod --reference="${metadata_file}" "${rewritten_metadata}" ||
        ! mv -- "${rewritten_metadata}" "${metadata_file}"; then
        rm -f -- "${rewritten_metadata}"
        printf 'failed to set %s EROFS identity metadata: %s\n' \
            "${partition}" "${metadata_file}" >&2
        return 1
    fi
}

dlkm_metadata_set_uuid() {
    if (( $# != 3 )); then
        printf 'usage: dlkm_metadata_set_uuid <partition> <metadata-file> <uuid>\n' >&2
        return 2
    fi
    local volume_label

    volume_label="$(awk -F= '/^ORIGINAL_VOLUME_NAME=/ {
        value = substr($0, index($0, "=") + 1)
    } END { print value }' "$2")"
    dlkm_metadata_set_identity "$1" "$2" "$3" "${volume_label}"
}

dlkm_image_uuid() {
    dump.erofs -s "$1" 2>/dev/null | awk '/Filesystem UUID:/ { print $NF; exit }'
}

dlkm_image_label() {
    file -b -- "$1" 2>/dev/null |
        sed -n 's/.*[ ,]name=\([^, ]*\).*/\1/p'
}

dlkm_image_has_avbf_footer() {
    local image="$1"
    local size
    local footer_magic
    local final_magic

    size="$(_dlkm_resolve_size dlkm "${image}" rebuilt 2>/dev/null)" || return 1
    (( size >= 64 )) || return 1
    footer_magic="$(od -An -tx1 -j $((size - 64)) -N 4 -- "${image}" | tr -d ' \n')"
    final_magic="$(od -An -tx1 -j $((size - 4)) -N 4 -- "${image}" | tr -d ' \n')"
    [[ "${footer_magic}" == 41564266 || "${final_magic}" == 41564266 ]]
}

dlkm_image_validate() {
    if (( $# != 3 )); then
        printf 'usage: dlkm_image_validate <partition> <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi

    local partition="$1"
    local stock_image="$2"
    local rebuilt_image="$3"
    local stock_uuid
    local rebuilt_uuid
    local stock_label
    local rebuilt_label

    _dlkm_validate_partition "${partition}" || return
    dlkm_capacity_validate "${partition}" "${stock_image}" "${rebuilt_image}" >/dev/null || return
    command -v fsck.erofs >/dev/null 2>&1 || {
        printf 'fsck.erofs is required to validate %s\n' "${partition}" >&2
        return 1
    }
    command -v dump.erofs >/dev/null 2>&1 || {
        printf 'dump.erofs is required to validate %s\n' "${partition}" >&2
        return 1
    }
    fsck.erofs -p --xattrs "${rebuilt_image}" >/dev/null 2>&1 || {
        printf 'rebuilt %s image failed EROFS integrity validation: %s\n' \
            "${partition}" "${rebuilt_image}" >&2
        return 1
    }
    stock_uuid="$(dlkm_image_uuid "${stock_image}")"
    rebuilt_uuid="$(dlkm_image_uuid "${rebuilt_image}")"
    [[ -n "${stock_uuid}" ]] || {
        printf 'stock %s UUID could not be read\n' "${partition}" >&2
        return 1
    }
    [[ -n "${rebuilt_uuid}" ]] || {
        printf 'rebuilt %s UUID could not be read\n' "${partition}" >&2
        return 1
    }
    [[ "${rebuilt_uuid}" == "${stock_uuid}" ]] || {
        printf 'rebuilt %s UUID differs from stock: %s != %s\n' \
            "${partition}" "${rebuilt_uuid}" "${stock_uuid}" >&2
        return 1
    }
    stock_label="$(dlkm_image_label "${stock_image}")"
    rebuilt_label="$(dlkm_image_label "${rebuilt_image}")"
    [[ "${rebuilt_label}" == "${stock_label}" ]] || {
        printf 'rebuilt %s EROFS label differs from stock: %s != %s\n' \
            "${partition}" "${rebuilt_label:-<empty>}" "${stock_label:-<empty>}" >&2
        return 1
    }
    if dlkm_image_has_avbf_footer "${rebuilt_image}"; then
        printf 'rebuilt %s image retains an AVBf footer\n' "${partition}" >&2
        return 1
    fi
    printf '%s identity: uuid=%s label=%s avb_footer=absent\n' \
        "${partition}" "${rebuilt_uuid}" "${rebuilt_label:-<empty>}"
}

dlkm_selinux_xattrs_validate() {
    if (( $# < 2 || $# > 3 )); then
        printf 'usage: dlkm_selinux_xattrs_validate <partition> <root> [module-root]\n' >&2
        return 2
    fi

    local partition="$1"
    local extracted_root="$2"
    local module_root="${3:-/lib/modules}"
    local path
    local target
    local value
    local expected
    local description='SELinux label'
    local -a paths=(/ /etc/build.prop /lib/modules)

    _dlkm_validate_partition "${partition}" || return
    command -v getfattr >/dev/null 2>&1 || {
        printf 'getfattr is required to validate named %s SELinux xattrs\n' \
            "${partition}" >&2
        return 1
    }
    [[ "${module_root}" == /lib/modules || "${module_root}" == /lib/modules/* ]] || {
        printf 'invalid %s module root for label validation: %s\n' \
            "${partition}" "${module_root}" >&2
        return 1
    }
    if [[ "${partition}" == system_dlkm && "${module_root}" != /lib/modules ]]; then
        paths+=("${module_root}")
    fi
    [[ "${partition}" != vendor_dlkm ]] || description='SELinux xattr'

    for path in "${paths[@]}"; do
        target="${extracted_root}${path}"
        value="$(set -o pipefail; getfattr --absolute-names --only-values \
            -n security.selinux -- "${target}" 2>/dev/null | tr -d '\000\n')" || {
            printf '%s %s security.selinux missing from %s\n' \
                "${partition}" "${description}" "${path}" >&2
            return 1
        }
        case "${partition}:${path}" in
            vendor_dlkm:/etc/build.prop) expected='u:object_r:vendor_configs_file:s0' ;;
            vendor_dlkm:*) expected='u:object_r:vendor_file:s0' ;;
            system_dlkm:*) expected='u:object_r:system_dlkm_file:s0' ;;
        esac
        [[ "${value}" == "${expected}" ]] || {
            printf '%s %s security.selinux differs on %s: %s != %s\n' \
                "${partition}" "${description}" "${path}" \
                "${value:-<empty>}" "${expected}" >&2
            return 1
        }
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --pad)
            shift
            dlkm_capacity_pad_to_stock "$@"
            ;;
        --validate-image)
            shift
            dlkm_image_validate "$@"
            ;;
        --validate-selinux-xattrs)
            shift
            dlkm_selinux_xattrs_validate "$@"
            ;;
        *)
            dlkm_capacity_validate "$@"
            ;;
    esac
fi
