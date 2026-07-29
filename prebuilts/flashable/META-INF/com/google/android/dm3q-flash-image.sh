#!/sbin/sh

set -eu

PARTITION="${1:?partition name is required}"
IMAGE="${2:?image path is required}"

case "${PARTITION}" in
    boot|vendor_boot|vendor_dlkm) ;;
    *)
        echo "unsupported partition: ${PARTITION}" >&2
        exit 10
        ;;
esac

[ -s "${IMAGE}" ] || {
    echo "image is missing or empty: ${IMAGE}" >&2
    exit 11
}

MOUNTED_SOURCE=""
if [ "${PARTITION}" = "vendor_dlkm" ]; then
    MOUNTED_SOURCE="$(awk '$2 == "/vendor_dlkm" { print $1; exit }' /proc/mounts)"
fi

TARGET=""
for candidate in \
    "${MOUNTED_SOURCE}" \
    "/dev/block/mapper/${PARTITION}" \
    "/dev/block/by-name/${PARTITION}" \
    /dev/block/platform/*/by-name/"${PARTITION}"
do
    if [ -n "${candidate}" ] && [ -b "${candidate}" ]; then
        TARGET="${candidate}"
        break
    fi
done

[ -n "${TARGET}" ] || {
    echo "${PARTITION} block device was not found" >&2
    exit 12
}

if [ "${PARTITION}" = "vendor_dlkm" ] &&
    grep -q ' /vendor_dlkm ' /proc/mounts; then
    umount /vendor_dlkm || {
        echo "failed to unmount /vendor_dlkm" >&2
        exit 13
    }
fi

for tool in awk blockdev dd sha256sum sync wc; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "required recovery command not found: ${tool}" >&2
        exit 14
    }
done

SIZE="$(wc -c < "${IMAGE}")"
[ "$((SIZE % 4096))" -eq 0 ] || {
    echo "${PARTITION} image size is not 4096-byte aligned" >&2
    exit 15
}

TARGET_SIZE="$(blockdev --getsize64 "${TARGET}")"
[ "${TARGET_SIZE}" -ge "${SIZE}" ] || {
    echo "${PARTITION} image (${SIZE} bytes) is larger than ${TARGET} (${TARGET_SIZE} bytes)" >&2
    exit 16
}

blockdev --setrw "${TARGET}" >/dev/null 2>&1 || true

echo "Flashing ${PARTITION} to ${TARGET}"
dd if="${IMAGE}" of="${TARGET}" bs=4096
sync
blockdev --flushbufs "${TARGET}" >/dev/null 2>&1 || true

BLOCKS="$((SIZE / 4096))"
EXPECTED="$(sha256sum "${IMAGE}" | awk '{ print $1 }')"
ACTUAL="$(
    dd if="${TARGET}" bs=4096 count="${BLOCKS}" 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
)"

[ "${ACTUAL}" = "${EXPECTED}" ] || {
    echo "${PARTITION} verification failed" >&2
    echo "expected ${EXPECTED}" >&2
    echo "actual   ${ACTUAL}" >&2
    exit 17
}

echo "${PARTITION} verified: ${ACTUAL}"
rm -f "${IMAGE}"
