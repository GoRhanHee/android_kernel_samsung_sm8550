# SM8550 recovery-flashable kernel package

This template is shared by the dm1q, dm2q, dm3q, and q5q builds. It installs
the four images required by each device:

- `boot.img`
- `vendor_boot.img`
- `vendor_dlkm.img`
- `system_dlkm.img`

Run a full build for the selected device. Each command uses that device's
isolated output and stock-image inputs:

```bash
./build.sh dm1q full  # Galaxy S23 (SM-S911N)
./build.sh dm2q full  # Galaxy S23+ (SM-S916N)
./build.sh dm3q full  # Galaxy S23 Ultra (SM-S918N)
./build.sh q5q full   # Galaxy Z Fold5 (SM-F946N)
```

To build a ZIP directly from a device's packaged image directory:

```bash
./prebuilts/make_flashable_zip.sh \
    out/dm1q/msm-kalama-kalama-gki/packaged/dm1q-kernel-recovery-flashable.zip \
    out/dm1q/msm-kalama-kalama-gki/packaged \
    "Galaxy S23"

./prebuilts/make_flashable_zip.sh \
    out/dm2q/msm-kalama-kalama-gki/packaged/dm2q-kernel-recovery-flashable.zip \
    out/dm2q/msm-kalama-kalama-gki/packaged \
    "Galaxy S23+"

./prebuilts/make_flashable_zip.sh \
    out/dm3q/msm-kalama-kalama-gki/packaged/dm3q-kernel-recovery-flashable.zip \
    out/dm3q/msm-kalama-kalama-gki/packaged \
    "Galaxy S23 Ultra"

./prebuilts/make_flashable_zip.sh \
    out/q5q/msm-kalama-kalama-gki/packaged/q5q-kernel-recovery-flashable.zip \
    out/q5q/msm-kalama-kalama-gki/packaged \
    "Galaxy Z Fold5"
```

The full-build commands call the same packager automatically. Each writes
`${device}-kernel-recovery-flashable.zip` next to that device's packaged
images under `out/${device}/msm-kalama-kalama-gki/packaged/`.

The ZIP contains only those four image files under `files/`, plus the required
`META-INF` installer files. It does not include `dtbo.img`, module lists,
staging archives, checksums, or other side metadata, even when those files are
present beside the packaged images.

Both `vendor_dlkm.img` and `system_dlkm.img` are matched to the selected
device's downloaded stock image's exact stat size, not a shared hardcoded
limit. Repacking requires positive, 4096-byte-aligned stock and rebuilt images;
a smaller rebuilt image is zero-padded to that exact stock size, equality is a
no-op, and oversize or invalid input is rejected before mutation. The final
validator requires `used == max` and also checks raw EROFS integrity, UUID
preservation, required SELinux xattrs, and the AVB-tail policy. Both flashed
DLKM images must therefore match their target stock partition capacities.

`system_dlkm.img` is handled as a raw EROFS image. It is not
sparse-converted, and its stock AVB hashtree footer/tail is not copied into the
rebuilt image; only zero-padding to the exact stock capacity is allowed. It is
written as a raw image to `/dev/block/mapper/system_dlkm`.

A downloaded stock DLKM image may contain AVB footer/signature bytes in its
tail. Padding never copies those stock bytes: the raw rebuilt images are paired
with the rebuilt `vendor_boot`, whose `vendor_dlkm` and `system_dlkm` fstab
entries have had their AVB flags removed.

Wireless routing is device-specific: dm1q, dm2q, and q5q use the QCA6490
profile; dm3q uses Kiwi V2.

For local pre-push validation, run the static shell, YAML, profile, Kconfig,
DTS, and packaging checks first. Run a targeted `./build.sh dm1q full` or
`./build.sh dm2q full` only when the remaining question requires build-produced
evidence (such as emitted DTBs, compiled WLAN/module routing, or a repacked
`vendor_dlkm.img`). The CI workflow intentionally performs a full build for
every matrix device; this static-first policy applies to local validation.

The build keeps `dtbo.img` and system module side artifacts in the
target-specific `dist` directory for separate collection; they are not added
to the recovery ZIP.

The installer uses the same ARM64 Edify `update-binary` layout as the q5q
package. On Samsung non-A/B devices it resolves the existing block devices for
`system_dlkm`, `vendor_dlkm`, `vendor_boot`, and `boot`, rejects non-block
targets, writes each image with `dd`, and verifies the exact written range with
SHA-256. The flash order is `system_dlkm`, `vendor_dlkm`, `vendor_boot`, then
`boot`; `boot` is written last. Flashing is sequential and has no rollback:
if a later write fails, earlier successful writes remain in place.

Before flashing, keep a matching stock/custom set of `boot`, `vendor_boot`,
`vendor_dlkm`, and `system_dlkm` images available. Flashing a mismatched or
corrupt image can prevent Android from booting.
