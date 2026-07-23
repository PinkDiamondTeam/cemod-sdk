# SDK conformance and fuzz assets

`test_cemod.py` contains unit, schema, deterministic ZIP, signature, legacy
ELF, WPS, and optional CemuExtend cross-repository tests. `test_fuzz.py`
performs deterministic mutation/property smoke checks and runs every seed in
`corpus/`. `fuzz_driver.py` can be called with files from a larger fuzzer:

```sh
python3 tests/fuzz_driver.py tests/corpus/wps-truncated.hex
```

The C++ cross-repository test is enabled by the existing CemuExtend binaries
or by setting `CEMUEXTEND_WUPS_BINARY` and `CEMUEXTEND_PACKAGE_BINARY`.
Third-party/public `plugin.wps` files are accepted through an explicit test
path or the `verify-wups` CLI; no binary is silently treated as a conformance
plugin, and no third-party binary is vendored without provenance and license
review.
