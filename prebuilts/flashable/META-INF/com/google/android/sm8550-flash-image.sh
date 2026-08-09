#!/sbin/sh

set -u

log() {
    printf '%s\n' "[sm8550-flash] $*" >&2
}

warn() {
    log "WARNING: $*"
}

fail() {
    code="$1"
    shift
    log "ERROR exit=${code}: $*"
    exit "${code}"
}

resolve_tool() {
    name="$1"

    # Keep the resolved value directly executable. Encoding it as kind|path
    # breaks parameter expansion in Android recovery's mksh.
    direct="$(command -v "${name}" 2>/dev/null)" || direct=""
    if [ -n "${direct}" ]; then
        printf '%s' "${direct}"
        return 0
    fi

    for direct in \
        "/sbin/${name}" \
        "/system/bin/${name}" \
        "/vendor/bin/${name}"
    do
        if [ -x "${direct}" ]; then
            printf '%s' "${direct}"
            return 0
        fi
    done

    return 1
}

mounted_source() {
    mountpoint_to_find="$1"
    mounts_file="$2"
    [ -r "${mounts_file}" ] || return 1

    while IFS=' ' read -r source mountpoint remainder; do
        if [ "${mountpoint}" = "${mountpoint_to_find}" ]; then
            printf '%s\n' "${source}"
            return 0
        fi
    done < "${mounts_file}"

    return 1
}

select_block_target() {
    candidate="$1"
    [ -n "${candidate}" ] || return 1
    [ -b "${candidate}" ] || return 1

    TARGET="${candidate}"
    if [ -n "${READLINK_TOOL}" ]; then
        resolved=""
        if resolved="$("${READLINK_TOOL}" -f "${candidate}" 2>/dev/null)" &&
            [ -n "${resolved}" ] &&
            [ -b "${resolved}" ]; then
            TARGET="${resolved}"
        fi
    fi

    return 0
}

[ "$#" -eq 2 ] ||
    fail 2 "expected PARTITION and IMAGE arguments"

PARTITION="$1"
IMAGE="$2"

case "${PARTITION}" in
    boot|vendor_boot|system_dlkm|vendor_dlkm) ;;
    *)
        fail 10 "unsupported partition: ${PARTITION}"
        ;;
esac

[ -s "${IMAGE}" ] ||
    fail 11 "image is missing or empty: ${IMAGE}"

if ! DD_TOOL="$(resolve_tool dd)"; then
    fail 14 "required recovery command not found: dd"
fi
if ! SYNC_TOOL="$(resolve_tool sync)"; then
    fail 14 "required recovery command not found: sync"
fi
if ! WC_TOOL="$(resolve_tool wc)"; then
    fail 14 "required recovery command not found: wc"
fi
if ! SHA256_TOOL="$(resolve_tool sha256sum)"; then
    fail 14 "required recovery command not found: sha256sum"
fi

TARGET=""
TEST_TARGET="${SM8550_FLASH_TEST_TARGET-}"
TEST_ALLOW_FILE="${SM8550_FLASH_TEST_ALLOW_FILE_TARGET-0}"
TEST_FILE_TARGET=0

if [ -n "${TEST_TARGET}" ] || [ "${TEST_ALLOW_FILE}" != "0" ]; then
    [ "${TEST_ALLOW_FILE}" = "1" ] ||
        fail 20 "test target requires SM8550_FLASH_TEST_ALLOW_FILE_TARGET=1"
    [ -n "${TEST_TARGET}" ] &&
        [ -f "${TEST_TARGET}" ] &&
        [ ! -L "${TEST_TARGET}" ] ||
        fail 20 "test target must be an existing, non-symlink regular file"
    TARGET="${TEST_TARGET}"
    TEST_FILE_TARGET=1
    warn "TEST-ONLY regular-file target override enabled: ${TARGET}"
fi

MOUNT_POINT=""
case "${PARTITION}" in
    system_dlkm|vendor_dlkm)
        MOUNT_POINT="/${PARTITION}"
        ;;
esac

MOUNTS_FILE=/proc/mounts
TEST_MOUNTS_FILE="${SM8550_FLASH_TEST_MOUNTS_FILE-}"
if [ -n "${TEST_MOUNTS_FILE}" ]; then
    [ "${TEST_FILE_TARGET}" -eq 1 ] ||
        fail 20 "test mounts file requires regular-file target override"
    [ -f "${TEST_MOUNTS_FILE}" ] && [ ! -L "${TEST_MOUNTS_FILE}" ] ||
        fail 20 "test mounts file must be an existing, non-symlink regular file"
    MOUNTS_FILE="${TEST_MOUNTS_FILE}"
fi

MOUNTED_SOURCE=""
if [ -n "${MOUNT_POINT}" ]; then
    MOUNTED_SOURCE="$(mounted_source "${MOUNT_POINT}" "${MOUNTS_FILE}")" ||
        MOUNTED_SOURCE=""
fi

