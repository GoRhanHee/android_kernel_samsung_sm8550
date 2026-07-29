#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${REPO_ROOT}/kernel_platform/msm-kernel/drivers/i2c/busses/i2c-msm-geni.c"

[[ -f "${SOURCE}" ]] || {
    echo "GENI I2C source not found: ${SOURCE}" >&2
    exit 1
}

for expected in \
    '{KHz(100), 7, 10, 11, 26},' \
    '{KHz(400), 2,  7, 10, 24},' \
    '{KHz(1000), 1, 3,  9, 18},'
do
    grep -Fq "${expected}" "${SOURCE}" || {
        echo "Samsung GENI I2C timing is missing: ${expected}" >&2
        exit 1
    }
done

echo "Samsung GENI I2C timing test passed"
