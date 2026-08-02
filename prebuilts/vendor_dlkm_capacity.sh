#!/usr/bin/env bash

# Compatibility facade for callers that still use the vendor-specific API.

readonly _VENDOR_DLKM_CAPACITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dlkm_capacity.sh
source "${_VENDOR_DLKM_CAPACITY_DIR}/dlkm_capacity.sh"

VENDOR_DLKM_BLOCK_SIZE="${DLKM_BLOCK_SIZE}"

vendor_dlkm_metadata_set_uuid() {
    if (( $# != 2 )); then
        printf 'usage: vendor_dlkm_metadata_set_uuid <metadata-file> <uuid>\n' >&2
        return 2
    fi
    dlkm_metadata_set_uuid vendor_dlkm "$1" "$2"
}

_vendor_dlkm_capacity_resolve_size() {
    _dlkm_resolve_size vendor_dlkm "$1" "$2"
}

_vendor_dlkm_capacity_validate_bounds() {
    _dlkm_validate_bounds vendor_dlkm "$1" "$2"
}

vendor_dlkm_capacity_pad_to_stock() {
    if (( $# != 2 )); then
        printf 'usage: vendor_dlkm_capacity_pad_to_stock <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi
    dlkm_capacity_pad_to_stock vendor_dlkm "$1" "$2"
}

vendor_dlkm_capacity_validate() {
    if (( $# != 2 )); then
        printf 'usage: vendor_dlkm_capacity_validate <stock-file> <rebuilt-file>\n' >&2
        return 2
    fi
    dlkm_capacity_validate vendor_dlkm "$1" "$2"
}

vendor_dlkm_selinux_xattrs_validate() {
    if (( $# != 1 )); then
        printf 'usage: vendor_dlkm_selinux_xattrs_validate <extracted-image-root>\n' >&2
        return 2
    fi
    dlkm_selinux_xattrs_validate vendor_dlkm "$1" /lib/modules
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --validate-selinux-xattrs)
            shift
            vendor_dlkm_selinux_xattrs_validate "$@"
            ;;
        *)
            vendor_dlkm_capacity_validate "$@"
            ;;
    esac
fi
