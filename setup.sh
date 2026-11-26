#!/bin/sh
# Drops this repo's device/kernel/mkinitfs files into a pmaports checkout and
# prints the exact pmbootstrap commands to build and flash from there.
#
# Usage:
#   ./setup.sh [path-to-existing-pmaports-checkout]
#
# With no argument, clones a fresh pmaports checkout into ./pmaports-checkout.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "${1:-}" != "" ]; then
	PMAPORTS="$1"
	if [ ! -d "$PMAPORTS/device" ]; then
		echo "ERROR: '$PMAPORTS' doesn't look like a pmaports checkout (no device/ dir)" >&2
		exit 1
	fi
else
	PMAPORTS="$SCRIPT_DIR/pmaports-checkout"
	if [ ! -d "$PMAPORTS" ]; then
		echo "==> Cloning pmaports (this is the upstream postmarketOS source tree, not this repo)..."
		git clone --branch v25.12 https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS"
	else
		echo "==> Reusing existing checkout at $PMAPORTS"
	fi
fi

echo "==> Copying device-samsung-gta3xlwifi and linux-samsung-gta3xlwifi into $PMAPORTS/device/testing/"
cp -r "$SCRIPT_DIR/pmaports/device-samsung-gta3xlwifi" "$PMAPORTS/device/testing/"
cp -r "$SCRIPT_DIR/pmaports/linux-samsung-gta3xlwifi" "$PMAPORTS/device/testing/"

echo "==> Overwriting main/postmarketos-mkinitfs/ with the CRC32-patched version"
mkdir -p "$PMAPORTS/main/postmarketos-mkinitfs"
cp "$SCRIPT_DIR/pmaports/main-postmarketos-mkinitfs/APKBUILD" "$PMAPORTS/main/postmarketos-mkinitfs/APKBUILD"
cp "$SCRIPT_DIR/pmaports/main-postmarketos-mkinitfs/0001-lzma-use-crc32-checksum.patch" "$PMAPORTS/main/postmarketos-mkinitfs/"
cp "$SCRIPT_DIR/pmaports/main-postmarketos-mkinitfs/postmarketos-mkinitfs.post-upgrade" "$PMAPORTS/main/postmarketos-mkinitfs/" 2>/dev/null || true
cp "$SCRIPT_DIR/pmaports/main-postmarketos-mkinitfs/postmarketos-mkinitfs.trigger" "$PMAPORTS/main/postmarketos-mkinitfs/" 2>/dev/null || true

cat <<EOF

==> Done. Files are in place at: $PMAPORTS

Next steps (needs pmbootstrap: https://postmarketos.org/pmbootstrap):

    cd "$PMAPORTS"
    pmbootstrap init                       # vendor: samsung, device: gta3xlwifi, edge/v25.12 channel
    pmbootstrap build postmarketos-mkinitfs
    pmbootstrap build linux-samsung-gta3xlwifi
    pmbootstrap install --android-recovery-zip --password "1234"

Then flash the resulting recovery zip from TWRP, same as any other
heimdall-bootimg postmarketOS device. See this repo's README.md for the
background on what these two patches actually fix, and for known remaining
issues (USB gadget / networking in the initramfs, root fs resize warning).

Do NOT build by manually entering a raw chroot and running "make" yourself -
it silently falls back to slow QEMU emulation. Always use "pmbootstrap build
<pkgname>", which picks the fast cross-compiler automatically.
EOF
