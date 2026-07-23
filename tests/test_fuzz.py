import os
import pathlib
import random
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from fuzz_driver import fuzz_one  # noqa: E402
from test_cemod import wps_image  # noqa: E402
from cemodlib import inspect_wups  # noqa: E402


class FuzzSmokeTests(unittest.TestCase):
    def test_mutated_wps_inputs_are_rejections_not_crashes(self):
        randomizer = random.Random(0xCE0D)
        seed = wps_image()
        for _ in range(128):
            mutated = bytearray(seed)
            for _ in range(1 + randomizer.randrange(4)):
                mutated[randomizer.randrange(len(mutated))] ^= 1 << randomizer.randrange(8)
            fuzz_one(bytes(mutated))

    def test_corpus_inputs(self):
        corpus = ROOT / "tests/corpus"
        for path in corpus.iterdir():
            with self.subTest(path=path.name):
                data = bytes.fromhex(path.read_text()) if path.suffix == ".hex" else path.read_bytes()
                fuzz_one(data)

    def test_optional_public_plugin_conformance(self):
        path = os.environ.get("CEMOD_WPS_CONFORMANCE_PLUGIN")
        if not path:
            self.skipTest("set CEMOD_WPS_CONFORMANCE_PLUGIN to inspect a public plugin.wps")
        inspect_wups(pathlib.Path(path).read_bytes())


if __name__ == "__main__":
    unittest.main()
