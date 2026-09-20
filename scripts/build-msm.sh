#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${OUT_DIR:?OUT_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${GKI_DIST_DIR:?GKI_DIST_DIR is required}"
: "${WLAN_PROFILES:?WLAN_PROFILES is required}"

[[ -s "${GKI_DIST_DIR}/Image" ]] || {
    echo "error: build common first: ${GKI_DIST_DIR}/Image is missing" >&2
    exit 1
}

if [[ -e "${OUT_DIR}/host/bin/ufdt_apply_overlay" ]]; then
    chmod u+w "${OUT_DIR}/host/bin/ufdt_apply_overlay"
fi

echo "[msm] Building MSM kernel and vendor modules"
(
    cd "${KERNEL_PLATFORM}"
    export BUILD_CONFIG="build.config"
    export BUILD_CONFIG_FRAGMENTS="../scripts/msm-prebuilts.config"
    export OUT_DIR="${OUT_DIR}"
    export DIST_DIR="${DIST_DIR}"
    ./build/build.sh
)

"${SOURCE_DIR}/scripts/lib/stage_gki_artifacts.sh" "${OUT_DIR}"
for wlan_profile in ${WLAN_PROFILES}; do
    [[ -s "${DIST_DIR}/${wlan_profile}.ko" ]] || {
        echo "error: WLAN module was not built: ${DIST_DIR}/${wlan_profile}.ko" >&2
        exit 1
    }
    cp -- "${DIST_DIR}/${wlan_profile}.ko" \
        "${DIST_DIR}/qca_cld3_${wlan_profile}.ko"
done

"${SOURCE_DIR}/scripts/lib/check_display_panels.sh" \
    "${DIST_DIR}/msm_drm.ko" "${CLANG_TOOLCHAIN_DIR}/bin/llvm-nm"
echo "[msm] Artifacts: ${DIST_DIR}"
