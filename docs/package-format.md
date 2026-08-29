# Package format

A `.cemod` file is a validated ZIP container. `package_cemod.py` generates a
deterministic archive, while `verify_cemod.py` applies the same manifest,
payload, path, size, and signature rules used by the SDK.

## Container entries

Every package contains:

- `manifest.json`; and
- exactly one of `mod.elf` or `plugin.wps`.

A signed package also contains both `public_key.ed25519` and
`signature.ed25519`. Package version 4 additionally contains one or more files
below `ui/`. Other entries are rejected.

## Common manifest fields

All supported manifests require:

| Field | Rule |
| --- | --- |
| `package_version` | Integer `1`, `2`, `3`, or `4` |
| `api_version` | Integer `2` |
| `execution_mode` | `isolated` or `trusted_native` |
| `mod_id` | 1–128 characters from `A-Z`, `a-z`, `0-9`, `_`, `.`, and `-` |
| `title_ids` | 1–64 non-zero 64-bit title IDs, as integers or hexadecimal strings |
| `requested_permissions` | Unique values from `read`, `write`, `inject`, `clipboard`, `capture`, `network`, and `ui` |

Permissions are requests, not automatic grants. CemuExtend decides whether a
package may use them.

## Version 1

Version 1 is the legacy `mod.elf` format. It must omit `payload`, `scope`, and
`permissions`; the payload is implicitly `cemod_elf/mod.elf`.

```json
{
  "package_version": 1,
  "api_version": 2,
  "execution_mode": "isolated",
  "mod_id": "example-mod",
  "title_ids": ["0005000012345678"],
  "requested_permissions": [],
  "memory": {
    "code_bytes": 1048576,
    "private_bytes": 1048576,
    "stack_bytes": 65536
  },
  "cpu": {
    "instructions_per_frame": 100000,
    "time_us_per_frame": 500
  },
  "entrypoint": "cemod_init"
}
```

## Versions 2 and 3

Versions 2–4 require an exact payload descriptor:

```json
"payload": {"format": "cemod_elf", "path": "mod.elf"}
```

or:

```json
"payload": {"format": "wups", "path": "plugin.wps"}
```

WUPS requires `execution_mode: "trusted_native"`.

An optional `scope` is either an Aroma-native scope:

```json
"scope": {"type": "aroma_native"}
```

or a process scope with 1–16 unique targets:

```json
"scope": {"type": "process", "targets": ["game", "home_menu"]}
```

Accepted target names are `all`, `root_rpx`, `wii_u_menu`, `tvii`, `e_manual`,
`home_menu`, `error_display`, `mini_miiverse`, `browser`, `miiverse`, `eshop`,
`download_manager`, `game`, and `game_and_menu`.

The optional `permissions` object may declare boolean `native_memory`,
`function_patching`, `physical_address_patching`, `network`, `mapped_memory`,
`notifications`, and `content_redirection` capabilities, a typed `filesystem`
object, and up to 64 unique module identifiers. Package version 3 additionally
allows `plugin_management` and trusted-native memory expansion.

```json
{
  "package_version": 3,
  "api_version": 2,
  "execution_mode": "trusted_native",
  "mod_id": "example-mod",
  "title_ids": ["0005000012345678"],
  "requested_permissions": ["read", "network"],
  "payload": {"format": "wups", "path": "plugin.wps"},
  "scope": {"type": "aroma_native"},
  "permissions": {
    "filesystem": {"read": true},
    "network": true,
    "modules": ["homebrew_wupsbackend"]
  },
  "memory": {"mem2_expansion_bytes": 16777216}
}
```

Trusted-native memory expansion must be non-zero, 4 KiB aligned, and no more
than 256 MiB. Trusted-native manifests must not define `cpu` or `entrypoint`.

Isolated manifests require `memory`, `cpu`, and `entrypoint: "cemod_init"`.
The validator bounds code to 16 MiB, private memory to 32 MiB, stack memory to
1 MiB, instructions per frame to 1,000,000, and time per frame to 1,000 µs.
The stack size must be non-zero and 4 KiB aligned.

## Version 4 and Web UI assets

Version 4 requires the `ui` requested permission, a `web_ui` descriptor, and
a non-empty UI directory passed with `--ui-dir` or `CEMOD_UI_DIR`.

```json
{
  "package_version": 4,
  "api_version": 2,
  "execution_mode": "trusted_native",
  "mod_id": "example-mod",
  "title_ids": ["0005000012345678"],
  "requested_permissions": ["ui"],
  "payload": {"format": "wups", "path": "plugin.wps"},
  "scope": {"type": "aroma_native"},
  "web_ui": {
    "bridge_version": 1,
    "views": {
      "main": {
        "entry": "ui/main/index.html",
        "single_instance": true,
        "modes": ["window", "overlay"],
        "window": {
          "title": "Example Mod",
          "width": 960,
          "height": 540,
          "min_width": 640,
          "min_height": 360,
          "resizable": true
        },
        "overlay": {
          "surfaces": ["tv"],
          "z_order": "below_builtin",
          "transparent": true,
          "interactive": false
        }
      }
    }
  }
}
```

There must be 1–16 views. Each entry is an HTML file below `ui/`, and each
overlay declares `z_order` as `below_builtin` or `above_builtin`. The order
also controls input and focus priority relative to Cemu's built-in overlay.

Optional network policy lists exact HTTPS/WSS origins:

```json
"network": {
  "connect": ["wss://example.com"],
  "resources": ["https://static.example.com"],
  "credentials": false,
  "persistent_storage": false,
  "allow_private_network": false
}
```

Network use requires the `network` requested permission. Origins must be
canonical, path-free HTTPS or WSS origins; URL paths, queries, fragments, and
credentials are rejected.

`CEMOD_UI_DIR` is the directory *inside* which the UI paths begin. For example,
`<UI_DIR>/main/index.html` becomes `ui/main/index.html`.

## Signing

Generate an Ed25519 private key with OpenSSL:

```sh
openssl genpkey -algorithm Ed25519 -out signing-key.pem
```

Sign while packaging:

```sh
python3 tools/package_cemod.py \
  --manifest manifest.json \
  --wps build/plugin.wps \
  --ui-dir web-ui/dist \
  --private-key signing-key.pem \
  --output build/example-mod.cemod
```

The private key is never placed in the archive. The packager embeds its raw
32-byte public key and a 64-byte detached signature. An external signer can
instead supply `--public-key` and `--signature` together.

The canonical digest sorts entries by UTF-8 name, omits only
`signature.ed25519`, and commits each name, uncompressed length, and SHA-256
content digest before the final SHA-256/Ed25519 operation. Consequently every
manifest, payload, public-key, or UI byte is covered.

## Validation limits

The SDK enforces, among other structural checks:

| Resource | Limit |
| --- | --- |
| Archive and expanded package | 97 MiB each |
| Payload | 64 MiB |
| Trusted-native ELF | 10 MiB |
| Manifest | 256 KiB |
| ZIP compression ratio | 200:1 |
| WPS sections | 512 |
| UI files | 512 |
| One UI file | 16 MiB |
| All UI files | 32 MiB |

Absolute paths, traversal, backslashes, controls, non-canonical names,
case-normalized duplicates, symbolic links in the source UI tree, encrypted
entries, unknown mandatory entries, and unsafe expansion are rejected.

For the WPS/RPL binary contract and runtime boundary, see
[WUPS support design](wups-support-design.md).
