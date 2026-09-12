#!/usr/bin/env python3
"""Exercise repacking with a real CI ZIP; optionally run its ARM magiskboot via QEMU.

Usage: verify_sm8550_repack.py ARTIFACT.zip --emulator /path/to/qemu-aarch64
Dynamic DLKM writes are mocked; boot/vendor_boot targets are ordinary fixture files.
"""
import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile


SOURCE = Path(__file__).resolve().parent


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            result.update(chunk)
    return result.hexdigest()


def cpio(entries):
    result = bytearray()
    for index, (name, data, mode) in enumerate(entries + [('TRAILER!!!', b'', 0)]):
        name = name.encode() + b'\0'
        fields = [index + 1, mode, 123, 456, 1, 123456789, len(data), 0, 0, 0, 0, len(name), 0]
        result.extend(b'070701' + ''.join(f'{v:08x}' for v in fields).encode() + name)
        result.extend(b'\0' * (-len(result) % 4))
        result.extend(data)
        result.extend(b'\0' * (-len(result) % 4))
    return bytes(result)


def cpio_records(data):
    records, offset = {}, 0
    while offset < len(data):
        assert data[offset:offset + 6] == b'070701'
        fields = [int(data[offset + 6 + i * 8:offset + 14 + i * 8], 16) for i in range(13)]
        start = offset + 110
        name = data[start:start + fields[11] - 1].decode()
        start = (start + fields[11] + 3) & ~3
        if name == 'TRAILER!!!':
            break
        # Compare mode, ownership, link count, timestamp and contents directly
        # in the archive, independently of extraction's host filesystem metadata.
        records[name] = (fields[1:6], data[start:start + fields[6]])
        offset = (start + fields[6] + 3) & ~3
    return records


