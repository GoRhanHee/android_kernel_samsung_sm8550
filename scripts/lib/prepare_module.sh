#!/usr/bin/env bash

set -Eeuo pipefail

(( $# == 2 )) || { echo "usage: $0 <module> <LLVM bin directory>" >&2; exit 1; }
for tool in tail cmp; do
    command -v "${tool}" >/dev/null || { echo "error: required command not found: ${tool}" >&2; exit 1; }
done

# The appended signature covers the entire ELF, including debug and BTF data.
# Objcopy/strip drop that signature, so copy signed GKI modules unchanged.
if tail -c 28 -- "$1" | cmp -s - <(printf '~Module signature appended~\n'); then
    exit 0
fi

"$2/llvm-objcopy" --remove-section=.BTF --remove-section=.BTF.ext "$1"
"$2/llvm-strip" --strip-debug "$1"
