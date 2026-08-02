#!/usr/bin/env sh

set -u

tool="${0##*/}"

log_event() {
    if [ -n "${SM8550_FLASH_TEST_EVENT_LOG-}" ]; then
        printf '%s\n' "$1" >> "${SM8550_FLASH_TEST_EVENT_LOG}"
    fi
}

case "${tool}" in
    dd)
        write=0
        block_size=4096
        block_count=0
        for argument in "$@"; do
            case "${argument}" in
                of=*) write=1 ;;
                bs=*) block_size="${argument#bs=}" ;;
                count=*) block_count="${argument#count=}" ;;
            esac
        done

        if [ "${write}" -eq 1 ]; then
            log_event 'dd-write'
            if [ "${SM8550_FLASH_TEST_DD_MODE-}" = 'write-fail' ]; then
                exit 1
            fi
        else
            log_event 'dd-readback'
            if [ "${SM8550_FLASH_TEST_DD_MODE-}" = 'readback-mismatch' ]; then
                exec "${SM8550_FLASH_TEST_REAL_DD}" \
                    if=/dev/zero bs="${block_size}" count="${block_count}" status=none
            fi
        fi

        exec "${SM8550_FLASH_TEST_REAL_DD}" "$@"
        ;;
    sync)
        log_event 'sync'
        [ "${SM8550_FLASH_TEST_SYNC_FAIL-0}" != '1' ] || exit 1
        exit 0
        ;;
    umount)
        log_event "umount:$1"
        [ "${SM8550_FLASH_TEST_UMOUNT_FAIL-0}" != '1' ] || exit 1
        exit 0
        ;;
    *)
        printf 'unsupported mock tool name: %s\n' "${tool}" >&2
        exit 127
        ;;
esac
