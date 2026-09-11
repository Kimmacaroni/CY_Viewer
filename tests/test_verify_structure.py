from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPOSITORY_ROOT / "scripts/verify_structure.py"
SPEC = importlib.util.spec_from_file_location("verify_structure", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
verify_structure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify_structure)


class VerifyStructureTests(unittest.TestCase):
    def test_current_repository_structure_passes(self) -> None:
        self.assertEqual(verify_structure.validate(REPOSITORY_ROOT), [])

    def test_missing_implementations_are_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            errors = verify_structure.validate(Path(directory))
        for implementation in verify_structure.IMPLEMENTATIONS:
            self.assertTrue(
                any(implementation in error for error in errors),
                f"누락 구현체가 보고되지 않음: {implementation}",
            )


if __name__ == "__main__":
    unittest.main()
