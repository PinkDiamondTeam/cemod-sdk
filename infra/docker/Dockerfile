# syntax=docker/dockerfile:1.7
#
# Generic devkitPPC + short-wchar-stdlib build image for cemod-sdk projects.
#
# The default build context MUST be the consuming project's root directory
# (not this SDK directory) so the ARG-selected devkitPPC vendor archive below
# resolves against the project's own infra/docker/vendor/devkitPPC/
# directory. A second named context "sdk" must point at this SDK's
# infra/docker/ directory so the stdlib build script and patch can be copied
# in without duplicating them into every project. cemod.mk's `docker-build`
# target wires both contexts up via docker compose's `additional_contexts`.
ARG BASE_IMAGE=ghcr.io/wiiu-env/devkitppc:20260225@sha256:472118aa3d2a1ebb62691e9ae18a21d4d8f14238d688d679c30f5973dc9d9f35
FROM ${BASE_IMAGE}

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
CMD ["sh", "-c", "sh \"$CEMOD_SDK_ROOT/infra/docker/build.sh\""]
