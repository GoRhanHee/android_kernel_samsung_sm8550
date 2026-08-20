# GoRhanHee Kernel

<p align="center">
  <img src="assets/gorhanhee-kernel-logo.png" alt="GoRhanHee Kernel logo" width="100%">
</p>

## ⚠️ Disclaimer

- Designed for Samsung stock One UI firmware.
- One UI-based custom ROMs may be incompatible; UN1CA has been tested and confirmed working.
- AOSP-based ROMs are not supported.

## 📱 Supported Devices

| Codename | Device | Status |
| --- | --- | --- |
| `dm1q` | Galaxy S23 | ✅ Supported |
| `dm2q` | Galaxy S23+ | ✅ Supported |
| `dm3q` | Galaxy S23 Ultra | ✅ Supported |
| `q5q` | Galaxy Z Fold5 | ✅ Supported |
| `b5q` | Galaxy Z Flip5 | ❌ Not supported |

Global and international variants using the same device codename are supported when firmware and partition layouts match.

The build script contains a `b5q` profile for development, but Galaxy Z Flip5 is currently excluded from supported devices.

## ✨ Features

- KernelSU-Next is integrated for kernel-level root management.
- Baseband Guard monitors unauthorized writes to protected partition devices.
- DroidSpaces support enables Linux containers through namespaces, IPC, netfilter, and matching DLKM modules.
- NTSync provides kernel synchronization primitives for Wine, Winlator, and GameHub.
- BBRv3 with TCP PLB is available for runtime network congestion control.
- FQ, FQ-CoDel, CAKE, PIE, NAT, IP sets, and IPv6 masquerading are enabled for network policy flexibility.
- Memory paths include optimized memset, memcpy, memcmp, page clearing, alignment, and cache-pressure tuning.
- Scheduler paths include CPU scan-order, cache-hot-buddy, and cpufreq minimum-frequency tuning.
- F2FS and ext4 include garbage-collection, congestion, fsync, and journal-commit tuning.
- Power management includes wakelock, alarmtimer, freeze-timeout, s2idle, and PCI PME wakeup tuning.
- Repetitive IRQ, healthd, logd, and dashd kernel messages are reduced.

## 🔨 Build

```sh
git clone https://github.com/GoRhanHee/android_kernel_samsung_sm8550.git
cd android_kernel_samsung_sm8550
git submodule update --init --recursive
```

Supported build targets:

```sh
./build.sh dm1q
./build.sh dm2q
./build.sh dm3q
./build.sh q5q
```


The build flow selects the device profile, applies the common feature patches, merges the custom defconfig, builds the kernel and matching vendor modules, then packages the boot and DLKM images.

## 📦 Output & Fastboot Installation

Typical output:

```text
out/<model>/msm-kalama-kalama-gki/
```

Main artifacts:

```text
boot.img
vendor_boot.img
vendor_dlkm.img
system_dlkm.img
GoRhanHee_Kernel-kalama-<model>-fastboot.zip
```

- Flash only to the matching device and firmware family.
- Keep the four images together; `vendor_dlkm.img` and `system_dlkm.img` are matched to the selected device.
- Keep stock images available for recovery.
- The Flip5 (`b5q`) build is not currently supported.

### Fastboot Installation

Extract the `-fastboot.zip` package and run the script for your computer from the directory containing all four images:

```text
Windows: flash_windows.bat
macOS:   chmod +x flash_macos.sh && ./flash_macos.sh
Linux:   chmod +x flash_linux.sh && ./flash_linux.sh
```

The release ZIP contains exactly the four images and three platform-specific flash scripts listed above. The scripts use `fastboot` from the environment when available; otherwise, they automatically download the official Android platform-tools package for Windows, macOS, or Linux.

The four writes are:

```sh
fastboot flash boot boot.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash system_dlkm system_dlkm.img
```

The bootloader must be unlocked and the device must already be in fastbootd before running a script. These scripts do not enter or switch boot modes. Samsung Download Mode/Odin is not used by this package. Flashing is sequential and has no rollback; do not disconnect the device until the script reboots Android.

## 📚 Credits

- [Android Common Kernel](https://android.googlesource.com/kernel/common/) — Android 13 / Linux 5.15 GKI base.
- [Qualcomm MSM Kernel](https://git.codelinaro.org/clo/la/kernel/msm-5.15) — SM8550 / Kalama platform source.
- [Samsung Open Source Release Center](https://opensource.samsung.com/) — Samsung device kernel source reference.
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — KernelSU-Next root integration.
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) — Protected partition write monitoring.
- [DroidSpaces OSS](https://github.com/ravindu644/Droidspaces-OSS) — Linux container support reference.
- [Google BBR](https://github.com/google/bbr) — BBR congestion-control reference.
- [WildKernels](https://github.com/WildKernels) — Kernel optimization and feature patch reference.
