#!/usr/bin/env bash

set -Eeuo pipefail

[[ $# -eq 2 ]] || {
    echo "usage: $0 FLASHABLE_ZIP IMAGE_DIR" >&2
    exit 2
}

readonly FLASHABLE_ZIP="$1"
readonly IMAGE_DIR="$2"
readonly UPDATER_PATH="META-INF/com/google/android/updater-script"
readonly HELPER_PATH="META-INF/com/google/android/dm3q-flash-image.sh"

for image in boot.img vendor_boot.img vendor_dlkm.img; do
    source_hash="$(sha256sum "${IMAGE_DIR}/${image}" | awk '{ print $1 }')"
    archive_hash="$(unzip -p "${FLASHABLE_ZIP}" "files/${image}" | sha256sum | awk '{ print $1 }')"
    [[ "${archive_hash}" == "${source_hash}" ]] || {
        echo "${image} differs between source and ZIP" >&2
        exit 1
    }
done

updater="$(unzip -p "${FLASHABLE_ZIP}" "${UPDATER_PATH}")"
helper="$(unzip -p "${FLASHABLE_ZIP}" "${HELPER_PATH}")"

if grep -Fq 'set_perm(' <<<"${updater}"; then
    echo "updater-script uses unsupported set_perm()" >&2
    exit 1
fi

grep -Fq 'run_program("/sbin/sh", "/tmp/dm3q-flash-image.sh", "vendor_dlkm"' <<<"${updater}"
grep -Fq 'run_program("/sbin/sh", "/tmp/dm3q-flash-image.sh", "vendor_boot"' <<<"${updater}"
grep -Fq 'run_program("/sbin/sh", "/tmp/dm3q-flash-image.sh", "boot"' <<<"${updater}"
grep -Fq 'run_program("/sbin/sh", "-c", "umount /vendor_dlkm >/dev/null 2>&1 || true");' <<<"${updater}"
grep -Fq 'assert(unmap_partition("vendor_dlkm"));' <<<"${updater}"
grep -Fq 'assert(map_partition("vendor_dlkm"));' <<<"${updater}"
grep -Fq 'assert(' <<<"${updater}"
[[ "$(grep -Fc 'run_program("/sbin/sh", "/tmp/dm3q-flash-image.sh"' <<<"${updater}")" == "3" ]]
[[ "$(grep -Fc 'unmap_partition("vendor_dlkm")' <<<"${updater}")" == "2" ]]
unmount_line="$(grep -Fn 'umount /vendor_dlkm >/dev/null 2>&1 || true' <<<"${updater}" | cut -d: -f1)"
remap_unmap_line="$(grep -Fn 'assert(unmap_partition("vendor_dlkm"));' <<<"${updater}" | cut -d: -f1)"
map_line="$(grep -Fn 'assert(map_partition("vendor_dlkm"));' <<<"${updater}" | cut -d: -f1)"
vendor_dlkm_line="$(grep -Fn '"vendor_dlkm", "/tmp/vendor_dlkm.img"' <<<"${updater}" | cut -d: -f1)"
vendor_boot_line="$(grep -Fn '"vendor_boot", "/tmp/vendor_boot.img"' <<<"${updater}" | cut -d: -f1)"
boot_line="$(grep -Fn '"boot", "/tmp/boot.img"' <<<"${updater}" | cut -d: -f1)"
[[ "${unmount_line}" -lt "${remap_unmap_line}" ]]
[[ "${remap_unmap_line}" -lt "${map_line}" ]]
[[ "${map_line}" -lt "${vendor_dlkm_line}" ]]
[[ "${vendor_dlkm_line}" -lt "${vendor_boot_line}" ]]
[[ "${vendor_boot_line}" -lt "${boot_line}" ]]

grep -Fq '[ -b "${candidate}" ]' <<<"${helper}"
grep -Fq 'blockdev --getsize64' <<<"${helper}"
grep -Fq 'dd if="${IMAGE}" of="${TARGET}"' <<<"${helper}"
grep -Fq 'dd if="${TARGET}" bs=4096 count="${BLOCKS}"' <<<"${helper}"
grep -Fq 'sha256sum' <<<"${helper}"
