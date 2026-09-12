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
| `b5q` | Galaxy Z Flip5 | ✅ Supported |

Korean and European variants use the same universal kernel. Device-specific
DTB/DTBO outputs remain separated so overlapping Qualcomm board IDs are never
combined into one ambiguous image.

## ✨ Features

- The `vanilla` build mode does not include KernelSU-Next or SUSFS.
- The `susfs` build mode adds KernelSU-Next and SUSFS 2.2.0 for Android 13 / Linux 5.15.
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

The source is compiled once per kernel mode:

```sh
./build.sh vanilla
./build.sh ksun
./build.sh susfs
```

Before fetching submodules or compiling, `build.sh` checks that the EROFS
tools can create and verify both DLKM images. If the tools are missing or
incompatible, it builds pinned erofs-utils 1.8.10 in `.cache/erofs-utils`,
adds its `bin` directory to the build's PATH, and checks it again. Later
builds reuse this installation. Local builds and GitHub Actions use the
same setup; no manual EROFS installation or PATH export is needed.
Building these tools requires `autoconf`, `automake`, `libtool`,
`pkg-config`, a C compiler and make, plus LZ4, SELinux and UUID development
libraries (`liblz4-dev`, `libselinux1-dev`, and `uuid-dev` on Ubuntu/Debian).

The argument selects the kernel mode and defaults to `vanilla` when omitted. `vanilla` keeps the common project feature patches but excludes KernelSU-Next/SUSFS. `ksun` adds the pinned KernelSU-Next revision without SUSFS. `susfs` also applies the two patches under `patches/susfs/` and merges `custom_defconfigs/ksu_defconfig` followed by `custom_defconfigs/susfs_defconfig`. All temporary source patches are reverted when the build exits.

The universal config builds the union of device drivers and the enabled product DTS targets. The build creates `vendor_dlkm` and `system_dlkm` directly from the newly built modules; it does not download or repack stock DLKM images.

Packaging uses the common GKI build's `kernel.release`, recorded in `dist`,
for module directories instead of reading one module's vermagic. Its system
modules are restored after the mixed build to replace same-name device modules.
Signed modules are copied unchanged so their signatures remain valid; only
unsigned modules have debug and BTF sections removed.

The MSM option `CONFIG_SM8550_DTBO` defaults to `n`. Set
`CONFIG_SM8550_DTBO=y` in
`kernel_platform/msm-kernel/arch/arm64/configs/vendor/universal_project.config`
to build DTBOs and the product DTBs that depend on them. Qualcomm base DTBs
remain available when the option is disabled. The separate `dm3q_eur_openx`
DTS sources are retained but excluded from the build.

## 📦 Output & AnyKernel3 Installation

Typical output:

```text
out/universal/msm-kalama-kalama-gki-<mode>/
```

Main artifacts:

```text
Image
vendor_ramdisk/
vendor_dlkm_qca6490.img
vendor_dlkm_kiwi_v2.img
system_dlkm.img
GoRhanHee_Kernel-kalama-universal-<mode>-AnyKernel3.zip
```

`dist/device-trees/base` contains the common Qualcomm base DTBs. Each product
profile below `dist/device-trees/` has separate `dtb` and `dtbo` directories.
The two vendor DLKM images differ only in the mutually exclusive WLAN driver;
AnyKernel3 chooses the correct one at install time.

- Keep stock images available for recovery.

### AnyKernel3 Installation

The `-AnyKernel3.zip` package uses the configured `gki-2.0` tools. Its separate `sm8550_ramdisk/` payload avoids the core's automatic multi-partition relocation. The installer prepares the common `Image` in the stock boot image, then uses `magiskboot unpack -n` on the device's existing `vendor_boot`. It updates module entries and DLKM AVB fstab flags in the CPIO fragment containing `first_stage_ramdisk/fstab.qcom`; other fragments retain their original compressed bytes. `magiskboot repack` retains the stock DTB, bootconfig and v4 table metadata while updating fragment sizes and offsets. Both prepared physical images must fit before flashing begins. The installer also selects the matching WLAN `vendor_dlkm` and common `system_dlkm`.

The bootloader must be unlocked, and the device must use a recovery/flasher that supports AnyKernel3 update ZIPs. Samsung Download Mode/Odin is not used by this package. Keep a stock backup available because flashing is sequential and has no rollback.

## 📚 Credits

- [Android Common Kernel](https://android.googlesource.com/kernel/common/) — Android 13 / Linux 5.15 GKI base.
- [Qualcomm MSM Kernel](https://git.codelinaro.org/clo/la/kernel/msm-5.15) — SM8550 / Kalama platform source.
- [Samsung Open Source Release Center](https://opensource.samsung.com/) — Samsung device kernel source reference.
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — KernelSU-Next root integration.
- [SUSFS for KernelSU](https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android13-5.15) — Android 13 / Linux 5.15 kernel integration reference.
- [KernelSU-Next SUSFS reference patch](https://github.com/xfwdrev/android_kernel_samsung_b4q/blob/sixteen/patches/0001-Enable-SuSFS-2.2.0-KSU-Next.patch) — KernelSU-Next-side SUSFS 2.2.0 integration reference.
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — flashable kernel ZIP framework.
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) — Protected partition write monitoring.
- [DroidSpaces OSS](https://github.com/ravindu644/Droidspaces-OSS) — Linux container support reference.
- [Google BBR](https://github.com/google/bbr) — BBR congestion-control reference.
- [WildKernels](https://github.com/WildKernels) — Kernel optimization and feature patch reference.
