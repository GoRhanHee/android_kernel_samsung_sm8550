# ⚡ GoRhanHee Kernel

<p align="center">
  <strong>Android 13 · Linux 5.15 GKI · Qualcomm Snapdragon 8 Gen 2 · SM8550</strong>
</p>

<p align="center">
  A feature-rich Samsung Qualcomm kernel focused on root compatibility, container support, networking, storage responsiveness, and practical day-to-day performance.
</p>

> **Project status:** Experimental and actively maintained. The primary development target is Samsung's SM8550 device family, with `dm3q` / Galaxy S23 Ultra as the main reference device.

## ⚠️ Disclaimer

This kernel is provided for testing, development, and educational purposes. Compatibility is not guaranteed. It may not work on AOSP-based ROMs or on some One UI-based custom ROMs; it is primarily intended for compatible Samsung stock or stock-based firmware with matching vendor modules and partition layouts.

Always keep a complete backup of the original boot, vendor boot, vendor DLKM, and system DLKM images. Verify the device codename, model, firmware generation, and bootloader state before flashing. You are responsible for every result of using this software.

## 📱 Supported Build Profiles

The top-level build script currently contains profiles for the following SM8550-family Samsung targets:

| Codename | Device |
| --- | --- |
| `dm1q` | Galaxy S23 |
| `dm2q` | Galaxy S23+ |
| `dm3q` | Galaxy S23 Ultra |
| `q5q` | Galaxy Z Fold5 |
| `b5q` | Galaxy Z Flip5 |

The `dm3q` / `SM-S918N` profile is the primary development and testing reference for this repository. The kernel is intended to work on global SM8550 variants as well; it is not limited to Korean models or carriers. Always use the matching regional firmware, vendor modules, and partition images for the device being flashed.

## ✨ Feature Summary

### 🔐 Root, Security, and Custom-Kernel Compatibility

#### KernelSU-Next

The build pipeline integrates the official KernelSU-Next setup flow when a checked-in integration is not already present:

- Downloads the official KernelSU-Next setup script from the `next` branch.
- Imports the development integration into the common kernel for the build.
- Verifies that the setup only changes the expected KernelSU registration files.
- Restores the common tree after the build and packaging steps finish.

This keeps the source checkout reproducible while still producing a kernel with KernelSU-Next support. The appropriate KernelSU-Next manager and userspace configuration are still required after flashing.

#### Baseband Guard (BBG)

Baseband Guard is integrated as a lightweight Linux Security Module (LSM). Its purpose is to reduce the chance that an unauthorized process can write to sensitive partition devices or perform destructive operations against protected storage.

The current configuration enables:

- `CONFIG_BBG=y`
- `baseband_guard` in the `CONFIG_LSM` list
- Protection hooks for protected partition writes
- Protection for destructive block-device ioctls
- Protection for unauthorized attribute changes
- Compatibility hooks for process credential and execution paths

The boot and recovery blocking options are intentionally disabled:

```text
CONFIG_BBG_BLOCK_BOOT=n
CONFIG_BBG_BLOCK_RECOVERY=n
```

That choice is important for this project. It keeps normal recovery, boot-image, and DLKM flashing workflows from being blocked by BBG. BBG is therefore a protection layer for unauthorized runtime writes, not a replacement for a verified backup or a guarantee that every partition operation is safe.

#### Samsung Anti-Root Protections

The custom defconfig disables several Samsung-specific anti-root or integrity layers so that a custom kernel can work with KernelSU-Next and other development workflows:

- `CONFIG_UH=n`
- `CONFIG_RKP=n`
- `CONFIG_KDP=n`
- `CONFIG_SECURITY_DEFEX=n`
- `CONFIG_PROCA=n`
- `CONFIG_FIVE=n`

This improves custom-kernel compatibility, but it also means that stock Samsung hardening is not preserved in the same form. Do not interpret these changes as security enhancements.

### 🐳 DroidSpaces and Linux Container Support

