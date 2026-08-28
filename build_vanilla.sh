#!/usr/bin/env bash
#
# Build chan_roip.so against a vanilla Asterisk source tree (default 20.8.1),
# for a standard glibc Asterisk install (NOT OpenWrt).
#
# Optional env:
#   ASTVER      Asterisk version tag to build against (default 20.8.1)
#   FULL_BUILD  if "1", build the whole Asterisk tree and take chan_roip.so from
#               it (slower, uses Asterisk's own build flags). Default 0 = compile
#               the single module standalone (fast; verified).
#
set -euo pipefail

ASTVER="${ASTVER:-20.8.1}"
SRC=/work/src
OUT=/out/vanilla
JOBS="${JOBS:-$(nproc)}"
FULL_BUILD="${FULL_BUILD:-0}"

echo "==> chan_roip.so against vanilla Asterisk ${ASTVER}"

cd /home/builder
TREE="asterisk-${ASTVER}"
if [ ! -d "$TREE" ]; then
    echo "==> Fetching Asterisk ${ASTVER} source..."
    curl -fSL -o ast.tgz "https://codeload.github.com/asterisk/asterisk/tar.gz/refs/tags/${ASTVER}"
    tar xzf ast.tgz
fi
cd "$TREE"

echo "==> Injecting chan_roip.c (line endings normalised)"
sed 's/\r$//' "${SRC}/chan_roip.c" > channels/chan_roip.c
if [ -f "${SRC}/roip.conf.sample" ]; then
    mkdir -p configs/samples
    sed 's/\r$//' "${SRC}/roip.conf.sample" > configs/samples/roip.conf.sample
fi

echo "==> ./configure"
./configure --without-pjproject >/tmp/conf.log 2>&1 || { echo "configure failed:"; tail -30 /tmp/conf.log; exit 1; }

mkdir -p "$OUT"

if [ "$FULL_BUILD" = "1" ]; then
    echo "==> Full Asterisk build (menuselect + make; slow)"
    make menuselect.makeopts >/tmp/ms.log 2>&1
    menuselect/menuselect --enable chan_roip menuselect.makeopts
    make -j"${JOBS}" >/tmp/make.log 2>&1 || { echo "make failed:"; tail -40 /tmp/make.log; exit 1; }
    cp -v channels/chan_roip.so "$OUT/"
else
    echo "==> Generating Asterisk build headers"
    make include/asterisk/version.h include/asterisk/buildopts.h include/asterisk/build.h \
        >/tmp/hdr.log 2>&1 || { echo "header gen failed:"; tail -20 /tmp/hdr.log; exit 1; }
    echo "==> Compiling chan_roip.so (standalone module build)"
    gcc -shared -fPIC -O2 -std=gnu99 -D_GNU_SOURCE \
        -DAST_MODULE='"chan_roip"' -DAST_MODULE_SELF_SYM=__internal_chan_roip_self \
        -I include -I . \
        channels/chan_roip.c -o chan_roip.so -lasound
    cp -v chan_roip.so "$OUT/"
fi

[ -f "${SRC}/roip.conf.sample" ] && cp -v "${SRC}/roip.conf.sample" "$OUT/" || true

echo "==> DONE. Output in ${OUT}:"
ls -la "$OUT"
echo
echo "Install: copy chan_roip.so to your Asterisk modules dir (e.g. /usr/lib/asterisk/modules/),"
echo "put roip.conf in /etc/asterisk/, then 'module load chan_roip.so' (or autoload)."
echo "NOTE: the module must match your running Asterisk's build options (AST_BUILDOPT_SUM)."
echo "      This is guaranteed when your Asterisk was built from the same ${ASTVER} source."
