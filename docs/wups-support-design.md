# WUPS support design for cemod-sdk

This document is the contract implemented by this repository.  The SDK owns
the `.cemod` container, manifest schema, deterministic package generation,
Ed25519 detached signatures, and host-side WPS/RPL inspection.  It does not
execute guest PPC code, emulate WUPS/WUMS services, or claim that an
unsupported Cemu runtime feature succeeded.

## Architecture and boundaries

`package_cemod.py` and `verify_cemod.py` share the pure-Python `cemodlib.py`
validation layer.  The layer is deliberately independent of
WiiUPluginLoaderBackend source code and mirrors the observable public binary
contract:

```text
manifest.json + payload
        |
        v
  cemodlib validation
        |
  deterministic ZIP / signature digest
        |
  verify + inspect reports
```

On the Cemu side, the payload abstraction is `cemod_elf` or `wups`; WUPS is a
payload format under `trusted_native`, never an `execution_mode`.  Runtime
code must dispatch a WUPS package to a WUPS payload instance and must not pass
`plugin.wps` through the legacy CMB1 ELF bootstrap path.  Runtime ownership,
guest callbacks, WUMS modules, GUI state, storage handles, and patch
transactions remain CemuExtend responsibilities and are outside this SDK.

## Package format and compatibility

The container contains `manifest.json`, exactly one of `mod.elf` and
`plugin.wps`, and optionally both `public_key.ed25519` (32 raw bytes) and
`signature.ed25519` (64 raw bytes).  ZIP entry names are checked for absolute
paths, traversal, controls, separators, duplicate normalized names, unknown
entries, encryption, expansion size, and a 200:1 compression ratio limit.

Package version 1 selects `mod.elf` when `payload` is absent.  Package version
2 requires the exact descriptor `{ "format": ..., "path": ... }`, with
`cemod_elf/mod.elf` or `wups/plugin.wps`.  WUPS requires `trusted_native`.
Version 2 `scope` supports `process` with one to sixteen known Aroma process
targets or `aroma_native`; `permissions` is validated as a closed object with
typed filesystem and module fields.  Isolated manifests retain the original
resource limits and `cemod_init` entrypoint contract.

The signature digest is exactly:

1. sort entry names by their UTF-8 byte spelling;
2. omit only `signature.ed25519`;
3. append big-endian `u32(name byte length)`, name bytes,
   big-endian `u64(uncompressed length)`, and SHA-256(entry bytes) for each;
4. SHA-256 the resulting byte stream;
5. Ed25519-sign that 32-byte digest.

This is the same field order and byte order used by CemuExtend's package
inspector.  Private keys are read only by OpenSSL, never placed in the ZIP,
and all output is written to a sibling temporary file and renamed only after
validation/signature work succeeds.

## WPS/RPL inspection

`inspect_wups` validates the ELF32 big-endian PPC `PL` marker, section table,
section count, bounds, alignment, compression envelope, CRC and FILEINFO
regions, allocated virtual ranges, TLS flags, symbol/string tables, RPL
imports/exports, REL/RELA relocation widths and supported types, and the
required `.wups.meta` and `.wups.hooks` sections.  `.wups.load` descriptors
are parsed as the public 36-byte WUPS layout and distinguish optional,
mandatory, and legacy entries, physical/virtual address patches, call-through
storage, replacement functions, and process targets.

Metadata is copied into ordinary host-owned values.  Required `name` and
`wups` keys, supported ABI versions `0.7.1`, `0.8.1`, `0.8.2`, `0.9.0`, and
`0.9.1`, storage identifiers, debug flags, duplicate keys, termination, and
unknown-key retention are handled explicitly.  Unknown ABI versions and
malformed versions fail with the plugin name, detected version, and supported
range.  Unknown WUMS sections are not treated as valid WUPS runtime support;
`inspect_wups` reports only data present in the image.

## Runtime mapping contract

When CemuExtend consumes this SDK contract, its runtime must keep these
separate:

- `CemodElfPayloadRuntime`: existing CMB1/native ELF behavior;
- `WupsPayloadRuntime`: RPL link/load, WUPS metadata and lifecycle;
- `WumsModuleRuntime`: `.wms` module graph, typed export registry, relocation
  and lifecycle;
- `WupsFunctionPatchManager`: transactional named, physical, and virtual
  patches with REL24/far trampolines, owner/generation tracking, cache
  invalidation, conflict detection, restoration, and dynamic-RPL hooks.

The SDK never resolves an import to zero or to a dummy success function.  A
runtime resolver should use this order and report package ID, plugin/module,
module name, symbol, function/data kind, mandatory/optional state, and ABI:

