#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEVOPTAB_CHMOD_PATCH="$SCRIPT_DIR/gcc-14.2.0-enable-devoptab-chmod.patch"
test -s "$DEVOPTAB_CHMOD_PATCH"

# Rebuild the parts of devkitPPC r46.1 whose ABI depends on wchar_t. GCC is
# also rebuilt with assembler TLS disabled: a codecave is entered with
# Minecraft's r2 value, so PowerPC's native TLS ABI is unsafe here. GCC then
# lowers C++ thread_local objects to libgcc's __emutls_* implementation, which
# uses the dkp gthread backend supplied by src/runtime/GThread.cpp.
GCC_VERSION=14.2.0
NEWLIB_VERSION=4.4.0.20231231
DKP_BUILDSCRIPTS_COMMIT=1b09b3a82495da820885f8102726c47247f5b05a
PREFIX=/opt/devkitpro/mcwiiu-stdlib
GCC_PREFIX=/opt/devkitpro/mcwiiu-gcc
WORK=/tmp/mcwiiu-stdlib-build
DOWNLOADS=/var/cache/mcwiiu-stdlib
JOBS=${JOBS:-}

if [ -z "$JOBS" ]; then
    JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fi

fetch()
{
    url=$1
    destination=$2
    checksum=$3
    if [ ! -f "$destination" ]; then
        curl --fail --location --retry 4 --output "$destination" "$url"
    fi
    printf '%s  %s\n' "$checksum" "$destination" | sha256sum -c -
}

rm -rf "$PREFIX" "$GCC_PREFIX" "$WORK"
mkdir -p "$DOWNLOADS" "$PREFIX" "$WORK"

fetch \
    "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz" \
    "$DOWNLOADS/gcc-$GCC_VERSION.tar.xz" \
    a7b39bc69cbf9e25826c5a60ab26477001f7c08d85cec04bc0e29cabed6f3cc9
fetch \
    "https://sourceware.org/pub/newlib/newlib-$NEWLIB_VERSION.tar.gz" \
    "$DOWNLOADS/newlib-$NEWLIB_VERSION.tar.gz" \
    0c166a39e1bf0951dfafcd68949fe0e4b6d3658081d6282f39aeefc6310f2f13
fetch \
    "https://raw.githubusercontent.com/devkitPro/buildscripts/$DKP_BUILDSCRIPTS_COMMIT/dkppc/patches/gcc-$GCC_VERSION.patch" \
    "$DOWNLOADS/gcc-$GCC_VERSION.patch" \
    2b73fec6d4e04c4559a67aa8c73ebb7b15a941b51b0dab674694387c42dac75f
fetch \
    "https://raw.githubusercontent.com/devkitPro/buildscripts/$DKP_BUILDSCRIPTS_COMMIT/dkppc/patches/newlib-$NEWLIB_VERSION.patch" \
    "$DOWNLOADS/newlib-$NEWLIB_VERSION.patch" \
    c149a64d20673a6a08ceac5f78e4a9eeca5486103454aea5087ace21dbcbbac0

tar -xf "$DOWNLOADS/gcc-$GCC_VERSION.tar.xz" -C "$WORK"
tar -xf "$DOWNLOADS/newlib-$NEWLIB_VERSION.tar.gz" -C "$WORK"
patch -p1 -d "$WORK/gcc-$GCC_VERSION" -i "$DOWNLOADS/gcc-$GCC_VERSION.patch"
patch -p1 -d "$WORK/gcc-$GCC_VERSION" -i "$DEVOPTAB_CHMOD_PATCH"
patch -p1 -d "$WORK/newlib-$NEWLIB_VERSION" -i "$DOWNLOADS/newlib-$NEWLIB_VERSION.patch"

mkdir -p "$WORK/build-newlib"
cd "$WORK/build-newlib"
MAKEINFO=true \
CFLAGS_FOR_TARGET='-O2 -ffunction-sections -fdata-sections -fshort-wchar -msdata=none -DCUSTOM_MALLOC_LOCK' \
    "$WORK/newlib-$NEWLIB_VERSION/configure" \
        --target=powerpc-eabi \
        --prefix="$PREFIX" \
        --enable-newlib-mb \
        --enable-newlib-register-fini
make MAKEINFO=true -j"$JOBS"
make MAKEINFO=true install -j1

# GCC's own prerequisite script carries SHA-512 checksums for these exact
# archives. Graphite/ISL is unnecessary for the target compiler. Build GCC
# after newlib so its driver has the final target headers available.
cd "$WORK/gcc-$GCC_VERSION"
mkdir -p "$DOWNLOADS/gcc-prerequisites"
./contrib/download_prerequisites --no-isl --directory="$DOWNLOADS/gcc-prerequisites"

mkdir -p "$WORK/build-gcc"
cd "$WORK/build-gcc"
MAKEINFO=true \
    "$WORK/gcc-$GCC_VERSION/configure" \
        --target=powerpc-eabi \
        --prefix="$GCC_PREFIX" \
        --with-newlib \
        --with-headers="$PREFIX/powerpc-eabi/include" \
        --enable-languages=c,c++ \
        --enable-threads=dkp \
        --disable-tls \
        --disable-analyzer \
        --disable-shared \
        --disable-multilib \
        --disable-nls \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --disable-libsanitizer
make MAKEINFO=true -j"$JOBS" all-gcc
make MAKEINFO=true -j1 install-gcc

GCC_EXEC="$GCC_PREFIX/libexec/gcc/powerpc-eabi/$GCC_VERSION"
PATH="/opt/devkitpro/devkitPPC/bin:$PATH"
export PATH
test -x "$GCC_EXEC/cc1"
test -x "$GCC_EXEC/cc1plus"

