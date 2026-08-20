# SM8550 fastbootd release package

Each device release is one ZIP containing exactly seven top-level files:

- `boot.img`
- `vendor_boot.img`
- `vendor_dlkm.img`
- `system_dlkm.img`
- `flash_windows.bat`
- `flash_macos.sh`
- `flash_linux.sh`

The flash scripts assume the device is already in fastbootd. They do not enter,
probe, or switch fastboot modes; they only flash the four images and reboot
Android when all writes succeed.

To package an existing image directory manually:

```bash
./prebuilts/make_fastboot_package.sh \
  out/dm3q/msm-kalama-kalama-gki/packaged/GoRhanHee_Kernel-kalama-dm3q-fastboot.zip \
  out/dm3q/msm-kalama-kalama-gki/packaged
```

The image directory must contain non-empty `boot.img`, `vendor_boot.img`,
`vendor_dlkm.img`, and `system_dlkm.img`.
