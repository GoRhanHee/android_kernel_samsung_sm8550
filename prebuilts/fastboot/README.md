# SM8550 fastbootd release package

Each device release is one ZIP containing exactly seven top-level files:

- `boot.img`
- `vendor_boot.img`
- `vendor_dlkm.img`
- `system_dlkm.img`
- `flash_windows.bat`
- `flash_macos.sh`
- `flash_linux.sh`

The flash scripts require the device to already be in fastbootd. They do not
enter or switch fastboot modes. The Windows script verifies that exactly one
device is connected and that it reports is-userspace: yes; the Linux and
macOS scripts assume fastbootd and ask for confirmation before flashing. All
scripts flash the four images and offer to reboot Android when the writes
succeed.

To package an existing image directory manually:

```bash
./prebuilts/make_fastboot_package.sh \
  out/dm3q/msm-kalama-kalama-gki/packaged/GoRhanHee_Kernel-kalama-dm3q-fastboot.zip \
  out/dm3q/msm-kalama-kalama-gki/packaged
```

The image directory must contain non-empty `boot.img`, `vendor_boot.img`,
`vendor_dlkm.img`, and `system_dlkm.img`.
