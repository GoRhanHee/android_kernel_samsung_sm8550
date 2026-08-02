#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATE_DIR="${SCRIPT_DIR}/flashable"
OUTPUT_ZIP=""
STAGE_DIR=""

usage() {
    cat <<EOF
Usage:
  ${SCRIPT_NAME} OUTPUT_ZIP IMAGE_DIR DEVICE_DISPLAY_NAME

IMAGE_DIR must contain:
  boot.img
  vendor_boot.img
  vendor_dlkm.img
  system_dlkm.img

Example:
  ${SCRIPT_NAME} out/dm3q-kernel-flashable.zip out/msm-kalama-kalama-gki/packaged "Galaxy S23 Ultra"
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
    local device_display_name="$3"
    local output_dir
    local output_name
    local stage_dir
    local archive
    local image
    local updater_script

    if [[ "${output_zip}" != /* ]]; then
        output_zip="${PWD}/${output_zip}"
    fi
    if [[ "${image_dir}" != /* ]]; then
        image_dir="${PWD}/${image_dir}"
    fi
    OUTPUT_ZIP="${output_zip}"
    trap cleanup EXIT

    require_command zip

    [[ -d "${TEMPLATE_DIR}/META-INF" ]] ||
        die "flashable template not found: ${TEMPLATE_DIR}"
    [[ -d "${image_dir}" ]] || die "image directory not found: ${image_dir}"
    [[ "${device_display_name}" =~ ^[[:alnum:]][[:alnum:]\ .()+_-]*$ ]] ||
        die "invalid device display name: ${device_display_name}"

    output_dir="$(dirname "${output_zip}")"
    output_name="$(basename "${output_zip}")"
    mkdir -p "${output_dir}"

    STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dm3q-flashable.XXXXXX")"
    stage_dir="${STAGE_DIR}"

    mkdir -p "${stage_dir}/files"
    cp -a "${TEMPLATE_DIR}/META-INF" "${stage_dir}/"
    updater_script="${stage_dir}/META-INF/com/google/android/updater-script"
    grep -Fq '@@DEVICE_DISPLAY_NAME@@' "${updater_script}" ||
        die "device display name placeholder not found in updater-script"
    sed -i \
        "s|@@DEVICE_DISPLAY_NAME@@|${device_display_name}|g" \
        "${updater_script}"
    grep -Fq '@@DEVICE_DISPLAY_NAME@@' "${updater_script}" &&
        die "unreplaced device display name placeholder in updater-script"

    for image in boot.img vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        [[ -s "${image_dir}/${image}" ]] ||
            die "required image is missing or empty: ${image_dir}/${image}"
        cp "${image_dir}/${image}" "${stage_dir}/files/${image}"
        chmod 0644 "${stage_dir}/files/${image}"
    done

    (
        cd "${stage_dir}"
        zip -0 -q -r "${output_name}" META-INF files
    )

    archive="${stage_dir}/${output_name}"
    mv -f "${archive}" "${output_zip}"

    echo "Created ${output_zip}"
}

main "$@"