if [ "${TEST_FILE_TARGET}" -ne 1 ]; then
    READLINK_TOOL=""
    READLINK_TOOL="$(resolve_tool readlink)" || READLINK_TOOL=""

    for candidate in \
        "/dev/block/mapper/${PARTITION}" \
        "${MOUNTED_SOURCE}" \
        "/dev/block/by-name/${PARTITION}" \
        "/dev/block/bootdevice/by-name/${PARTITION}" \
        /dev/block/platform/*/by-name/"${PARTITION}" \
        /dev/block/platform/*/*/by-name/"${PARTITION}" \
        /dev/block/platform/*/*/*/by-name/"${PARTITION}" \
        /dev/block/platform/*/*/*/*/by-name/"${PARTITION}"
    do
        if select_block_target "${candidate}"; then
            break
        fi
    done
fi

[ -n "${TARGET}" ] ||
    fail 12 "${PARTITION} block device was not found"

if [ "${TEST_FILE_TARGET}" -ne 1 ] && [ ! -b "${TARGET}" ]; then
    fail 12 "resolved target is not a block device: ${TARGET}"
fi

if [ -n "${MOUNT_POINT}" ] && [ -n "${MOUNTED_SOURCE}" ]; then
    if ! UMOUNT_TOOL="$(resolve_tool umount)"; then
        fail 13 "${PARTITION} is mounted but no umount command is available"
    fi
    if ! "${UMOUNT_TOOL}" "${MOUNT_POINT}"; then
        fail 13 "failed to unmount ${MOUNT_POINT}"
    fi
    log "unmounted ${MOUNT_POINT}"
fi

SIZE_RAW=""
if ! SIZE_RAW="$("${WC_TOOL}" -c < "${IMAGE}")"; then
    fail 15 "could not determine image size: ${IMAGE}"
fi
set -f
set -- ${SIZE_RAW}
set +f
[ "$#" -eq 1 ] ||
    fail 15 "invalid image size output: ${SIZE_RAW}"
SIZE="$1"
case "${SIZE}" in
    ''|*[!0-9]*)
        fail 15 "invalid image size output: ${SIZE_RAW}"
        ;;
esac

[ "$((SIZE % 4096))" -eq 0 ] ||
    fail 15 "${PARTITION} image size is not 4096-byte aligned: ${SIZE}"

BLOCKDEV_TOOL=""
if [ "${TEST_FILE_TARGET}" -ne 1 ]; then
    if ! BLOCKDEV_TOOL="$(resolve_tool blockdev)"; then
        fail 14 "required recovery command not found: blockdev"
    fi
fi

if [ "${TEST_FILE_TARGET}" -eq 1 ]; then
    TARGET_SIZE_RAW="$("${WC_TOOL}" -c < "${TARGET}")" ||
        fail 16 "could not determine test target capacity"
    set -f
    set -- ${TARGET_SIZE_RAW}
    set +f
    TARGET_SIZE="$1"
    [ "${TARGET_SIZE}" -ge "${SIZE}" ] ||
        fail 16 "image (${SIZE} bytes) is larger than target (${TARGET_SIZE} bytes)"
elif [ -n "${BLOCKDEV_TOOL}" ]; then
    TARGET_SIZE="$("${BLOCKDEV_TOOL}" --getsize64 "${TARGET}" 2>/dev/null)" ||
        fail 16 "could not determine target capacity: ${TARGET}"
    [ -n "${TARGET_SIZE}" ] ||
        fail 16 "could not determine target capacity: ${TARGET}"
    case "${TARGET_SIZE}" in
        *[!0-9]*)
            fail 16 "invalid target capacity reported for ${TARGET}: ${TARGET_SIZE}"
            ;;
    esac
    [ "${TARGET_SIZE}" -ge "${SIZE}" ] ||
        fail 16 "image (${SIZE} bytes) is larger than ${TARGET} (${TARGET_SIZE} bytes)"
    log "capacity verified: image=${SIZE} target=${TARGET_SIZE}"
fi

if [ -n "${BLOCKDEV_TOOL}" ] && [ "${TEST_FILE_TARGET}" -ne 1 ]; then
    "${BLOCKDEV_TOOL}" --setrw "${TARGET}" >/dev/null 2>&1 ||
        warn "could not request read-write mode for ${TARGET}"
fi

log "flashing ${PARTITION} to ${TARGET} (${SIZE} bytes)"
if ! "${DD_TOOL}" if="${IMAGE}" of="${TARGET}" bs=4096; then
    fail 18 "dd failed while writing ${PARTITION} to ${TARGET}"
fi
if ! "${SYNC_TOOL}"; then
    fail 19 "sync failed after writing ${PARTITION}"
fi

if [ -n "${BLOCKDEV_TOOL}" ] && [ "${TEST_FILE_TARGET}" -ne 1 ]; then
    "${BLOCKDEV_TOOL}" --flushbufs "${TARGET}" >/dev/null 2>&1 ||
        warn "could not flush block-device buffers for ${TARGET}"
fi

EXPECTED_LINE="$("${SHA256_TOOL}" "${IMAGE}")" ||
    fail 17 "could not hash source image"
EXPECTED="${EXPECTED_LINE%% *}"
BLOCKS="$((SIZE / 4096))"
ACTUAL_LINE="$(
    "${DD_TOOL}" if="${TARGET}" bs=4096 count="${BLOCKS}" 2>/dev/null |
        "${SHA256_TOOL}"
)" || fail 17 "could not hash the written range"
ACTUAL="${ACTUAL_LINE%% *}"

[ "${ACTUAL}" = "${EXPECTED}" ] ||
    fail 17 "${PARTITION} readback hash mismatch: expected=${EXPECTED} actual=${ACTUAL}"
log "${PARTITION} readback verified: ${ACTUAL}"

RM_TOOL=""
RM_TOOL="$(resolve_tool rm)" || RM_TOOL=""
if [ -n "${RM_TOOL}" ]; then
    "${RM_TOOL}" -f "${IMAGE}" ||
        warn "could not remove temporary image: ${IMAGE}"
else
    warn "rm unavailable; temporary image retained: ${IMAGE}"
fi

log "${PARTITION} flash complete"
