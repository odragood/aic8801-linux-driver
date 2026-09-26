#!/bin/sh
# Build helper for DKMS: CachyOS and other distros ship clang-built kernels,
# which require LLVM=1 (their CFLAGS contain clang-only options).
set -e

KVER="${1:-$(uname -r)}"
CONF="/lib/modules/$KVER/build/.config"

if [ -f "$CONF" ] && grep -q '^CONFIG_CC_IS_CLANG=y' "$CONF"; then
    exec make -j"$(nproc)" LLVM=1 KVER="$KVER"
fi
exec make -j"$(nproc)" KVER="$KVER"
