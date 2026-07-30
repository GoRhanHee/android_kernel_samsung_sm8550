# SM8550 recovery-flashable kernel package

This template is shared by the dm3q and q5q builds. It installs the three
images required by either device:

- `boot.img`
- `vendor_boot.img`
- `vendor_dlkm.img`

Build a ZIP directly from a device's packaged image directory:

```bash
./prebuilts/make_flashable_zip.sh \
    out/dm3q/msm-kalama-kalama-gki/packaged/dm3q-kernel-recovery-flashable.zip \
    out/dm3q/msm-kalama-kalama-gki/packaged

./prebuilts/make_flashable_zip.sh \
    out/q5q/msm-kalama-kalama-gki/packaged/q5q-kernel-recovery-flashable.zip \
    out/q5q/msm-kalama-kalama-gki/packaged
```

`./build.sh dm3q full` and `./build.sh q5q full` call the same packager
automatically. Each writes `${device}-kernel-recovery-flashable.zip` next to
that device's packaged images.

The recovery ZIP contains only `boot.img`, `vendor_boot.img`, and
`vendor_dlkm.img`. The build keeps `dtbo.img` in the target-specific `dist`
directory for separate collection; it is not added to the recovery ZIP.

The installer uses the same ARM64 Edify `update-binary` layout as the q5q
package. On Samsung non-A/B devices it resolves existing block devices for
`vendor_dlkm`, `vendor_boot`, and `boot`, rejects non-block targets, writes
each image with `dd`, and verifies the exact written range with SHA-256.
`boot` is written last so a `vendor_dlkm` or `vendor_boot` failure cannot
silently leave only the kernel updated.

Before flashing, keep a matching stock/custom set of `boot`, `vendor_boot`,
and `vendor_dlkm` images available. Flashing a mismatched or corrupt image can
prevent Android from booting.
