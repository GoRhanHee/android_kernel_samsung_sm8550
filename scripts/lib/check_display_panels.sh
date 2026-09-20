#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )); then
    echo 'usage: check_display_panels.sh <msm_drm.ko> <llvm-nm>' >&2
    exit 2
fi
module="$1"
llvm_nm="$2"
[[ -s "$module" ]] || { echo "error: display module missing: $module" >&2; exit 1; }
[[ -x "$llvm_nm" ]] || { echo "error: llvm-nm missing: $llvm_nm" >&2; exit 1; }

# A universal module can link successfully without any product panel code.
# Check the actual ELF before packaging, including older bootloader panel names.
required=(
    DM1_S6E3FAC_AMB606AW01_FHD_init
    DM1_LX83118_CM002_FHD_init
    DM2_S6E3FAC_AMB655AY01_FHD_init
    DM3_S6E3HAE_AMB681AZ01_WQHD_init
    B5_S6E3FC5_AMB338EH01_SVGA_init
    B5_S6E3FAC_AMF670BS03_FHD_init
    Q5_S6E3XA2_AMF756BQ03_QXGA_init
    Q5_S6E3XA2_AMF756EJ01_QXGA_init
    Q5_S6E3FAC_AMB619EK01_FHD_init
    S6E3FAC_AMB606AW01_FHD_init
    S6E3FAC_AMB655AY01_FHD_init
    S6E3HAE_AMB681AZ01_WQHD_init
    PBA_BOOTING_FHD_DSI1_init
)
symbols="$("$llvm_nm" --defined-only --format=posix "$module" | awk '$2 ~ /^[Tt]$/ {print $1}')"
missing=0
for symbol in "${required[@]}"; do
    if ! grep -Fxq "$symbol" <<< "$symbols"; then
        echo "error: universal display module lacks panel initialization: $symbol" >&2
        missing=1
    fi
done
(( missing == 0 )) || exit 1
echo "[display] All ${#required[@]} required panel initializers are present in $module"