# Configure libstdc++ as a target library using the codecave-safe GCC. The
# devkitPro GCC patch supplies the dkp gthread model used by src/runtime/GThread.cpp.
mkdir -p "$WORK/build-libstdcxx"
# A full GCC build generates this forwarding header in the top-level libgcc
# build directory. A standalone libstdc++ configure needs the same file for its
# gthread capability probe.
mkdir -p "$WORK/build-libstdcxx/libgcc"
cp "/opt/devkitpro/devkitPPC/powerpc-eabi/include/c++/$GCC_VERSION/powerpc-eabi/bits/gthr-default.h" \
    "$WORK/build-libstdcxx/libgcc/gthr-default.h"
cd "$WORK/build-libstdcxx"
MAKEINFO=true \
glibcxx_cv_dev_random=yes \
CC="powerpc-eabi-gcc -B$GCC_EXEC/" \
CXX="powerpc-eabi-g++ -B$GCC_EXEC/" \
AR=powerpc-eabi-ar \
AS=powerpc-eabi-as \
LD=powerpc-eabi-ld \
NM=powerpc-eabi-nm \
RANLIB=powerpc-eabi-ranlib \
STRIP=powerpc-eabi-strip \
CFLAGS='-O2 -ffunction-sections -fdata-sections -fshort-wchar -msdata=none' \
CPPFLAGS="-isystem $PREFIX/powerpc-eabi/include" \
CXXFLAGS="-O2 -ffunction-sections -fdata-sections -fshort-wchar -msdata=none -isystem $PREFIX/powerpc-eabi/include" \
    "$WORK/gcc-$GCC_VERSION/libstdc++-v3/configure" \
        --build="$("$WORK/gcc-$GCC_VERSION/config.guess")" \
        --host=powerpc-eabi \
        --target=powerpc-eabi \
        --prefix="$PREFIX" \
        --with-newlib \
        --with-gxx-include-dir="$PREFIX/include/c++/$GCC_VERSION" \
        --enable-libstdcxx-threads=yes \
        --disable-shared \
        --disable-multilib \
        --disable-nls \
        --disable-libstdcxx-pch \
        --disable-libstdcxx-verbose \
        --enable-libstdcxx-time=yes \
        --enable-libstdcxx-filesystem-ts

# The standalone configure probe uses GCC top-level build paths that are only
# fully populated by a complete compiler rebuild. The r46.1 dkp header above
# defines __GTHREADS_CXX0X and our payload provides every __gthr_impl_* entry,
# so make that known to both the library build and installed target headers.
for config in config.h include/powerpc-eabi/bits/c++config.h; do
    sed -i 's@/\* #undef _GLIBCXX_HAS_GTHREADS \*/@#define _GLIBCXX_HAS_GTHREADS 1@' "$config"
    grep -q '^#define _GLIBCXX_HAS_GTHREADS 1' "$config"
done
make MAKEINFO=true -j"$JOBS"
make MAKEINFO=true install -j1

# Keep the payload Makefile independent of libtool's target-specific layout.
mkdir -p "$PREFIX/lib"
find "$PREFIX" -type f \( \
        -name 'libc.a' -o -name 'libm.a' -o \
        -name 'libstdc++.a' -o -name 'libstdc++exp.a' -o \
        -name 'libstdc++fs.a' -o -name 'libsupc++.a' \
    \) -exec cp -f '{}' "$PREFIX/lib/" ';'

test -s "$PREFIX/lib/libc.a"
test -s "$PREFIX/lib/libm.a"
test -s "$PREFIX/lib/libstdc++.a"
test -s "$PREFIX/lib/libsupc++.a"
test -f "$PREFIX/include/c++/$GCC_VERSION/powerpc-eabi/bits/c++config.h"

cat > "$WORK/wchar-check.cpp" <<'EOF'
#include <string>
static_assert(sizeof(wchar_t) == 2);
static_assert(sizeof(std::wstring::value_type) == 2);
int main() { std::wstring value = L"Cafe"; return value.size() == 4 ? 0 : 1; }
EOF
powerpc-eabi-g++ -B"$GCC_EXEC/" -std=gnu++20 -fshort-wchar -nostdinc++ \
    -isystem "$PREFIX/powerpc-eabi/include" \
    -isystem "$PREFIX/include/c++/$GCC_VERSION" \
    -isystem "$PREFIX/include/c++/$GCC_VERSION/powerpc-eabi" \
    -c "$WORK/wchar-check.cpp" -o "$WORK/wchar-check.o"

cat > "$WORK/tls-check.cpp" <<'EOF'
thread_local int value = 7;
int read_tls() { return value; }
EOF
powerpc-eabi-g++ -B"$GCC_EXEC/" -std=gnu++20 -fshort-wchar -c "$WORK/tls-check.cpp" \
    -o "$WORK/tls-check.o"
if powerpc-eabi-readelf -SW "$WORK/tls-check.o" | grep -Eq '\.(tdata|tbss)'; then
    echo "compiler emitted native PowerPC TLS instead of emulated TLS" >&2
    exit 1
fi
powerpc-eabi-nm -u "$WORK/tls-check.o" | grep -q '__emutls_get_address'

cat > "$PREFIX/.wchar16" <<EOF
devkitPPC=46.1
gcc=$GCC_VERSION
newlib=$NEWLIB_VERSION
devkitpro_buildscripts=$DKP_BUILDSCRIPTS_COMMIT
cflags=-fshort-wchar
msdata=none
sizeof_wchar_t=2
tls=emulated
EOF

rm -rf "$WORK"