The kernel includes the configuration needed by [DroidSpaces](https://github.com/ravindu644/Droidspaces-OSS), a userspace container environment for running Linux distributions and services on Android.

The custom defconfig enables or prepares:

- System V IPC and POSIX message queues
- IPC, PID, and user namespaces
- `devtmpfs` for device-node management
- User namespaces for rootless or isolated container workflows
- Extended attributes and POSIX ACLs on tmpfs
- Netfilter address-type matching
- IP set support for firewall and fail2ban-style rules
- IPv6 NAT and masquerading
- TTL and IPv6 hop-limit targets
- USB Audio Class 1 gadget compatibility
- A deliberately expanded GKI symbol surface for matching kernel and module builds

The build also sets:

```text
TRIM_NONLISTED_KMI=0
KMI_SYMBOL_LIST_STRICT_MODE=0
```

These settings intentionally relax the normal baseline KMI comparison because this fork changes the GKI ABI for full DroidSpaces and matching vendor-module support. The kernel and its matching modules must be treated as one build output.

### 🪟 NTSync for Wine, Winlator, and GameHub

NTSync provides kernel-backed emulation of Windows NT synchronization primitives. The driver implements synchronization objects such as:

- Semaphores
- Mutexes
- Manual and auto-reset events
- Wait queues for `wait-any` and `wait-all` behavior

It is enabled with `CONFIG_NTSYNC=y` and is intended to reduce synchronization overhead for Wine-based workloads such as Winlator and GameHub. NTSync is not a hardware driver; it is a kernel interface used by compatible userspace runtimes.

### 🌐 Network Stack

#### TCP BBRv3

BBRv3 is backported to the Android 13 / 5.15 common kernel with Android KABI compatibility. It adds a congestion-control algorithm that estimates bottleneck bandwidth and round-trip time instead of relying only on packet loss.

The tree provides:

- `CONFIG_TCP_CONG_BBR3=y`
- BBRv3 congestion-control logic
- TCP Probe Loss Balance (PLB) support from the backport
- Kernel configuration and runtime selection support

BBRv3 is **available**, but this project does not force it as the global runtime default. The active congestion controller remains a userspace / sysctl policy decision. When supported by the running kernel, it can be selected with:

```sh
su -c 'cat /proc/sys/net/ipv4/tcp_allowed_congestion_control'
su -c 'echo bbr3 > /proc/sys/net/ipv4/tcp_congestion_control'
```

Actual networking results depend on the modem, Wi-Fi chipset, carrier, access point, queueing discipline, and network path. BBRv3 is not a promise of a faster internet connection in every environment.

#### Queueing Disciplines and Firewall Features

The custom defconfig enables a broad set of networking components:

- FQ, FQ-CoDel, CAKE, PIE, and FQ-PIE queueing disciplines
- IPv4 and IPv6 NAT support
- IPv6 masquerading
- IP set bitmap, hash, and list-set variants
- Netfilter address-type, recent, logging, reject, and set matches/targets
- IPv4 TTL and IPv6 hop-limit targets and matches
- Larger socket memory packet accounting (`_SK_MEM_PACKETS` from 256 to 1024)

These options improve flexibility for tethering, VPNs, containers, firewall rules, fail2ban, and traffic shaping. They do not automatically select CAKE or BBRv3; userspace policy still controls the active algorithm and scheduler.

### ⚡ Memory and CPU-Side Optimizations

The common patch queue contains focused low-level changes rather than a single generic “performance mode.” The intended benefits are lower overhead on hot paths, better cache behavior, and less wasted work:

- **Optimized memory operations:** faster generic `memset()` behavior using aligned wider stores where safe.
- **ARM64 memory prefetch:** prefetches cache lines for copy operations to reduce stalls in `memcpy()` and `memmove()` paths.
- **ARM64 `memcmp()` implementation:** updates the SM8550-facing assembly implementation from optimized ARM routines.
- **Aligned `clear_page()`:** aligns the page-clearing loop to 16 bytes to reduce instruction-fetch and loop overhead.
- **8-byte `struct file` alignment:** improves alignment for a frequently used VFS object and can reduce unaligned access or cacheline inefficiency.
- **Faster integer square root:** reduces the cost of integer square-root calculations used by kernel code such as frequency and scheduler-related paths.
- **Lower VFS cache pressure:** changes the default `vfs_cache_pressure` from 100 to 50, allowing more dentries and inodes to remain cached when memory pressure permits.
- **CPU scan-order adjustment:** avoids immediately repeating a CPU that has already been examined during idle-capacity and NUMA-related scans.
- **Disabled `CACHE_HOT_BUDDY`:** allows the scheduler to make better use of the DynamIQ Shared Unit when migrating work between cores that share higher-level cache.

These are workload-dependent optimizations. They can improve responsiveness or reduce overhead in some workloads, but they are not a guaranteed Geekbench score increase and should not be described as a universal performance or battery-life win.

#### CPU Minimum-Frequency Limit Interface

The custom cpufreq patch adds a per-policy `scaling_min_freq_limit` interface. Its behavior is deliberately a limit, not a forced performance floor:

```text
effective_minimum = min(scaling_min_freq, scaling_min_freq_limit)
```

This allows a userspace power policy to cap an accidentally high minimum frequency so the CPU can idle at lower frequencies. It does not raise the minimum frequency, increase the maximum frequency, or create a performance boost by itself.

### 💾 Storage and Filesystem Tuning

#### F2FS

The F2FS-related patches target latency and background maintenance:

- Urgent GC thread sleep reduced from 500 ms to 50 ms.
- Congestion wait timeout reduced from 20 ms to 6 ms.
- Minimum fsync blocks increased from 8 to 20.

The goal is to reduce avoidable stalls on flash storage and make background garbage collection react sooner. The best values still depend on storage health, free space, encryption, workload, and the vendor's F2FS userspace behavior.

#### ext4

The default JBD2 commit age is increased from 5 seconds to 30 seconds. This can batch journal commits and reduce write activity, but it also increases the amount of recent data that could be lost after an unexpected power failure. It is a performance / write-amplification trade-off, not a free improvement.

### 🔋 Power, Suspend, and Wakeup Behavior

The power-management patch group reduces unnecessary wakeups and stuck wait behavior:

- **Global wakelock cap:** indefinite wakelocks use a 500 ms wakeup event instead of staying awake forever.
- **Alarmtimer wake duration:** suspend abort wakeups use the actual nearest-alarm duration plus one millisecond instead of a hardcoded two-second event.
- **Freeze timeout:** process-freeze timeout is reduced from 20 seconds to 1 second, and Android userspace cannot overwrite the patched value.
- **s2idle wakeups:** repeated wake attempts are collapsed so only the first pending suspend abort performs the wake operation.
- **PCI PME polling:** the PME check interval is increased from 1 second to 4 seconds to reduce needless wakeups.

These changes target stuck wakelocks, deadlock-like freeze waits, and repeated suspend activity. Aggressive timeout changes can expose bugs in software that incorrectly relies on indefinite wake or unusually long suspend transitions, so testing with audio, Bluetooth, USB, tethering, and accessories is recommended.

### 🧹 Kernel Log Noise Reduction

Two small logging patches reduce repetitive messages without changing the underlying operation:

- IRQ affinity failures are downgraded from rate-limited warnings to debug messages.
- Repetitive `healthd`, `logd`, and `dashd` messages are filtered from the kernel printk path.

This keeps debugging output easier to read during charging, app startup, and CPU hotplug activity. It can also hide messages that would otherwise be useful during diagnosis, so reproduce a problem with the unfiltered stock kernel when comparing logs.

## 🧰 Build Information

| Item | Configuration |
| --- | --- |
| Kernel base | Android 13 Common Kernel, Linux 5.15 GKI |
| Platform | Qualcomm SM8550 / Kalama |
| Architecture | ARM64 (`aarch64`) |
| Compiler | Android Clang 22.0.2, revision `r596125` |
| Linker | LLD 22.0.2 from the same Android LLVM toolchain |
| LTO | ThinLTO by default (`LTO=thin`) |

The build uses Android Clang 22.0.2 and LLD 22.0.2 from the Android LLVM toolchain. See the official [AOSP Android LLVM toolchain](https://android.googlesource.com/toolchain/llvm-project/) for the upstream toolchain source.

## 🔨 Building

Initialize the repository and its submodules first:

```sh
git clone https://github.com/GoRhanHee/android_kernel_samsung_sm8550.git
cd android_kernel_samsung_sm8550
git submodule update --init --recursive
```

Build a target with the top-level script:

```sh
./build.sh dm3q full
```

Other supported targets are:

```sh
./build.sh dm1q full
./build.sh dm2q full
./build.sh q5q full
./build.sh b5q full
```

Useful build overrides:

```sh
JOBS=16 LTO=thin ./build.sh dm3q full
TOOLCHAIN_VERSION=r596125 ./build.sh dm3q full
BUILD_SH_PROFILE_ONLY=1 ./build.sh dm3q full
```

The build sequence performs the following high-level operations:

1. Selects the device profile and output paths.
2. Validates that the common and MSM submodules are initialized and clean.
3. Imports KernelSU-Next temporarily when needed.
4. Applies and checks the common feature patch queue.
5. Builds with the Android Clang 22 toolchain and ThinLTO.
6. Builds the matching vendor modules and device images.
7. Packages the resulting boot and DLKM images.
8. Reverses temporary KernelSU and common patch changes before exiting.

No kernel build is performed by editing this README. The commands above are the source-of-truth build entry points.

## 📦 Output and Flashing

For `dm3q`, build output is placed below the target-specific output tree, normally under:

```text
out/dm3q/msm-kalama-kalama-gki/
```

The packaging flow produces kernel and module artifacts such as:

- `boot.img`
- `vendor_boot.img`
- `vendor_dlkm.img`
- `system_dlkm.img`
- `<model>-kernel-recovery-flashable.zip`

Use the generated flashable package only on its matching target and firmware family. Keep stock images nearby so you can recover through the appropriate Samsung flashing or recovery workflow.

## ⚖️ Trade-offs and Expectations

- Optimization patches are targeted changes, not benchmark guarantees.
- Battery life, UI latency, storage throughput, and network performance can move in different directions depending on workload.
- BBRv3 and CAKE are available but are not automatically forced as the active runtime policies.
- Ext4's 30-second commit age reduces write frequency at the cost of a larger sudden-power-loss window.
- Lower freeze, wakelock, and F2FS timeouts can expose badly behaved vendor software.
- BBG boot/recovery blocking is disabled to preserve flashing compatibility.
- The custom GKI ABI settings mean kernel modules must come from the matching build.
- Custom kernels reduce the safety margin provided by stock Samsung integrity features. Keep recovery images and backups before testing.

## 📚 Credits and Sources

The project is built from and inspired by the following work. Individual patch files retain their own upstream attribution where available.

### Core kernel sources

- [Android Common Kernel — `android13-5.15`](https://android.googlesource.com/kernel/common/+/refs/heads/android13-5.15) — original Android Common Kernel baseline.
- [CodeLinaro Qualcomm MSM 5.15](https://git.codelinaro.org/clo/la/kernel/msm-5.15) — original Qualcomm platform source.
- [CodeLinaro `KERNEL.PLATFORM.2.0.r1-23200-kernel.0` tag](https://git.codelinaro.org/clo/la/kernel/msm-5.15/-/tree/KERNEL.PLATFORM.2.0.r1-23200-kernel.0?ref_type=tags) — Qualcomm kernel-platform reference tag.
- [Samsung Open Source Release Center](https://opensource.samsung.com/uploadSearch?searchValue=SM-S918N) — Samsung's official SM-S918N source-release search.

### Feature and compatibility sources

- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — KernelSU-Next integration and setup flow.
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) — BBG implementation and security concept.
- [DroidSpaces OSS](https://github.com/ravindu644/Droidspaces-OSS) — container-oriented kernel configuration guidance and userspace integration target.
- [LineageOS SM8550 kernel source](https://github.com/LineageOS/android_kernel_qcom_sm8550) — SM8550 community kernel reference.
- [Google BBR](https://github.com/google/bbr) — BBR family reference and congestion-control background.
- [WildKernels `Samsung_KernelSU_SUSFS`](https://github.com/WildKernels/Samsung_KernelSU_SUSFS) — reference for the imported optimization and kernel-feature patch set.
- [WildKernels common kernel patches](https://github.com/WildKernels/kernel_patches/tree/main/common) — patch provenance and related common-kernel tuning work.

### Toolchain

- [Android LLVM Toolchain (AOSP)](https://android.googlesource.com/toolchain/llvm-project/) — Android Clang 22.0.2 / LLD 22.0.2 toolchain source.

## 📄 License

Unless a file states otherwise, the applicable license is the license of the original kernel source or patch. Always review the individual license and copyright headers before redistributing modified binaries or source.
