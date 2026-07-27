# syntax=docker/dockerfile:1.7
#
# Generic build images for cemod-sdk projects, selected via `--target`:
#   builder       devkitPPC + short-wchar-stdlib toolchain, produces the
#                 trusted-native ELF payload (default target).
#   wups-builder  the `builder` toolchain plus a WUPS (Wii U Plugin System)
#                 toolchain built from the project's own
#                 third_party/toolchains/WiiUPluginSystem/, for the WUPS
#                 plugin payload.
#
# The default build context MUST be the consuming project's root directory
# (not this SDK directory) so the ARG-selected devkitPPC vendor archive below
# resolves against the project's own infra/docker/vendor/devkitPPC/
# directory, and so wups-builder's WiiUPluginSystem COPY resolves against
# the project's own third_party/toolchains/WiiUPluginSystem/. A second named
# context "sdk" must point at this SDK's infra/docker/image/ directory (the
# directory this Dockerfile itself lives in) so the stdlib build script and
# patch can be copied in without duplicating them into every project.
# compose.yaml wires both contexts up via docker compose's
# `additional_contexts`.
ARG BASE_IMAGE=ghcr.io/wiiu-env/devkitppc:20260225@sha256:472118aa3d2a1ebb62691e9ae18a21d4d8f14238d688d679c30f5973dc9d9f35
ARG WUPS_BASE_IMAGE=ghcr.io/wiiu-env/devkitppc:20260504@sha256:68785e7d75b070b0aea03272b61f36dd2fddfda4f442cdf0e27b168bd36a09fb

FROM ${BASE_IMAGE} AS builder

ARG DEVKITPPC_ARCHIVE=infra/docker/vendor/devkitPPC/devkitPPC-r46.1-1-linux_x86_64.pkg.tar.zst
ARG DEVKITPPC_SHA256=6695ecfe062ede7b041cdcefc8aaaa997fdb0a61d727626197f1089b4ad75b8c

# Use the same vendored native Linux devkitPPC toolchain the project pins.
# The archive checksum is also verified by docker-build.sh before Docker runs.
COPY ${DEVKITPPC_ARCHIVE} /tmp/devkitPPC.pkg.tar.zst
RUN echo "${DEVKITPPC_SHA256}  /tmp/devkitPPC.pkg.tar.zst" | sha256sum -c - \
    && rm -rf /opt/devkitpro/devkitPPC \
    && bsdtar -xf /tmp/devkitPPC.pkg.tar.zst -C / \
    && rm /tmp/devkitPPC.pkg.tar.zst \
    && /opt/devkitpro/devkitPPC/bin/powerpc-eabi-gcc --version | grep '14.2.0'

ENV DEVKITPRO=/opt/devkitpro \
    DEVKITPPC=/opt/devkitpro/devkitPPC \
    PATH=/opt/devkitpro/devkitPPC/bin:${PATH}

COPY --from=sdk build-short-wchar-stdlib.sh gcc-14.2.0-enable-devoptab-chmod.patch /tmp/
RUN --mount=type=cache,target=/var/cache/mcwiiu-stdlib \
    sh /tmp/build-short-wchar-stdlib.sh \
    && rm /tmp/build-short-wchar-stdlib.sh

WORKDIR /project
CMD ["sh", "-c", "sh \"$CEMOD_SDK_ROOT/infra/docker/container/container-build.sh\""]

# elf2rpl/readrpl ship prebuilt in BASE_IMAGE already (inherited via the
# `builder` stage below), so there is no wut-tools build stage here -- only
# the WiiUPluginSystem library itself.
FROM ${WUPS_BASE_IMAGE} AS wups-toolchain
WORKDIR /src/WiiUPluginSystem
COPY third_party/toolchains/WiiUPluginSystem/ ./
RUN make clean && make -j"$(nproc)" \
    && mkdir -p /artifacts/wups /artifacts/devkitPPC \
    && cp -a lib include share /artifacts/wups/ \
    && cp /opt/devkitpro/devkitPPC/base_rules /opt/devkitpro/devkitPPC/base_tools /artifacts/devkitPPC/

FROM builder AS wups-builder
COPY --from=wups-toolchain /artifacts/ /opt/devkitpro/
RUN test "$(powerpc-eabi-gcc -dumpfullversion)" = "14.2.0" \
    && test -f /opt/devkitpro/mcwiiu-stdlib/.wchar16 \
    && test -f /opt/devkitpro/devkitPPC/base_rules \
    && test -f /opt/devkitpro/wups/share/wups_rules \
    && test -f /opt/devkitpro/wups/lib/libwups.a \
    && test -x /opt/devkitpro/tools/bin/elf2rpl \
    && test -x /opt/devkitpro/tools/bin/readrpl
CMD ["sh", "-c", "sh \"$CEMOD_SDK_ROOT/infra/docker/container/container-build-wups.sh\""]
