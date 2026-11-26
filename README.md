# postmarketOS on Samsung Galaxy Tab A 10.1 (2019) — SM-T510 / gta3xlwifi

Status: **root filesystem mounts and `switch_root` succeeds** on real hardware — the
boot blocker that stopped this device port from ever reaching userspace is fixed.
This is, as far as we could determine, the first time this exact device/kernel/
bootloader combination has been confirmed booting past the initramfs stage.

Device: Samsung Galaxy Tab A 10.1 (2019) Wi-Fi, SM-T510, Exynos 7904
(`universal7885` family), codename `samsung-gta3xlwifi`.

## Credit

This builds entirely on prior work by **Mollomm1** (device port, near-mainline
kernel fork, [`uniLoader`](https://github.com/Mollomm1/uniLoader-t510) secondary
bootloader) and the postmarketOS project. Nothing here is a from-scratch port —
it is two concrete bug fixes on top of their existing, previously non-booting
work, found and verified on real hardware.

## Architecture (for context)

```
Samsung stock bootloader
  -> loads boot.img "kernel" section = uniLoader (secondary bootloader)
  -> uniLoader relocates its embedded Linux kernel Image + DTB + initramfs
     to fixed physical addresses and jumps into the kernel
  -> Linux kernel (6.15-rc1, near-mainline) unpacks the initramfs
  -> postmarketos-mkinitfs's /init script mounts the real root filesystem
     and switch_root's into it
```

uniLoader is needed because this bootloader cannot speak the modern,
device-tree-only boot protocol a near-mainline kernel expects; it embeds the
kernel/dtb/initramfs inside itself at build time and relocates them into RAM
by hand before jumping to the kernel.

## The two bugs that blocked boot

### 1. Ramdisk physical address mismatch (DTS vs. uniLoader config)

uniLoader copies the real initramfs to a fixed physical address given by
`CONFIG_RAMDISK_ENTRY` in its board defconfig. For this device that address is
**`0x84000000`** (see `uniloader-t510-reference/gta3xl_defconfig`).

The device's kernel DTS (`exynos7904-t510.dts`), however, still hardcoded
`linux,initrd-start = <0x89000000>` — a leftover from an older, different
uniLoader board config (`SAMSUNG_T510`, generic `Mollomm1/uniLoader` repo,
which used `0x89000000`). uniLoader-t510 is also supposed to patch this at
runtime via `patch_dtb()` (`ramdisk_handler_patch_dtb`, libfdt), but in
practice the kernel still found nothing at `0x89000000` since that's simply
the wrong address for where the data actually ends up — and nothing at all
was logged about it (silence, not an error), making this very hard to find
without live kernel console access.

**Fix:** hardcode the DTS's `linux,initrd-start`/`linux,initrd-end` to match
`CONFIG_RAMDISK_ENTRY` (`0x84000000`–`0x86000000`). See the diff in
`pmaports/linux-samsung-gta3xlwifi/exynos7904-t510.dts`.

### 2. Initramfs compressed with an XZ checksum the kernel can't decode

Once the initramfs was found at the right address, the kernel panicked with:

```
Initramfs unpacking failed: Input was encoded with settings that are not
supported by this XZ decoder
```

`postmarketos-mkinitfs` (pinned at v2.7.0 in pmaports) compresses the
`lzma`-format initramfs using the default settings of the
[`github.com/ulikunitz/xz`](https://github.com/ulikunitz/xz) Go library,
which defaults to a **CRC64** integrity check. Linux's in-kernel XZ decoder
(`xz_dec`, used to decompress the initramfs before any userspace or even
`CONFIG_MODULES` exist) is deliberately built without CRC64 support to save
code size — it only supports CRC32/none. Any XZ stream checksummed with
CRC64 is permanently and silently non-bootable as a kernel-loaded initramfs,
regardless of how it got there.

This exact problem had already been fixed upstream, but after the 2.7.0 tag:
[postmarketos-mkinitfs!56](https://gitlab.postmarketos.org/postmarketOS/postmarketos-mkinitfs/-/work_items/56),
fixed on the `main` branch:

```go
case FormatLzma:
    cfg := xz.WriterConfig{
        // Linux does not support crc64
        CheckSum: xz.CRC32,
    }
    compressor, err = cfg.NewWriter(fd)
```

**Fix:** backport that one-line fix as a patch on top of the pinned 2.7.0
release. See `pmaports/main-postmarketos-mkinitfs/0001-lzma-use-crc32-checksum.patch`.

Confirmed before/after with `file boot/initramfs`:
```
before: XZ compressed data, checksum CRC64
after:  XZ compressed data, checksum CRC32
```

## How this was found

Photographing the framebuffer console raced against the boot/panic (sub-second
window, no way to get a usable photo in time) and the kernel's own persistent-
storage crash logging (`pstore`/`ramoops`, `pstore_blk`) couldn't be read back
either (TWRP's kernel doesn't share the same reserved-memory layout, and
registers its own backend too late to catch an early panic). The breakthrough
was enabling a **USB gadget serial console** (`CONFIG_USB_G_SERIAL=y` +
`CONFIG_U_SERIAL_CONSOLE=y` — the second one is easy to miss, it's a *separate*
Kconfig symbol from `USB_G_SERIAL` and gates whether the gadget can be used as
a kernel `console=` target at all) with `console=ttyGS0,115200` on the kernel
command line, read live on the host with a small Python/pyserial script. That
finally made the real kernel log (not just what fits on screen before a panic)
readable, which is what surfaced both bugs above.

The gadget's console ring buffer (`GS_CONSOLE_BUF_SIZE`, 8 KiB by default in
`drivers/usb/gadget/function/u_serial.c`) also had to be enlarged (here: to
256 KiB) via a kernel patch, since the default was too small to survive the
burst of driver-probe messages before USB enumeration on the host side
completes — see
`pmaports/linux-samsung-gta3xlwifi/0001-increase-u_serial-console-buffer.patch`.

## Repo layout

- `pmaports/device-samsung-gta3xlwifi/` — device package, unmodified from
  Mollomm1's fork.
- `pmaports/linux-samsung-gta3xlwifi/` — kernel package. Diff against
  Mollomm1's original is: the DTS ramdisk-address fix, the console-buffer
  patch, and (for debugging) `CONFIG_USB_G_SERIAL`/`CONFIG_U_SERIAL_CONSOLE`/
  `rootdelay=15` in the kernel config/cmdline. The ramdisk-address fix should
  stay; the USB-console/rootdelay bits were a debugging aid and can be
  reverted once the port is otherwise stable.
- `pmaports/main-postmarketos-mkinitfs/` — the one-line CRC32 patch that needs
  to go on top of pmaports' pinned `postmarketos-mkinitfs` 2.7.0, plus the
  (otherwise unmodified) `APKBUILD` it's applied to.
- `uniloader-t510-reference/` — the exact uniLoader source files
  (`boot.c`, `gta3xl_defconfig`) this was built against, for reference. The
  full uniLoader-t510 source itself is at
  <https://github.com/Mollomm1/uniLoader-t510> and was **not modified**.
- `docs-debug-journey.md` — the full, blow-by-blow debugging log from the
  session that found these two bugs, kept for context on dead ends that don't
  need to be repeated.

## How to build

### Quick start

```sh
git clone https://github.com/MachuraHarry/pmos-samsung-gta3xlwifi
cd pmos-samsung-gta3xlwifi
./setup.sh                 # clones pmaports and drops these files into it
                            # (or: ./setup.sh /path/to/existing/pmaports)
```

`setup.sh` clones [pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports)
(`v25.12` branch) if you don't already have a checkout, copies
`device-samsung-gta3xlwifi`/`linux-samsung-gta3xlwifi` into
`device/testing/`, drops in the already-patched `postmarketos-mkinitfs`
package, and prints the exact `pmbootstrap` commands to build and flash from
there. It requires `git`; `pmbootstrap` itself you need to
[install separately](https://postmarketos.org/pmbootstrap).

### Manual steps (what the script does)

1. Check out [pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports)
   (this was done against the `v25.12` branch) and drop in
   `pmaports/device-samsung-gta3xlwifi/` and
   `pmaports/linux-samsung-gta3xlwifi/` from this repo under `device/testing/`.
2. Copy `pmaports/main-postmarketos-mkinitfs/` over pmaports'
   `main/postmarketos-mkinitfs/` (already has the patch applied, `pkgrel`
   bumped, and checksums updated).
3. `pmbootstrap init` with vendor `samsung`, device `gta3xlwifi`.
4. `pmbootstrap build postmarketos-mkinitfs` and
   `pmbootstrap build linux-samsung-gta3xlwifi` — use the default
   cross-compile path (don't drop into a raw QEMU chroot and call `make`
   directly; that silently falls back to QEMU emulation and is 10-50x slower
   for no reason, see `docs-debug-journey.md`).
5. `pmbootstrap install --android-recovery-zip --password "<pw>"`.
6. Flash the resulting zip via TWRP, same as any other `heimdall-bootimg`
   postmarketOS device.

## Known remaining issues

- `UDC core: g1: couldn't find an available UDC or it's busy` /
  `Couldn't write new UDC` during the initramfs's own USB gadget (networking)
  setup — likely contention with the debug USB serial console gadget
  (`g_serial`) still holding the UDC. Should resolve on its own once the
  `CONFIG_USB_G_SERIAL` debugging config is reverted for normal use; not yet
  independently confirmed.
- DHCP/network setup in the initramfs found no interface (consequence of the
  above).
- Root partition resize was skipped ("no free space left") and e2fsck flagged
  the root filesystem as needing a manual `e2fsck -f` pass — not yet
  investigated, may be unrelated to the two bugs above.

## Seen it in action

Full post-`switch_root` boot into XFCE/X11 is confirmed working — this is the
actual tablet running [**jarvis**](https://github.com/MachuraHarry/jarvis), a
German-language voice assistant (Claude Code as the brain, Vosk for offline
wake-word/speech recognition, a WebKitGTK fullscreen HUD) as its daily-driver
desktop environment. If you want to see what a real application looks like
running on top of this port, that's the best proof.
