#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/AnyKernel3"
readonly SCRIPT_TEMPLATE="${SCRIPT_DIR}/anykernel.sh"
OUTPUT_ZIP=""
STAGE_DIR=""

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} OUTPUT_ZIP IMAGE_DIR DEVICE_NAME

IMAGE_DIR must contain:
  Image
  vendor_boot.img
  vendor_dlkm.img
  system_dlkm.img

Example:
  ${SCRIPT_NAME} out/GoRhanHee_Kernel-kalama-dm3q-AnyKernel3.zip \\
    out/msm-kalama-kalama-gki/packaged dm3q
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
    [[ $# -eq 3 ]] || {
        usage >&2
        exit 2
    }

    local output_zip="$1"
    local image_dir="$2"
    local device_name="$3"
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
    [[ "${device_name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
        die "invalid device name: ${device_name}"

    output_dir="$(dirname "${output_zip}")"
    mkdir -p "${output_dir}"
    rm -f -- "${output_zip}"

    STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sm8550-anykernel.XXXXXX")"

    for path in LICENSE META-INF tools; do
        [[ -e "${TEMPLATE_DIR}/${path}" ]] ||
            die "AnyKernel3 template file is missing: ${TEMPLATE_DIR}/${path}"
        cp -a "${TEMPLATE_DIR}/${path}" "${STAGE_DIR}/"
    done

    cp "${SCRIPT_TEMPLATE}" "${STAGE_DIR}/anykernel.sh"
    sed -i "s/@@DEVICE_NAME@@/${device_name}/g" \
        "${STAGE_DIR}/anykernel.sh"
    grep -Fq '@@DEVICE_NAME@@' "${STAGE_DIR}/anykernel.sh" &&
        die "device name placeholder was not fully replaced"

    for image in Image vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        [[ -s "${image_dir}/${image}" ]] ||
            die "required image is missing or empty: ${image_dir}/${image}"
        cp "${image_dir}/${image}" "${STAGE_DIR}/${image}"
        chmod 0644 "${STAGE_DIR}/${image}"
    done

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
            vendor_boot.img \
            vendor_dlkm.img \
            system_dlkm.img
    )

    echo "Created ${output_zip}"
}

main "$@"
