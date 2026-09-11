#!/usr/bin/env bash

set -Eeuo pipefail

readonly BUILD_SYSTEM_DLKM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${SCRIPT_DIR:?SCRIPT_DIR is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${OUT_DIR:?OUT_DIR is required}"
: "${OUTPUT_IMAGE:?OUTPUT_IMAGE is required}"

exec "${BUILD_SYSTEM_DLKM_DIR}/build_dlkm.sh" system_dlkm