def run(args, cwd, log, accepted=(0,)):
    result = subprocess.run(args, cwd=cwd, stdout=log, stderr=log)
    assert result.returncode in accepted, f'command failed: {args}; see {log.name}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--emulator', type=Path)
    parser.add_argument('--magiskboot', type=Path, help='Native executable instead of bundled ARM binary')
    parser.add_argument('--quick', action='store_true', help='Keep signed GKI files; substitute small payloads for other modules for emulated format checks')
    parser.add_argument('--case', choices=('v3-unnamed-dm3q', 'v4-unnamed-dm3q', 'v4-platform-dm1q'))
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='sm8550-repack-check.', dir='/var/tmp'))
    print(f'Working directory: {root}', flush=True)
    package = root / 'package'
    package.mkdir()
    with zipfile.ZipFile(args.artifact) as outer:
        if 'anykernel.sh' in outer.namelist():
            archive_data = args.artifact.read_bytes()
        else:
            names = [n for n in outer.namelist() if n.endswith('.zip')]
            assert len(names) == 1
            archive_data = outer.read(names[0])
    with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
        for name in archive.namelist():
            if name.startswith(('vendor_ramdisk/', 'sm8550_ramdisk/')) or name in ('Image', 'anykernel.sh', 'tools/sm8550-repack.sh', 'tools/ak3-core.sh', 'tools/magiskboot'):
                archive.extract(name, package)
    if (package / 'vendor_ramdisk').exists():
        (package / 'vendor_ramdisk').rename(package / 'sm8550_ramdisk')
    # A corrected generated ZIP must be tested using the scripts it ships.
    generated = (package / 'tools/sm8550-repack.sh').is_file()
    installer_source = package / 'anykernel.sh' if generated else SOURCE / 'anykernel.sh'
    repack_source = package / 'tools/sm8550-repack.sh' if generated else SOURCE / 'sm8550-repack.sh'
    modules = package / 'sm8550_ramdisk/ramdisk/lib/modules'
    module_hashes = {p.name: digest(p) for p in modules.glob('*.ko')}
    assert len(module_hashes) == 527, 'Expected the successful 527-module SM8550 artifact'
    if args.quick:
        for path in modules.glob('*.ko'):
            if path.name not in ('zram.ko', 'zsmalloc.ko'):
                path.write_bytes(b'fixture payload ' + path.name.encode())
        module_hashes = {p.name: digest(p) for p in modules.glob('*.ko')}
    binary = (args.magiskboot or package / 'tools/magiskboot').resolve()
    binary.chmod(0o755)
    command = ([str(args.emulator.resolve())] if args.emulator else []) + [str(binary)]
    tools = root / 'tools'
    tools.mkdir()
    wrapper = tools / 'magiskboot'
    wrapper.write_text(r'''#!/bin/sh
if [ "${TEST_FAIL_CPIO_UPDATE:-0}" = 1 ] && [ "$1" = cpio ]; then
    case "$3" in rm\ *) exit 1;; esac
fi
exec ''' + shlex.join(command) + ' "$@"\n')
    wrapper.chmod(0o755)
    for name, text in {
        'getprop': '#!/bin/sh\ncase "$1" in ro.product.device) echo "$TEST_DEVICE";; esac\n',
        'httools_static': '#!/bin/sh\nexit 0\n',
        'lptools_static': '#!/bin/sh\nexit 0\n',
    }.items():
        (tools / name).write_text(text)
        (tools / name).chmod(0o755)
    shutil.copyfile(repack_source, tools / 'sm8550-repack.sh')
    mkbootimg = SOURCE.parent / 'kernel_platform/tools/mkbootimg/mkbootimg.py'
    stock_fstab = (b'# preserve comment\n'
                   b'vendor_dlkm /vendor_dlkm erofs ro wait,logical,first_stage_mount,avb=vbmeta\n'
                   b'system_dlkm /system_dlkm erofs ro wait,logical,avb\n'
                   b'system /system erofs ro wait,avb=vbmeta_system\n')
    platform_entries = [
        ('lib', b'', 0o40755), ('lib/modules', b'', 0o40755),
        ('lib/modules/old.ko', b'old module', 0o100644),
        ('first_stage_ramdisk', b'', 0o40755),
        ('first_stage_ramdisk/fstab.qcom', stock_fstab, 0o100644),
        ('keep.txt', b'stock platform content', 0o100640),
        ('keep-link', b'keep.txt', 0o120777),
    ]
    log = (root / 'verification.log').open('w')
    cases = [(3, '', 'dm3q'), (4, '', 'dm3q'), (4, 'platform', 'dm1q')]
    for version, platform_name, device in cases:
        if args.case and args.case != f'v{version}-{platform_name or "unnamed"}-{device}':
            continue
        case = root / f'v{version}-{platform_name or "unnamed"}-{device}'
        case.mkdir()
        parts = case / 'parts'
        parts.mkdir()
        (case / 'tools').symlink_to(tools)
        (case / 'Image').symlink_to(package / 'Image')
        (case / 'sm8550_ramdisk').symlink_to(package / 'sm8550_ramdisk')
        for name in ('vendor_dlkm_kiwi_v2.img', 'vendor_dlkm_qca6490.img', 'system_dlkm.img'):
            (case / name).write_bytes(b'dummy DLKM image')
        (case / 'stock-kernel').write_bytes(b'stock kernel' * 1024)
        boot_ramdisk = gzip.compress(cpio([('init', b'stock boot init', 0o100750)]), mtime=0)
        (case / 'boot.cpio.gz').write_bytes(boot_ramdisk)
        (case / 'platform.cpio').write_bytes(cpio(platform_entries))
        run([str(wrapper), 'compress=lz4_legacy', 'platform.cpio', 'platform.lz4'], case, log)
        (case / 'recovery.gz').write_bytes(gzip.compress(cpio([('recovery', b'other fragment', 0o100700)]), mtime=0))
        dtb = b'device-specific DTB bytes' * 256
        bootconfig = b'androidboot.hardware = "qcom"\nandroidboot.test = "keep"\n'
        (case / 'dtb').write_bytes(dtb)
        (case / 'bootconfig').write_bytes(bootconfig)
        run([sys.executable, str(mkbootimg), '--header_version', str(version),
             '--kernel', 'stock-kernel', '--ramdisk', 'boot.cpio.gz', '-o', str(parts / 'boot')], case, log)
        vendor_args = [sys.executable, str(mkbootimg), '--header_version', str(version),
                       '--vendor_boot', str(parts / 'vendor_boot'), '--dtb', 'dtb']
        if platform_name:
            vendor_args += ['--ramdisk_type', 'platform', '--ramdisk_name', platform_name,
                            '--board_id0', '7', '--vendor_ramdisk_fragment', 'platform.lz4']
        else:
            vendor_args += ['--vendor_ramdisk', 'platform.lz4']
        if version == 4:
            vendor_args += ['--vendor_bootconfig', 'bootconfig', '--ramdisk_type', 'recovery',
                            '--ramdisk_name', 'recovery', '--board_id0', '9',
                            '--vendor_ramdisk_fragment', 'recovery.gz']
        run(vendor_args, case, log)
        # The shipped package has no replacement DTB; the fixture input must
        # likewise not trigger AK3's automatic multi-partition setup.
        (case / 'dtb').unlink()
        for name, size in [('boot', 64 << 20), ('vendor_boot', 96 << 20)]:
            with (parts / name).open('r+b') as stream:
                stream.truncate(size)
        old_vendor = (parts / 'vendor_boot').read_bytes()
        core = (package / 'tools/ak3-core.sh').read_text().replace('/dev/block/bootdevice/by-name', str(parts))
        core = core.replace('/dev/block/by-name', str(parts))
        (tools / 'ak3-core.sh').write_text(core)
        installer = installer_source.read_text().replace('/dev/block/by-name', str(parts))
        installer = installer.replace('/dev/block/bootdevice/by-name', str(parts))
        installer = installer.replace(f'BLOCK={parts}/boot;', 'BLOCK=boot;')
        installer = installer.replace('. "$BIN/sm8550-repack.sh";',
            '. "$BIN/sm8550-repack.sh";\nflash_generic() { echo "$1" >> "$AKHOME/dlkm-writes"; }')
        (case / 'anykernel.sh').write_text(installer)
        env = os.environ | {'PATH': str(tools) + ':' + os.environ['PATH'],
                           'OUTFD': '1', 'TEST_DEVICE': device}
        # First force insufficient vendor_boot capacity. Boot must remain untouched.
        boot_hash = digest(parts / 'boot')
        with (parts / 'vendor_boot').open('r+b') as stream:
            stream.truncate(len(old_vendor.rstrip(b'\0')) + 4096)
        vendor_hash = digest(parts / 'vendor_boot')
        log.flush()
        failure_start = Path(log.name).stat().st_size
        failed = subprocess.run(['bash', 'anykernel.sh'], cwd=case, env=env, stdout=log, stderr=log)
        assert failed.returncode != 0
        log.flush()
        assert 'exceeds partition capacity' in Path(log.name).read_text()[failure_start:]
        assert digest(parts / 'boot') == boot_hash and digest(parts / 'vendor_boot') == vendor_hash
        assert not (case / 'dlkm-writes').exists()
        (parts / 'vendor_boot').write_bytes(old_vendor)
        for name in ('repack-boot', 'repack-vendor'):
            shutil.rmtree(case / name)
        failed = subprocess.run(['bash', 'anykernel.sh'], cwd=case,
                                env=env | {'TEST_FAIL_CPIO_UPDATE': '1'}, stdout=log, stderr=log)
        assert failed.returncode != 0
        assert digest(parts / 'boot') == boot_hash and (parts / 'vendor_boot').read_bytes() == old_vendor
        assert not (case / 'dlkm-writes').exists()
        for name in ('repack-boot', 'repack-vendor'):
            shutil.rmtree(case / name)
        success = subprocess.run(['bash', 'anykernel.sh'], cwd=case, env=env, stdout=log, stderr=log)
        assert success.returncode == 0, f'see {log.name}'
        assert (case / 'dlkm-writes').read_text().splitlines() == ['vendor_dlkm', 'system_dlkm']
        check = case / 'check'
        check.mkdir()
        run([str(wrapper), 'unpack', '-n', str(parts / 'boot')], check, log)
        assert digest(check / 'kernel') == digest(package / 'Image')
        assert (check / 'ramdisk.cpio').read_bytes() == boot_ramdisk
        run([str(wrapper), 'unpack', '-n', str(parts / 'vendor_boot')], check, log, accepted=(0, 3))
        assert (check / 'dtb').read_bytes() == dtb
        if version == 4:
            assert (check / 'bootconfig').read_bytes() == bootconfig
            assert (check / 'vendor_ramdisk/recovery.cpio').read_bytes() == (case / 'recovery.gz').read_bytes()
            # Table type/name/board IDs survive; only sizes and offsets may change.
            for image in (old_vendor, (parts / 'vendor_boot').read_bytes()):
                page_size = struct.unpack_from('<I', image, 12)[0]
                header_size, ramdisk_size, dtb_size = struct.unpack_from('<I', image, 2096)[0], struct.unpack_from('<I', image, 24)[0], struct.unpack_from('<I', image, 2100)[0]
                table = sum((size + page_size - 1) // page_size for size in (header_size, ramdisk_size, dtb_size)) * page_size
                metadata = [image[table + i * 108 + 8:table + (i + 1) * 108] for i in range(2)]
                if image is old_vendor:
                    original_metadata = metadata
                else:
                    assert metadata == original_metadata
            fragment = check / 'vendor_ramdisk' / f'{platform_name or "ramdisk"}.cpio'
        else:
            fragment = check / 'ramdisk.cpio'
        run([str(wrapper), 'decompress', str(fragment), 'platform.cpio'], check, log)
        original_records = cpio_records(cpio(platform_entries))
        updated_records = cpio_records((check / 'platform.cpio').read_bytes())
        for name in ('lib', 'first_stage_ramdisk', 'keep.txt', 'keep-link'):
            # The bundled magiskboot normalizes updated CPIO timestamps to 0.
            assert updated_records[name][0][:4] == original_records[name][0][:4], name
            assert updated_records[name][0][4] == 0, name
            assert updated_records[name][1] == original_records[name][1], name
        extract = check / 'extract'
        extract.mkdir()
        run([str(wrapper), 'cpio', str(check / 'platform.cpio'), 'extract'], extract, log)
        installed = extract / 'lib/modules'
        assert {p.name: digest(p) for p in installed.glob('*.ko')} == module_hashes
        assert not (installed / 'old.ko').exists()
        assert (extract / 'keep.txt').read_bytes() == b'stock platform content'
        assert (extract / 'keep.txt').stat().st_mode & 0o777 == 0o640
        assert (extract / 'keep-link').readlink() == Path('keep.txt')
        fstab = (extract / 'first_stage_ramdisk/fstab.qcom').read_text()
        assert 'wait,avb=vbmeta_system' in fstab
        assert all('avb' not in line for line in fstab.splitlines() if line.startswith(('vendor_dlkm', 'system_dlkm')))
        inactive = 'qca_cld3_qca6490.ko' if device == 'dm3q' else 'qca_cld3_kiwi_v2.ko'
        for name in ('modules.load', 'modules.load.recovery'):
            assert inactive not in (installed / name).read_text()
        print(f'PASS v{version} {platform_name or "unnamed"} {device}: 527 {"fixture" if args.quick else "actual"} module files, preserved stock content/modes/ownership; size/CPIO failures wrote nothing', flush=True)
    log.close()
    print(f'PASS. Evidence: {root}/verification.log')


if __name__ == '__main__':
    main()
