#!/usr/bin/env bash

set -Eeuo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}"
: "${KERNEL_PLATFORM:?KERNEL_PLATFORM is required}"
: "${OUT_DIR:?OUT_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${ROM_VARIANT:?ROM_VARIANT must be oneui or aosp}"

resolved_dist_dir="$(readlink -m -- "${DIST_DIR}")"
resolved_gki_dist_dir="$(readlink -m -- "${OUT_DIR}/gki_kernel/dist")"
[[ "${resolved_dist_dir}" != "${resolved_gki_dist_dir}" ]] || {
    echo "error: MSM DIST_DIR and GKI_DIST_DIR must be different" >&2
    exit 1
}

if [[ -e "${OUT_DIR}/host/bin/ufdt_apply_overlay" ]]; then
    chmod u+w "${OUT_DIR}/host/bin/ufdt_apply_overlay"
fi

# build.config supplies GKI_BUILD_CONFIG. Qualcomm's build/build.sh uses it to
# build common into GKI_OUT_DIR first, then builds MSM against that exact tree.
echo "[kernel] Building native common/MSM mixed kernel"
(
    cd "${KERNEL_PLATFORM}"
    export BUILD_CONFIG="build.config"
    export BUILD_CONFIG_FRAGMENTS=""
    export OUT_DIR="${OUT_DIR}"
    export DIST_DIR="${resolved_dist_dir}"
    # Qualcomm defaults these to OUT_DIR/gki_kernel[/dist]. Its recursive GKI
    # build restores the caller's exported environment, so an inherited
    # GKI_DIST_DIR would copy the GKI dist directory onto itself.
    unset GKI_OUT_DIR GKI_DIST_DIR GKI_PREBUILTS_DIR
    ./build/build.sh
)

# Check both configurations before packaging artifacts from a mixed build.
for kernel_config in "${OUT_DIR}/gki_kernel/common/.config" "${OUT_DIR}/msm-kernel/.config"; do
    [[ -s "${kernel_config}" ]] || {
        echo "error: kernel config is missing: ${kernel_config}" >&2
        exit 1
    }
    case "${ROM_VARIANT}" in
        aosp)
            grep -qx 'CONFIG_AOSP=y' "${kernel_config}" || {
                echo "error: AOSP config was not enabled in ${kernel_config}" >&2
                exit 1
            }
            ;;
        oneui)
            grep -qx '# CONFIG_AOSP is not set' "${kernel_config}" || {
                echo "error: AOSP config was enabled in the OneUI build: ${kernel_config}" >&2
                exit 1
            }
            ;;
        *)
            echo "error: unsupported ROM_VARIANT: ${ROM_VARIANT}" >&2
            exit 2
            ;;
    esac
done

for gki_artifact in \
    Image Image.lz4 System.map vmlinux vmlinux.symvers \
    modules.builtin modules.builtin.modinfo; do
    [[ -s "${resolved_gki_dist_dir}/${gki_artifact}" ]] || {
        echo "error: required GKI artifact is missing: ${resolved_gki_dist_dir}/${gki_artifact}" >&2
        exit 1
    }
done

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
echo "[kernel] Artifacts: ${DIST_DIR}"