1. ordinary Cafe OS RPL exports;
2. Cemu HLE exports;
3. WUPS backend exports;
4. WUMS module exports;
5. standard Aroma module exports;
6. explicitly registered custom `.wms` exports.

Mandatory unresolved imports fail the owning payload.  Optional imports are
skipped only when the public ABI marks them optional.  Function and data
exports are separate registry entries; module name/version collisions,
duplicate exports, and circular dependencies are deterministic failures.

## Lifecycle, ownership, TLS, and threading

The guest runtime must call WUT initialization hooks in loader order and
cleanup hooks in reverse order, roll back completed stages on failure, skip
undefined hooks, and isolate failure to the owning plugin/module.  It must
invoke guest callbacks through Cemu's PPC callback mechanism, preserving guest
stack alignment, r2/r13, LR/CTR, register save rules, ABI arguments/returns,
TLS, and per-thread reent context.  Host function-pointer casts of guest
addresses are prohibited.

Every plugin/module owns its RPL allocation, text/data/BSS/TLS, trampolines,
WUT/newlib resources, patches, callbacks, storage/config/button-combo handles,
mapped memory, notifications, mounts, sockets, dynamic references, and
threads.  Unload first blocks new callbacks, increments the generation,
removes patches and callbacks, then releases resources in reverse dependency
order.  Callback completion rechecks owner and generation.

For a runtime implementation the lock order is:

```text
title/process state -> module graph -> owner resource state -> subsystem state
```

No lock is held while guest code, a GUI callback, or an external filesystem
operation runs.  Title end, foreground transitions, dynamic RPL events, and
unload are serialized through the process/title state machine.

## Permissions and security

Manifest permissions are declarations, not grants.  Package inspection can
report inferred use of native memory, function/fixed-address patching,
filesystem, network, mapped memory, notifications, content redirection, and
required modules.  CemuExtend must compare these to approval before load and
recheck at each runtime API boundary.  Module imports do not auto-grant
permissions; unsupported hardware-only behavior must return an explicit
unsupported error and log owner, module/export, call site, safe argument
summary, and reason.

ZIP parsing is transactional: no partially validated package state is exposed.
All untrusted counts, offsets, sizes, compressed lengths, pointers, strings,
section ranges, and descriptor arrays are bounded before use.  The SDK treats
guest addresses as integers and never host-casts them.

## Standard Aroma modules and CEX2

FunctionPatcher, MemoryMapping, Notification, Logging, ContentRedirection,
WiiUPluginLoaderBackend, and WUMSLoader compatibility are runtime services,
not SDK parser features.  CemuExtend may provide HLE mappings where they have
meaning; physical hardware, kernel exploit, IOSU, real SD physical mapping,
USB serial, and kernel-only cache operations must be rejected as unsupported
when they cannot be represented safely.  WUPS remains optional with respect
to CEX2; a runtime must keep plugin ownership and CEX2 ownership distinct and
perform normal CEX2 session cleanup.

## Testing and conformance

The SDK tests cover manifest v1/v2, ZIP path and expansion attacks, payload
selection, deterministic output, Ed25519 signing, legacy CMB1 ELF validation,
WPS sections/CRC/compression/TLS, metadata/hooks/load descriptors,
imports/exports/relocations, permission warnings, and atomic failure.  A
cross-repository test passes the generated WPS fixture and signed package to
the CemuExtend test binaries when available via `CEMUEXTEND_WUPS_BINARY` and
`CEMUEXTEND_PACKAGE_BINARY` (or the sibling build path).

The fuzz driver accepts raw WPS, manifest, or `.cemod` inputs and converts
parser exceptions into ordinary rejected inputs.  Corpus files are malformed
seeds, not claims of executable runtime support.  A public plugin can be
checked by setting `CEMOD_WPS_CONFORMANCE_PLUGIN` and invoking `verify-wups`;
the repository does not vendor third-party binaries without a license and
stable provenance.

## License boundary and definition of complete SDK support

This repository contains an independent parser and build tool under its
existing project terms.  It does not copy GPL implementation code from
WiiUPluginLoaderBackend or WUMSLoader.  Public headers, ABI constants, binary
layout, and observable error behavior may be used as specifications; copied
implementation code is not.

SDK support is complete when both payload forms package, verify, inspect, and
round-trip through the canonical digest; v1/v2 manifests remain compatible;
malformed inputs fail safely; and C++ cross-repo conformance accepts the same
valid WPS and signed package.  Guest lifecycle execution, patch application,
WUMS loading, GUI, and hardware-only APIs are not claimed by this SDK and
must be reported as runtime limitations until implemented in CemuExtend.
