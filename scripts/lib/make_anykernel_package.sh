#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/prebuilts/AnyKernel3"
SCRIPT_TEMPLATE="${REPO_ROOT}/prebuilts/anykernel.sh"
: "${ROM_VARIANT:?ROM_VARIANT must be oneui or aosp}"
case "${ROM_VARIANT}" in
    oneui|aosp) ;;
    *) echo "error: unsupported ROM_VARIANT: ${ROM_VARIANT}" >&2; exit 2 ;;
esac
OUTPUT_ZIP=""
STAGE_DIR=""

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} OUTPUT_ZIP IMAGE_DIR

IMAGE_DIR must contain:
  Image
  vendor_ramdisk/
  vendor_dlkm.img
  system_dlkm.img

Example:
  ROM_VARIANT=aosp ${SCRIPT_NAME} out/aosp/GoRhanHee_Kernel-AnyKernel3.zip \\
    out/aosp/universal/msm-kalama-kalama-gki-vanilla/packaged
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command not found: $1"
}

cleanup() {
    local exit_status=$?

    if (( exit_status != 0 )) && [[ -n "${OUTPUT_ZIP}" ]]; then
        rm -f -- "${OUTPUT_ZIP}" || true
    fi
    if [[ -n "${STAGE_DIR}" && -d "${STAGE_DIR}" ]]; then
        rm -rf -- "${STAGE_DIR}" || true
    fi

    return "${exit_status}"
}

main() {
    [[ $# -eq 2 ]] || {
        usage >&2
        exit 2
    }

    local output_zip="$1"
    local image_dir="$2"
    local output_dir
    local image

    if [[ "${output_zip}" != /* ]]; then
        output_zip="${PWD}/${output_zip}"
    fi
    if [[ "${image_dir}" != /* ]]; then
        image_dir="${PWD}/${image_dir}"
    fi
    OUTPUT_ZIP="${output_zip}"
    trap cleanup EXIT

    require_command zip

    [[ -d "${TEMPLATE_DIR}" && -f "${TEMPLATE_DIR}/tools/ak3-core.sh" ]] ||
        die "AnyKernel3 submodule is not initialized: ${TEMPLATE_DIR}"
    [[ -f "${SCRIPT_TEMPLATE}" ]] ||
        die "AnyKernel3 installer template not found: ${SCRIPT_TEMPLATE}"
    [[ -d "${image_dir}" ]] ||
        die "image directory not found: ${image_dir}"
    output_dir="$(dirname "${output_zip}")"
    mkdir -p "${output_dir}"
    rm -f -- "${output_zip}"

    STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-anykernel.XXXXXX")"

    for path in LICENSE META-INF tools; do
        [[ -e "${TEMPLATE_DIR}/${path}" ]] ||
            die "AnyKernel3 template file is missing: ${TEMPLATE_DIR}/${path}"
        cp -a "${TEMPLATE_DIR}/${path}" "${STAGE_DIR}/"
    done

    sed "s/@ROM_VARIANT@/${ROM_VARIANT}/g" \
        "${SCRIPT_TEMPLATE}" >"${STAGE_DIR}/anykernel.sh"
    cp "${REPO_ROOT}/prebuilts/sm8550-repack.sh" "${STAGE_DIR}/tools/sm8550-repack.sh"

    for image in Image vendor_dlkm.img system_dlkm.img; do
        [[ -s "${image_dir}/${image}" ]] ||
            die "required image is missing or empty: ${image_dir}/${image}"
        cp "${image_dir}/${image}" "${STAGE_DIR}/${image}"
        chmod 0644 "${STAGE_DIR}/${image}"
    done
    [[ -d "${image_dir}/vendor_ramdisk/ramdisk/lib/modules" ]] ||
        die "staged vendor ramdisk modules are missing: ${image_dir}/vendor_ramdisk"
    # Avoid gki-2.0 setup_ak automatically moving Image and vendor_ramdisk.
    cp -a "${image_dir}/vendor_ramdisk" "${STAGE_DIR}/sm8550_ramdisk"

    chmod 0755 \
        "${STAGE_DIR}/anykernel.sh" \
        "${STAGE_DIR}/META-INF/com/google/android/update-binary" \
        "${STAGE_DIR}/tools/ak3-core.sh"
    find "${STAGE_DIR}/tools" -type f ! -name ak3-core.sh -exec chmod 0755 {} +

    (
        cd "${STAGE_DIR}"
        zip -r9 -q "${output_zip}" \
            LICENSE \
            META-INF \
            tools \
            anykernel.sh \
            Image \
            sm8550_ramdisk \
            vendor_dlkm.img \
            system_dlkm.img
    )

    echo "Created ${output_zip}"
}

main "$@"
