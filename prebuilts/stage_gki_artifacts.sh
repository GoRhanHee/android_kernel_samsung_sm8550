#!/usr/bin/env bash

set -Eeuo pipefail

readonly STAGE_GKI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
(( $# == 1 )) || { echo "usage: $0 <build output directory>" >&2; exit 1; }
readonly GKI_DIST="$1/gki_kernel/dist"
readonly DIST="$1/dist"
readonly SYSTEM_LIST="${GKI_DIST}/system_dlkm.modules.load"

release="$("${STAGE_GKI_DIR}/kernel_release.sh" "$1/gki_kernel/common/include/config/kernel.release")"
[[ -d "${DIST}" && -s "${SYSTEM_LIST}" ]] || {
    echo "error: GKI dist or system module load list not found beneath $1" >&2
    exit 1
}

# The mixed build copies device modules after GKI artifacts. Restore the GKI
# system modules so same-name device modules cannot replace their signatures.
while IFS= read -r module || [[ -n "${module}" ]]; do
    [[ "${module}" == *.ko ]] || continue
    module="${module##*/}"
    [[ -s "${GKI_DIST}/${module}" ]] || {
        echo "error: built GKI system module not found: ${GKI_DIST}/${module}" >&2
        exit 1
    }
    cp -- "${GKI_DIST}/${module}" "${DIST}/${module}"
done <"${SYSTEM_LIST}"
cp -- "${SYSTEM_LIST}" "${DIST}/system_dlkm.modules.load"
printf '%s\n' "${release}" >"${DIST}/kernel.release"
echo "[packaging] Staged GKI system modules for ${release}"
