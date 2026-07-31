#!/usr/bin/env bash

# Validate vendor_dlkm image sizes. This file is sourceable by packaging
# scripts and executable as a deterministic exact-size check.

VENDOR_DLKM_BLOCK_SIZE=4096

_vendor_dlkm_capacity_resolve_size() {
    local image="$1"
    local label="$2"
    local size

    [[ -f "${image}" ]] || {
        printf '%s vendor_dlkm image must be a regular file: %s\n' "${label}" "${image}" >&2
        return 1
    }

    if ! size="$(stat -c %s -- "${image}")"; then
        printf 'failed to read %s vendor_dlkm size: %s\n' "${label}" "${image}" >&2
        return 1
    fi
    printf '%s\n' "${size}"
}

_vendor_dlkm_capacity_validate_bounds() {
    local stock_size="$1"
    local rebuilt_size="$2"

    if (( stock_size <= 0 )); then
        printf 'stock vendor_dlkm size must be positive: %s\n' "${stock_size}" >&2
        return 1
    fi
    if (( rebuilt_size <= 0 )); then
        printf 'rebuilt vendor_dlkm size must be positive: %s\n' "${rebuilt_size}" >&2
        return 1
    fi
    if (( stock_size % VENDOR_DLKM_BLOCK_SIZE != 0 )); then
        printf 'stock vendor_dlkm size is not %s-byte aligned: %s\n' \
            "${VENDOR_DLKM_BLOCK_SIZE}" "${stock_size}" >&2
        return 1
    fi
    if (( rebuilt_size % VENDOR_DLKM_BLOCK_SIZE != 0 )); then
        printf 'rebuilt vendor_dlkm size is not %s-byte aligned: %s\n' \
            "${VENDOR_DLKM_BLOCK_SIZE}" "${rebuilt_size}" >&2
        return 1
    fi
    if (( rebuilt_size > stock_size )); then
        printf 'rebuilt vendor_dlkm image exceeds stock partition capacity: %s > %s bytes\n' \
            "${rebuilt_size}" "${stock_size}" >&2
        return 1
    fi
}

vendor_dlkm_capacity_pad_to_stock() {
    if (( $# != 2 )); then
        printf 'usage: vendor_dlkm_capacity_pad_to_stock <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi

    local stock_image="$1"
    local rebuilt_image="$2"
    local stock_size
    local rebuilt_size
    local final_size
    local padding
    local diagnostic

    [[ -f "${rebuilt_image}" && ! -L "${rebuilt_image}" ]] || {
        printf 'rebuilt vendor_dlkm image must be a regular, non-symlink file: %s\n' \
            "${rebuilt_image}" >&2
        return 1
    }
    command -v truncate >/dev/null 2>&1 || {
        printf 'truncate is required to pad vendor_dlkm images\n' >&2
        return 1
    }

    stock_size="$(_vendor_dlkm_capacity_resolve_size "${stock_image}" stock)" || return 1
    rebuilt_size="$(_vendor_dlkm_capacity_resolve_size "${rebuilt_image}" rebuilt)" || return 1
    diagnostic="vendor_dlkm capacity: used=${rebuilt_size} max=${stock_size} headroom=$((stock_size - rebuilt_size))"

    # Every rejection happens before truncate, so failed validation cannot
    # alter the rebuilt image.
    if ! _vendor_dlkm_capacity_validate_bounds "${stock_size}" "${rebuilt_size}"; then
        printf '%s\n' "${diagnostic}" >&2
        return 1
    fi

    padding=$((stock_size - rebuilt_size))
    if (( padding > 0 )); then
        truncate -s "${stock_size}" -- "${rebuilt_image}" || {
            printf 'failed to pad rebuilt vendor_dlkm image to %s bytes: %s\n' \
                "${stock_size}" "${rebuilt_image}" >&2
            return 1
        }
    fi

    final_size="$(_vendor_dlkm_capacity_resolve_size "${rebuilt_image}" rebuilt)" || return 1
    if (( final_size != stock_size )); then
        printf 'rebuilt vendor_dlkm image did not reach stock capacity: %s != %s bytes\n' \
            "${final_size}" "${stock_size}" >&2
        return 1
    fi

    printf 'vendor_dlkm capacity padded: used_before=%s max=%s padding=%s used_after=%s\n' \
        "${rebuilt_size}" "${stock_size}" "${padding}" "${final_size}"
}

vendor_dlkm_capacity_validate() {
    if (( $# != 2 )); then
        printf 'usage: vendor_dlkm_capacity_validate <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi

    local stock_size
    local rebuilt_size
    local diagnostic

    stock_size="$(_vendor_dlkm_capacity_resolve_size "$1" stock)" || return 1
    rebuilt_size="$(_vendor_dlkm_capacity_resolve_size "$2" rebuilt)" || return 1
    diagnostic="vendor_dlkm capacity: used=${rebuilt_size} max=${stock_size} headroom=$((stock_size - rebuilt_size))"

    if ! _vendor_dlkm_capacity_validate_bounds "${stock_size}" "${rebuilt_size}"; then
        printf '%s\n' "${diagnostic}" >&2
        return 1
    fi
    if (( rebuilt_size != stock_size )); then
        printf '%s\n' "${diagnostic}" >&2
        printf 'rebuilt vendor_dlkm image must exactly match stock capacity: %s != %s bytes\n' \
            "${rebuilt_size}" "${stock_size}" >&2
        return 1
    fi

    printf '%s\n' "${diagnostic}"
}

vendor_dlkm_selinux_xattrs_validate() {
    if (( $# != 1 )); then
        printf 'usage: vendor_dlkm_selinux_xattrs_validate <extracted-image-root>\n' >&2
        return 2
    fi
    command -v getfattr >/dev/null 2>&1 || {
        printf 'getfattr is required to validate named vendor_dlkm SELinux xattrs\n' >&2
        return 1
    }

    local extracted_root="$1"
    local path
    local target
    local value
    for path in / /etc/build.prop /lib/modules; do
        target="${extracted_root}${path}"
        value="$(
            getfattr --absolute-names --only-values \
                -n security.selinux -- "${target}" 2>/dev/null
        )" || {
            printf 'vendor_dlkm SELinux xattr security.selinux missing from %s\n' "${path}" >&2
            return 1
        }
        [[ -n "${value}" ]] || {
            printf 'vendor_dlkm SELinux xattr security.selinux is empty on %s\n' "${path}" >&2
            return 1
        }
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vendor_dlkm_capacity_validate "$@"
fi
