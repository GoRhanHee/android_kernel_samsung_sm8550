#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${OUT_DIR:?OUT_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${GKI_DIST_DIR:?GKI_DIST_DIR is required}"

MSM_DIST_DIR="$(readlink -m -- "${DIST_DIR}")"
MSM_GKI_DIST_DIR="$(readlink -m -- "${GKI_DIST_DIR}")"
[[ "${MSM_DIST_DIR}" != "${MSM_GKI_DIST_DIR}" ]] || {
    echo "error: MSM DIST_DIR and GKI_DIST_DIR must be different" >&2
    exit 1
}

for gki_artifact in \
    Image Image.lz4 System.map vmlinux vmlinux.symvers \
    modules.builtin modules.builtin.modinfo; do
    [[ -s "${MSM_GKI_DIST_DIR}/${gki_artifact}" ]] || {
        echo "error: required GKI artifact is missing: ${MSM_GKI_DIST_DIR}/${gki_artifact}" >&2
        exit 1
    }
done

if [[ -e "${OUT_DIR}/host/bin/ufdt_apply_overlay" ]]; then
    chmod u+w "${OUT_DIR}/host/bin/ufdt_apply_overlay"
fi

echo "[msm] Building MSM kernel and vendor modules"
(
    cd "${KERNEL_PLATFORM}"
    export BUILD_CONFIG="build.config"
    export BUILD_CONFIG_FRAGMENTS="../scripts/msm_prebuilts.config"
    export OUT_DIR="${OUT_DIR}"
    export DIST_DIR="${MSM_DIST_DIR}"
    export GKI_DIST_DIR="${MSM_GKI_DIST_DIR}"
    ./build/build.sh
)

"${SOURCE_DIR}/scripts/lib/stage_gki_artifacts.sh" "${OUT_DIR}"
for wlan_module in qca6490 kiwi_v2; do
    [[ -s "${DIST_DIR}/${wlan_module}.ko" ]] || {
        echo "error: WLAN module was not built: ${DIST_DIR}/${wlan_module}.ko" >&2
        exit 1
    }
    cp -- "${DIST_DIR}/${wlan_module}.ko" \
        "${DIST_DIR}/qca_cld3_${wlan_module}.ko"
done

"${SOURCE_DIR}/scripts/lib/check_display_panels.sh" \
    "${DIST_DIR}/msm_drm.ko" "${CLANG_TOOLCHAIN_DIR}/bin/llvm-nm"
echo "[msm] Artifacts: ${DIST_DIR}"
