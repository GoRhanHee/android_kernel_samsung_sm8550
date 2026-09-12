#!/usr/bin/env python3
"""Repackage a reference CI artifact using the real packager and compare ZIP contents."""
import argparse
import hashlib
import io
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    work = Path(tempfile.mkdtemp(prefix='sm8550-ak3-package-check.', dir='/var/tmp'))
    images = work / 'images'
    images.mkdir()
    with zipfile.ZipFile(args.reference) as outer:
        if 'anykernel.sh' in outer.namelist():
            data = args.reference.read_bytes()
        else:
            names = [n for n in outer.namelist() if n.endswith('.zip')]
            assert len(names) == 1
            data = outer.read(names[0])
    with zipfile.ZipFile(io.BytesIO(data)) as reference:
        image_names = ('Image', 'vendor_dlkm_qca6490.img', 'vendor_dlkm_kiwi_v2.img', 'system_dlkm.img')
        for name in reference.namelist():
            if name in image_names or name.startswith('vendor_ramdisk/'):
                reference.extract(name, images)
        output = work / 'AnyKernel3-generated-check.zip'
        subprocess.run(['bash', str(source / 'make_anykernel_package.sh'), str(output), str(images)], check=True)
        with zipfile.ZipFile(output) as generated:
            assert generated.testzip() is None
            entries = generated.namelist()
            assert not any(n.startswith('vendor_ramdisk/') for n in entries)
            assert not any(n in entries for n in ('boot.img', 'vendor_boot.img', 'dtb', 'dtbo.img'))
            for name in image_names:
                assert generated.read(name) == reference.read(name), name
            payload = [n for n in reference.namelist() if n.startswith('vendor_ramdisk/') and not n.endswith('/')]
            assert sum(n.endswith('.ko') for n in payload) == 527
            for name in payload:
                target = name.replace('vendor_ramdisk/', 'sm8550_ramdisk/', 1)
                assert generated.read(target) == reference.read(name), name
            for name, original in [('anykernel.sh', source / 'anykernel.sh'),
                                   ('tools/sm8550-repack.sh', source / 'sm8550-repack.sh'),
                                   ('tools/ak3-core.sh', source / 'AnyKernel3/tools/ak3-core.sh')]:
                assert generated.read(name) == original.read_bytes(), name
                assert generated.getinfo(name).external_attr >> 16 & 0o111, name
            # The recorded revision must use the same gki-2.0 core and binary
            # that CI actually packaged, rather than the old master revision.
            for name in ('tools/ak3-core.sh', 'tools/magiskboot'):
                assert hashlib.sha256(generated.read(name)).digest() == hashlib.sha256(reference.read(name)).digest(), name
    print('PASS: real gki-2.0 packager; installer/helper linked; 527 modules and four assets unchanged; CRC and permissions valid')
    print(output)


if __name__ == '__main__':
    main()
